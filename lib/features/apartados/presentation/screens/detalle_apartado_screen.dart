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
import '../../../../core/tutorial/tutorial_modelos.dart';
import '../../../../core/tutorial/tutorial_boton.dart';
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

  // Claves del tutorial guiado -pedido explícito del dueño: la persona que
  // va a usar el sistema no es muy ágil con computadoras-. Los tres botones
  // de acción y la tarjeta de progreso solo existen si el apartado sigue
  // activo (ver build): si se abre este tutorial sobre uno ya entregado o
  // cancelado, esos pasos se saltan solos (TutorialBoton ya maneja eso).
  final _keyProgreso = GlobalKey();
  final _keyCuotas = GlobalKey();
  final _keyHistorial = GlobalKey();
  final _keyRegistrarPago = GlobalKey();
  final _keyMarcarEntregado = GlobalKey();
  final _keyCancelarApartado = GlobalKey();

  TutorialTema get _temaDetalle => TutorialTema(
        titulo: 'Cómo ver el estado de un apartado',
        descripcion: 'Progreso, cuotas/pagos, y cuándo se entrega',
        icono: Icons.receipt_long_outlined,
        bienvenida:
            'Acá se ve todo lo que pasó con este apartado: cuánto lleva '
            'pagado, qué falta, y el historial completo de pagos. Recordá: '
            'el producto NO se descuenta del inventario hasta que el '
            'apartado se marca como "Entregado" -eso recién pasa cuando el '
            'saldo llega a \$0-.',
        pasos: () => [
          TutorialPaso(
            key: _keyProgreso,
            titulo: 'Progreso de pago',
            explicacion:
                'Esta barra muestra qué porcentaje del total ya se pagó y '
                'cuánto falta.',
          ),
          TutorialPaso(
            key: _keyCuotas,
            titulo: 'Cuotas programadas',
            explicacion:
                'Si el apartado es de "Cuotas fijas", acá se ve cada cuota: '
                'cuánto le corresponde, cuánto se le abonó de verdad, y si '
                'ya está pagada o todavía pendiente.',
          ),
          TutorialPaso(
            key: _keyHistorial,
            titulo: 'Historial de pagos',
            explicacion:
                'Acá aparece cada pago que se registró, con su fecha, '
                'método, y el saldo antes/después de ese pago. Tocando los '
                'tres puntitos de una fila podés editar o eliminar ese pago '
                '-por si se cargó algo mal-.',
          ),
          TutorialPaso(
            key: _keyRegistrarPago,
            titulo: 'Registrar Pago',
            explicacion:
                'Anota acá un nuevo pago del cliente. El monto es LIBRE: el '
                'cliente puede dar lo que pueda, no tiene que coincidir '
                'exactamente con ninguna cuota.',
          ),
          TutorialPaso(
            key: _keyMarcarEntregado,
            titulo: 'Marcar Entregado',
            explicacion:
                'Se activa recién cuando el saldo llega a \$0. Al tocarlo, '
                'el producto se descuenta de verdad del inventario y el '
                'apartado queda como entregado -recién ahí el cliente se '
                'lleva el producto-.',
          ),
          TutorialPaso(
            key: _keyCancelarApartado,
            titulo: 'Cancelar Apartado',
            explicacion:
                'Si el cliente ya no va a seguir pagando, cancelalo acá: el '
                'producto queda libre para vendérselo a otro cliente. Ojo, '
                'esta acción no se puede deshacer.',
          ),
        ],
      );

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
      body: Stack(
        children: [
          _cuerpo(apartadosAsync, apartado, itemsAsync, formatoFecha),
          Positioned(
            right: 16,
            bottom: 16,
            child: TutorialBoton(temas: [_temaDetalle]),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo(
    AsyncValue<List<ApartadoModel>> apartadosAsync,
    ApartadoModel? apartado,
    AsyncValue<List<dynamic>> itemsAsync,
    DateFormat formatoFecha,
  ) {
    return SafeArea(
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
                              final saldoPendiente = saldos[apartado.id] ?? apartado.montoTotal;
                              final cuotasAsync = ref.watch(apartadoCuotasProvider(widget.idApartado));
                              final abonosAsync = ref.watch(apartadoAbonosProvider(widget.idApartado));
                              final cuotas = cuotasAsync.value ?? [];
                              final abonos = abonosAsync.value ?? [];
                              final cuotasPendientes = cuotas.where((c) => c.pendiente).toList();
                              // El pago inicial (esInicial=true) cuenta para el saldo
                              // general (ver saldosApartadosProvider) pero NO se reparte
                              // contra las cuotas -mismo criterio que
                              // recalcular_cadena_abonos_apartado en supabase/schema.sql,
                              // que ya lo excluye-: las cuotas se arman sobre el saldo a
                              // financiar (ya excluye el inicial sugerido), así que
                              // incluirlo acá también las mostraría cubiertas de más.
                              final totalAbonadoParaCuotas = abonos.where((a) => !a.esInicial).fold<double>(0, (s, a) => s + a.montoAbonado);
                              final abonadoPorCuota = _abonadoPorCuota(cuotas, totalAbonadoParaCuotas);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  apartado.cancelado
                                      ? _tarjetaCancelado(apartado, apartado.montoTotal - saldoPendiente)
                                      : _tarjetaProgreso(apartado, saldoPendiente),
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
                                          key: _keyRegistrarPago,
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
                                          key: _keyMarcarEntregado,
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
                                          key: _keyCancelarApartado,
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

  Widget _tarjeta({required String titulo, required Widget child, Key? key}) {
    return Container(
      key: key,
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
  /// dueño, arriba de todo el detalle-. Si el apartado está CANCELADO, no se
  /// muestra: una barra de progreso ahí daría a entender que todavía hay algo
  /// en curso o pendiente de terminar, cuando en realidad el apartado ya
  /// quedó cerrado -ver [_tarjetaCancelado] en su lugar-.
  Widget _tarjetaProgreso(ApartadoModel apartado, double saldoPendiente) {
    final montoPagado = apartado.montoTotal - saldoPendiente;
    final progreso = apartado.montoTotal <= 0 ? 0.0 : (montoPagado / apartado.montoTotal).clamp(0, 1).toDouble();
    return _tarjeta(
      key: _keyProgreso,
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

  /// Reemplaza a [_tarjetaProgreso] cuando el apartado está CANCELADO: el
  /// dinero ya cobrado (abonos reales, inicial incluido) NO se borra ni se
  /// reversa -sigue siendo plata real que ya entró al negocio, ver
  /// ApartadoRepository.cancelarApartado-, pero mostrar una barra de
  /// progreso o un "saldo pendiente" acá daría a entender que falta algo por
  /// cobrar o que hay que devolver algo, cuando en realidad el apartado ya
  /// quedó cerrado. Se muestra en cambio, como dato histórico, cuánto se
  /// alcanzó a cobrar antes de cancelar.
  Widget _tarjetaCancelado(ApartadoModel apartado, double montoCobrado) {
    return _tarjeta(
      titulo: 'Apartado cancelado',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.cancel_outlined, color: Colors.grey.shade600, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              montoCobrado > 0.009
                  ? 'Se cobraron ${formatearMoneda(montoCobrado)} de ${formatearMoneda(apartado.montoTotal)} antes de cancelar. Ese dinero ya entró al negocio: no se devuelve ni se reversa por cancelar el apartado.'
                  : 'No se había cobrado nada de este apartado antes de cancelarlo.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaResumen(ApartadoModel apartado, double saldoPendiente, DateFormat formatoFecha) {
    final montoCobrado = apartado.montoTotal - saldoPendiente;
    return _tarjeta(
      titulo: 'Resumen',
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _dato('Modalidad', apartado.esCuotasFijas ? 'Cuotas fijas' : 'Abonos libres'),
          _dato('Monto total', formatearMoneda(apartado.montoTotal)),
          _dato('Pago inicial sugerido', formatearMoneda(apartado.montoInicial)),
          if (apartado.cancelado)
            _dato('Cobrado antes de cancelar', formatearMoneda(montoCobrado), destacado: true)
          else
            _dato('Saldo pendiente', formatearMoneda(saldoPendiente), destacado: true),
          _dato('Creado', apartado.fechaCreacion != null ? formatoFecha.format(apartado.fechaCreacion!) : '-'),
          if (apartado.fechaEntrega != null) _dato('Entregado', formatoFecha.format(apartado.fechaEntrega!)),
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
      key: _keyCuotas,
      titulo: 'Cuotas programadas',
      child: cuotas.isEmpty
          ? Text('Sin cuotas', style: GoogleFonts.poppins(color: Colors.grey.shade500))
          : Column(
              children: [
                _encabezadoTabla([
                  _celdaHeaderTabla('CUOTA', 2),
                  _celdaHeaderTabla('FECHA', 2),
                  _celdaHeaderTabla('PROGRAMADO', 2, align: TextAlign.right),
                  _celdaHeaderTabla('ABONADO', 2, align: TextAlign.right),
                  _celdaHeaderTabla('SALDO', 2, align: TextAlign.right),
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
    // Consistente SIEMPRE con [_chipCuotaEstado] (que usa c.pagada, el
    // estado real que ya decidió el servidor): esta cuenta es solo para el
    // color del monto abonado, nunca decide "pagada" por su cuenta -eso fue
    // justo el bug reportado (columna Abonado y estado Pagada desalineados)-.
    final saldoCuota = (c.montoProgramado - abonado).clamp(0, double.infinity);
    return Row(
      children: [
        Expanded(flex: 2, child: Text('Cuota ${c.numeroCuota}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600))),
        Expanded(
          flex: 2,
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
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.pagada ? const Color(0xFF16A34A) : const Color(0xFF3B82F6)),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            formatearMoneda(saldoCuota.toDouble()),
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: saldoCuota <= 0.009 ? Colors.grey.shade400 : const Color(0xFFB91C1C)),
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
      key: _keyHistorial,
      titulo: 'Historial de pagos',
      child: abonos.isEmpty
          ? Text('Todavía no hay pagos registrados', style: GoogleFonts.poppins(color: Colors.grey.shade500))
          : Column(
              children: [
                _encabezadoTabla([
                  _celdaHeaderTabla('FECHA', 3),
                  _celdaHeaderTabla('MÉTODO', 2),
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
                        Expanded(
                          flex: 3,
                          child: Text(
                            abonos[i].fecha != null
                                ? '${formatoFecha.format(abonos[i].fecha!)}${abonos[i].esInicial ? ' · Inicial' : ''}'
                                : '-',
                            style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(abonos[i].metodoPago ?? '-', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                        ),
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
