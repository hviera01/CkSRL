import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_model.dart';
import '../../data/apartado_cuota_model.dart';
import '../../providers/apartados_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../widgets/registrar_pago_apartado_dialog.dart';

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
                              final cuotasPendientes = (cuotasAsync.value ?? []).where((c) => c.pendiente).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _tarjetaProgreso(apartado, saldoPendiente),
                                  const SizedBox(height: 14),
                                  _tarjetaResumen(apartado, saldoPendiente, formatoFecha),
                                  const SizedBox(height: 14),
                                  _tarjetaItems(itemsAsync),
                                  const SizedBox(height: 14),
                                  if (apartado.esCuotasFijas)
                                    _tarjetaCuotas(apartado, cuotasAsync.value ?? [], formatoFecha)
                                  else
                                    _tarjetaAbonos(abonosAsync.value ?? [], formatoFecha),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
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

  Widget _tarjetaItems(AsyncValue<List<dynamic>> itemsAsync) {
    return _tarjeta(
      titulo: 'Productos',
      child: itemsAsync.when(
        data: (items) => items.isEmpty
            ? Text('Sin productos', style: GoogleFonts.poppins(color: Colors.grey.shade500))
            : Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(items[i].nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600))),
                          Expanded(
                            child: Text(
                              'x${items[i].cantidad.toStringAsFixed(items[i].cantidad == items[i].cantidad.roundToDouble() ? 0 : 2)}',
                              style: GoogleFonts.poppins(fontSize: 13),
                            ),
                          ),
                          Expanded(child: Text(formatearMoneda(items[i].precioUnitario), style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600))),
                          Expanded(child: Text(formatearMoneda(items[i].subtotal), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF0F1B3D))),
        error: (e, st) => Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red)),
      ),
    );
  }

  /// [apartado] solo se usa para el "saldo pendiente PROGRAMADO" de cada
  /// fila -saldo a financiar (montoTotal - montoInicial) menos la suma de
  /// las cuotas hasta esa fila inclusive, tal como quedaron programadas al
  /// crear el apartado-: no es necesariamente el saldo real en cada
  /// instante (un pago libre puede cubrir cuotas fuera de orden estricto o
  /// dejar una a medio cubrir, ver registrar_abono_apartado), pero sí sirve
  /// para ver de un vistazo cuánto debería quedar si el pago va al día.
  Widget _tarjetaCuotas(ApartadoModel apartado, List<ApartadoCuotaModel> cuotas, DateFormat formatoFecha) {
    final saldoAFinanciar = apartado.montoTotal - apartado.montoInicial;
    var acumulado = 0.0;
    return _tarjeta(
      titulo: 'Cuotas programadas',
      child: cuotas.isEmpty
          ? Text('Sin cuotas', style: GoogleFonts.poppins(color: Colors.grey.shade500))
          : Column(
              children: [
                for (var i = 0; i < cuotas.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  Builder(builder: (context) {
                    acumulado += cuotas[i].montoProgramado;
                    final saldoProgramado = (saldoAFinanciar - acumulado).clamp(0, saldoAFinanciar).toDouble();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text('Cuota ${cuotas[i].numeroCuota}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              cuotas[i].pagada && cuotas[i].fechaPago != null
                                  ? 'Pagada ${formatoFecha.format(cuotas[i].fechaPago!)}'
                                  : 'Vence ${formatoFecha.format(cuotas[i].fechaProgramada)}',
                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                          Expanded(child: Text(formatearMoneda(cuotas[i].montoProgramado), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
                          Expanded(child: Text(formatearMoneda(saldoProgramado), style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade500))),
                          _chipCuotaEstado(cuotas[i]),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
    );
  }

  Widget _chipCuotaEstado(ApartadoCuotaModel c) {
    final (color, texto) = c.pagada
        ? (const Color(0xFF16A34A), 'Pagada')
        : c.vencida
            ? (const Color(0xFFB91C1C), 'Vencida')
            : (const Color(0xFF3B82F6), 'Pendiente');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _tarjetaAbonos(List<dynamic> abonos, DateFormat formatoFecha) {
    return _tarjeta(
      titulo: 'Historial de abonos',
      child: abonos.isEmpty
          ? Text('Todavía no hay abonos registrados', style: GoogleFonts.poppins(color: Colors.grey.shade500))
          : Column(
              children: [
                for (var i = 0; i < abonos.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            abonos[i].fecha != null ? formatoFecha.format(abonos[i].fecha) : '-',
                            style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ),
                        Expanded(child: Text(formatearMoneda(abonos[i].montoAbonado), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700))),
                        Expanded(child: Text('Saldo: ${formatearMoneda(abonos[i].saldoPendiente)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
