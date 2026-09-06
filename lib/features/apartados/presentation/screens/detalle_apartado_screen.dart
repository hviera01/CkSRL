import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_model.dart';
import '../../data/apartado_cuota_model.dart';
import '../../data/apartado_abono_model.dart';
import '../../providers/apartados_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/presentation/widgets/acceso_especial.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../widgets/registrar_pago_apartado_dialog.dart';
import '../widgets/editar_abono_apartado_dialog.dart';

/// Detalle completo de un apartado: items, saldo, y -según la modalidad- las
/// cuotas programadas o el historial de abonos libres, con botones para
/// registrar un pago, marcar entregado (descuenta stock físico de verdad,
/// solo si el saldo ya está en 0) o cancelar.
class DetalleApartadoScreen extends ConsumerStatefulWidget {
  final String idApartado;

  const DetalleApartadoScreen({super.key, required this.idApartado});

  @override
  ConsumerState<DetalleApartadoScreen> createState() => _DetalleApartadoScreenState();
}

class _DetalleApartadoScreenState extends ConsumerState<DetalleApartadoScreen> {
  bool _procesando = false;
  String? _error;

  Future<void> _registrarPago(double saldoPendiente, List<ApartadoCuotaModel> cuotasPendientes) async {
    final apartado = ref.read(apartadosStreamProvider).value?.where((a) => a.id == widget.idApartado).firstOrNull;
    if (apartado == null) return;
    final ok = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => RegistrarPagoApartadoDialog(
        apartado: apartado,
        saldoPendiente: saldoPendiente,
        cuotasPendientes: cuotasPendientes,
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago registrado')));
    }
  }

  Future<void> _marcarEntregado() async {
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Marcar entregado', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'Esto va a descontar el stock de los productos de este apartado y a marcarlo como entregado. ¿Confirmás que el cliente ya se llevó todo?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirmar entrega', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() {
      _procesando = true;
      _error = null;
    });
    try {
      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      await ref.read(apartadoRepositoryProvider).marcarEntregado(idApartado: widget.idApartado, usuario: usuario);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Apartado entregado')));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _cancelar() async {
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancelar apartado', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          '¿Seguro que querés cancelar este apartado? El producto queda libre para venderse a otro cliente. Esta acción no se puede deshacer.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Volver', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Cancelar apartado', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() {
      _procesando = true;
      _error = null;
    });
    try {
      await ref.read(apartadoRepositoryProvider).cancelarApartado(widget.idApartado);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _procesando = false;
      });
    }
  }

  /// Editar/eliminar un pago -acción sensible pensada para corregir errores
  /// de carga, disponible SIEMPRE (no solo con el apartado activo): antes de
  /// dejar pasar pide la clave especial (si está activada en Negocio para
  /// esta acción puntual, ver verificarAccesoEspecial) con la clave
  /// correspondiente de PermisosEspeciales.
  Future<void> _editarPago(ApartadoAbonoModel abono) async {
    final autorizado = (await verificarAccesoEspecial(context, ref, PermisosEspeciales.apartadosEditarPago)).autorizado;
    if (!autorizado || !mounted) return;
    await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => EditarAbonoApartadoDialog(abono: abono),
    );
  }

  Future<void> _eliminarPago(ApartadoAbonoModel abono) async {
    final autorizado = (await verificarAccesoEspecial(context, ref, PermisosEspeciales.apartadosEliminarPago)).autorizado;
    if (!autorizado || !mounted) return;
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Eliminar pago', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          '¿Seguro que querés eliminar el pago de ${formatearMoneda(abono.montoAbonado)}? El saldo y, si aplica, el estado de las cuotas se recalculan automáticamente. Esta acción no se puede deshacer.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      await ref.read(apartadoRepositoryProvider).eliminarAbono(abono.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago eliminado')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  /// Reparte, en Dart, el total abonado (ledger real de apartado_abonos, sin
  /// importar cuántos pagos distintos lo compusieron) contra las cuotas
  /// programadas en orden (numero_cuota asc) -mismo criterio que
  /// registrar_abono_apartado/recalcular_cadena_abonos_apartado del lado del
  /// servidor-: para cada cuota, cuánto de lo ya pagado le corresponde de
  /// verdad (hasta su monto programado). Así una cuota pagada en dos partes
  /// (ej. L.20 un día y el resto otro) muestra el avance real en vez de un
  /// simple sí/no.
  Map<String, double> _abonadoPorCuota(List<ApartadoCuotaModel> cuotas, double totalAbonado) {
    var restante = totalAbonado;
    final mapa = <String, double>{};
    for (final c in cuotas) {
      final abonado = restante <= 0 ? 0.0 : (restante < c.montoProgramado ? restante : c.montoProgramado);
      mapa[c.id] = abonado;
      restante = (restante - abonado) < 0 ? 0 : (restante - abonado);
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    final apartadosAsync = ref.watch(apartadosStreamProvider);
    final apartado = apartadosAsync.value?.where((a) => a.id == widget.idApartado).firstOrNull;
    final itemsAsync = ref.watch(apartadoItemsProvider(widget.idApartado));
    final formatoFecha = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: apartadosAsync.isLoading && apartado == null
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F1B3D)))
            : apartado == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No se encontró este apartado', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                        const SizedBox(height: 12),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(apartado.nombreCliente, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                            ),
                            _chipEstado(apartado.estado),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Consumer(builder: (context, ref, _) {
                              final saldos = ref.watch(saldosApartadosProvider);
                              final saldoPendiente = saldos[apartado.id] ?? (apartado.montoTotal - apartado.montoInicial);
                              final cuotasAsync = ref.watch(apartadoCuotasProvider(widget.idApartado));
                              final abonosAsync = ref.watch(apartadoAbonosProvider(widget.idApartado));
                              final cuotas = cuotasAsync.value ?? [];
                              final abonos = abonosAsync.value ?? [];
                              final cuotasPendientes = cuotas.where((c) => c.pendiente).toList();
                              final totalAbonado = abonos.fold<double>(0, (s, a) => s + a.montoAbonado);
                              final abonadoPorCuota = _abonadoPorCuota(cuotas, totalAbonado);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _tarjetaProgreso(apartado, saldoPendiente),
                                  const SizedBox(height: 14),
                                  _tarjetaResumen(apartado, saldoPendiente, formatoFecha),
                                  const SizedBox(height: 14),
                                  _tarjetaItems(itemsAsync),
                                  const SizedBox(height: 14),
                                  if (apartado.esCuotasFijas) ...[
                                    _tarjetaCuotas(apartado, cuotas, abonadoPorCuota, formatoFecha),
                                    const SizedBox(height: 14),
                                  ],
                                  _tarjetaHistorialPagos(abonos, formatoFecha),
                                  if (_error != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                                      child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  if (apartado.activo)
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        FilledButton.icon(
                                          onPressed: _procesando ? null : () => _registrarPago(saldoPendiente, cuotasPendientes),
                                          icon: const Icon(Icons.payments_outlined, size: 18),
                                          label: Text('Registrar Pago', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F1B3D),
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                        FilledButton.icon(
                                          onPressed: (_procesando || saldoPendiente > 0.01) ? null : _marcarEntregado,
                                          icon: const Icon(Icons.check_circle_outline, size: 18),
                                          label: Text('Marcar Entregado', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF16A34A),
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _procesando ? null : _cancelar,
                                          icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFFB91C1C)),
                                          label: Text('Cancelar Apartado', style: GoogleFonts.poppins(color: const Color(0xFFB91C1C))),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFFB91C1C)),
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _chipEstado(String estado) {
    final (color, texto) = switch (estado) {
      'completado' => (const Color(0xFF16A34A), 'Entregado'),
      'cancelado' => (Colors.grey.shade600, 'Cancelado'),
      _ => (const Color(0xFF3B82F6), 'Activo'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _tarjeta({required String titulo, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  /// Barra de progreso general (pagado / monto total) -pedido explícito del
  /// dueño, arriba de todo el detalle-.
  Widget _tarjetaProgreso(ApartadoModel apartado, double saldoPendiente) {
    final montoPagado = apartado.montoTotal - saldoPendiente;
    final progreso = apartado.montoTotal <= 0 ? 0.0 : (montoPagado / apartado.montoTotal).clamp(0, 1).toDouble();
    return _tarjeta(
      titulo: 'Progreso de pago',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${(progreso * 100).toStringAsFixed(0)}% pagado', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const Spacer(),
              Text(
                '${formatearMoneda(montoPagado)} de ${formatearMoneda(apartado.montoTotal)}',
                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 12,
              backgroundColor: const Color(0xFFE8EAF0),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaResumen(dynamic apartado, double saldoPendiente, DateFormat formatoFecha) {
    return _tarjeta(
      titulo: 'Resumen',
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _dato('Modalidad', apartado.esCuotasFijas ? 'Cuotas fijas' : 'Abonos libres'),
          _dato('Monto total', formatearMoneda(apartado.montoTotal)),
          _dato('Pago inicial', formatearMoneda(apartado.montoInicial)),
          _dato('Saldo pendiente', formatearMoneda(saldoPendiente), destacado: true),
          _dato('Creado', apartado.fechaCreacion != null ? formatoFecha.format(apartado.fechaCreacion) : '-'),
          if (apartado.fechaEntrega != null) _dato('Entregado', formatoFecha.format(apartado.fechaEntrega)),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor, {bool destacado = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(), style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.3)),
        const SizedBox(height: 3),
        Text(valor, style: GoogleFonts.poppins(fontSize: destacado ? 16 : 13.5, fontWeight: FontWeight.w700, color: destacado ? const Color(0xFF0F1B3D) : const Color(0xFF1A1A1A))),
      ],
    );
  }

  /// Encabezado compacto de una mini-tabla dentro de una tarjeta (mismo
  /// estilo que ApartadosScreen._celdaHeader/HistorialAbonosDialog, para que
  /// estas tablas del detalle se vean consistentes con el resto del sistema).
  Widget _celdaHeaderTabla(String texto, int flex, {TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF666A72), letterSpacing: 0.3),
      ),
    );
  }

  Widget _encabezadoTabla(List<Widget> columnas) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: const Color(0xFFECEEF3), borderRadius: BorderRadius.circular(8)),
      child: Row(children: columnas),
    );
  }

  /// Fila con zebra striping -alterna blanco/gris muy claro- para que una
  /// tabla larga se lea de un vistazo fila por fila, en vez de solo confiar
  /// en el Divider entre filas (pedido de estética: "más compacta y
  /// prolija").
  Widget _filaTabla(int index, Widget child) {
    return Container(
      color: index.isEven ? Colors.white : const Color(0xFFF8F9FB),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: child,
    );
  }

  Widget _tarjetaItems(AsyncValue<List<dynamic>> itemsAsync) {
    return _tarjeta(
      titulo: 'Productos',
      child: itemsAsync.when(
        data: (items) => items.isEmpty
            ? Text('Sin productos', style: GoogleFonts.poppins(color: Colors.grey.shade500))
            : Column(
                children: [
                  _encabezadoTabla([
                    _celdaHeaderTabla('PRODUCTO', 4),
                    _celdaHeaderTabla('CANT.', 2, align: TextAlign.right),
                    _celdaHeaderTabla('PRECIO', 2, align: TextAlign.right),
                    _celdaHeaderTabla('SUBTOTAL', 2, align: TextAlign.right),
                  ]),
                  const SizedBox(height: 2),
                  for (var i = 0; i < items.length; i++)
                    _filaTabla(
                      i,
                      Row(
                        children: [
                          Expanded(flex: 4, child: Text(items[i].nombreProducto, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'x${items[i].cantidad.toStringAsFixed(items[i].cantidad == items[i].cantidad.roundToDouble() ? 0 : 2)}',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                            ),
                          ),
                          Expanded(flex: 2, child: Text(formatearMoneda(items[i].precioUnitario), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
                          Expanded(flex: 2, child: Text(formatearMoneda(items[i].subtotal), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700))),
                        ],
                      ),
                    ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF0F1B3D))),
        error: (e, st) => Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red)),
      ),
    );
  }

  /// Por cada cuota: monto programado vs. lo que [abonadoPorCuota] dice que
  /// se le abonó de verdad -calculado en Dart repartiendo TODO el historial
  /// de apartado_abonos contra las cuotas en orden, ver [_abonadoPorCuota]-,
  /// no solo un sí/no. Mientras no esté completa se muestra el avance
  /// parcial (ej. "L.60.00 programado, L.20.00 abonado"), aunque el estado
  /// server-side (columna `estado`) siga en 'pendiente' hasta que un pago
  /// futuro la termine de cubrir por completo.
  Widget _tarjetaCuotas(ApartadoModel apartado, List<ApartadoCuotaModel> cuotas, Map<String, double> abonadoPorCuota, DateFormat formatoFecha) {
    return _tarjeta(
      titulo: 'Cuotas programadas',
      child: cuotas.isEmpty
          ? Text('Sin cuotas', style: GoogleFonts.poppins(color: Colors.grey.shade500))
          : Column(
              children: [
                _encabezadoTabla([
                  _celdaHeaderTabla('CUOTA', 2),
                  _celdaHeaderTabla('FECHA', 3),
                  _celdaHeaderTabla('PROGRAMADO', 2, align: TextAlign.right),
                  _celdaHeaderTabla('ABONADO', 2, align: TextAlign.right),
                  _celdaHeaderTabla('ESTADO', 2, align: TextAlign.right),
                ]),
                const SizedBox(height: 2),
                for (var i = 0; i < cuotas.length; i++)
                  _filaTabla(i, _filaCuota(cuotas[i], abonadoPorCuota[cuotas[i].id] ?? 0, formatoFecha)),
              ],
            ),
    );
  }

  Widget _filaCuota(ApartadoCuotaModel c, double abonado, DateFormat formatoFecha) {
    final completa = abonado + 0.01 >= c.montoProgramado;
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Cuota ${c.numeroCuota}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
        Expanded(
          flex: 3,
          child: Text(
            c.pagada && c.fechaPago != null ? 'Pagada ${formatoFecha.format(c.fechaPago!)}' : 'Vence ${formatoFecha.format(c.fechaProgramada)}',
            style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ),
        Expanded(flex: 2, child: Text(formatearMoneda(c.montoProgramado), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700))),
        Expanded(
          flex: 2,
          child: Text(
            formatearMoneda(abonado),
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: completa ? const Color(0xFF16A34A) : const Color(0xFF3B82F6)),
          ),
        ),
        Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: _chipCuotaEstado(c))),
      ],
    );
  }

  Widget _chipCuotaEstado(ApartadoCuotaModel c) {
    final (color, texto) = c.pagada
        ? (const Color(0xFF16A34A), 'Pagada')
        : c.vencida
            ? (const Color(0xFFB91C1C), 'Vencida')
            : (const Color(0xFF3B82F6), 'Pendiente');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
    );
  }

  /// Historial COMPLETO de pagos (apartado_abonos), sin importar la
  /// modalidad -es la única fuente de verdad de "cuánto se pagó" en las dos,
  /// ver comentario grande en supabase/schema.sql-: por eso se muestra
  /// siempre, incluso en cuotas_fijas, para que dos pagos distintos que
  /// cubrieron juntos una misma cuota (ej. L.20 un día y L.40 otro) queden a
  /// la vista como los dos movimientos reales que fueron, no como una sola
  /// fila "Pagada". Cada fila tiene su menú de editar/eliminar -acción
  /// sensible, siempre disponible, protegida por verificarAccesoEspecial-.
  Widget _tarjetaHistorialPagos(List<ApartadoAbonoModel> abonos, DateFormat formatoFecha) {
    return _tarjeta(
      titulo: 'Historial de pagos',
      child: abonos.isEmpty
          ? Text('Todavía no hay pagos registrados', style: GoogleFonts.poppins(color: Colors.grey.shade500))
          : Column(
              children: [
                _encabezadoTabla([
                  _celdaHeaderTabla('FECHA', 3),
                  _celdaHeaderTabla('MONTO PAGADO', 2, align: TextAlign.right),
                  _celdaHeaderTabla('SALDO ANTES', 2, align: TextAlign.right),
                  _celdaHeaderTabla('SALDO DESPUÉS', 2, align: TextAlign.right),
                  _celdaHeaderTabla('', 1),
                ]),
                const SizedBox(height: 2),
                for (var i = 0; i < abonos.length; i++)
                  _filaTabla(
                    i,
                    Row(
                      children: [
                        Expanded(flex: 3, child: Text(abonos[i].fecha != null ? formatoFecha.format(abonos[i].fecha!) : '-', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600))),
                        Expanded(
                          flex: 2,
                          child: Text(formatearMoneda(abonos[i].montoAbonado), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A))),
                        ),
                        Expanded(flex: 2, child: Text(formatearMoneda(abonos[i].saldoAnterior), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500))),
                        Expanded(flex: 2, child: Text(formatearMoneda(abonos[i].saldoPendiente), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
                        Expanded(flex: 1, child: Align(alignment: Alignment.centerRight, child: _menuAccionesPago(abonos[i]))),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _menuAccionesPago(ApartadoAbonoModel abono) {
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (valor) {
        if (valor == 'editar') _editarPago(abono);
        if (valor == 'eliminar') _eliminarPago(abono);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'editar',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF4B4F58)),
              const SizedBox(width: 10),
              Text('Editar pago', style: GoogleFonts.poppins(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'eliminar',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
              const SizedBox(width: 10),
              Text('Eliminar pago', style: GoogleFonts.poppins(fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
  }
}
