import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_model.dart';
import '../../data/apartado_cuota_model.dart';
import '../../providers/apartados_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Registra un pago sobre un apartado activo -de CUALQUIER modalidad-: el
/// monto es SIEMPRE libre (igual que ya era en abonos_libres; antes, en
/// cuotas_fijas, obligaba a elegir una cuota y pagaba su monto exacto, sin
/// dejar pagar de más ni de menos -pedido explícito del dueño: que el monto
/// se pueda escribir siempre a mano-). Si la modalidad es cuotas_fijas, acá
/// solo se MUESTRA -de forma informativa, ya no seleccionable- cuál es la
/// próxima cuota pendiente: qué cuota(s) quedan cubiertas de verdad lo
/// decide el servidor (`registrar_abono_apartado`, ver supabase/schema.sql),
/// aplicando el monto contra las pendientes más antiguas en orden.
class RegistrarPagoApartadoDialog extends ConsumerStatefulWidget {
  final ApartadoModel apartado;
  final double saldoPendiente;
  final List<ApartadoCuotaModel> cuotasPendientes;

  const RegistrarPagoApartadoDialog({
    super.key,
    required this.apartado,
    required this.saldoPendiente,
    this.cuotasPendientes = const [],
  });

  @override
  ConsumerState<RegistrarPagoApartadoDialog> createState() => _RegistrarPagoApartadoDialogState();
}

class _RegistrarPagoApartadoDialogState extends ConsumerState<RegistrarPagoApartadoDialog> {
  final _montoController = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

  bool get _esCuotasFijas => widget.apartado.esCuotasFijas;

  double get _montoPagadoHastaAhora => widget.apartado.montoTotal - widget.saldoPendiente;

  double get _progreso => widget.apartado.montoTotal <= 0 ? 0 : (_montoPagadoHastaAhora / widget.apartado.montoTotal).clamp(0, 1);

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (fecha == null) return;
    final ahora = DateTime.now();
    setState(() => _fecha = DateTime(fecha.year, fecha.month, fecha.day, ahora.hour, ahora.minute, ahora.second));
  }

  Future<void> _guardar() async {
    final monto = _parseDouble(_montoController.text);
    if (monto <= 0) {
      setState(() => _error = 'Ingresá un monto de pago válido');
      return;
    }
    if (monto > widget.saldoPendiente + 0.01) {
      setState(() => _error = 'El pago no puede superar el saldo pendiente (${formatearMoneda(widget.saldoPendiente)})');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(apartadoRepositoryProvider);
      await repo.registrarAbono(idApartado: widget.apartado.id, montoAbonado: monto, fecha: _fecha);
      // Si este pago dejó el saldo en 0 -no puede quedar en negativo, ya se
      // validó arriba que no supere el saldo pendiente-, se ofrece de una
      // vez marcar el apartado como entregado (mismo flujo que el botón
      // "Marcar Entregado" del detalle), en vez de que el dueño tenga que ir
      // a buscarlo aparte -pedido explícito: "que pregunte apenas llega a
      // 0"-. Si el usuario dice que no, o si marcarEntregado falla por lo
      // que sea, el pago ya quedó guardado igual: solo se avisa el error,
      // sin revertir nada.
      final saldoRestante = widget.saldoPendiente - monto;
      if (mounted && saldoRestante <= 0.01) {
        await _preguntarMarcarEntregado();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  Future<void> _preguntarMarcarEntregado() async {
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Apartado pagado por completo', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'El apartado quedó completamente pagado. ¿Querés marcarlo como entregado ahora?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('No, todavía no', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sí, marcar entregado', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? '';
      await ref.read(apartadoRepositoryProvider).marcarEntregado(idApartado: widget.apartado.id, usuario: usuario);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('El pago se guardó, pero no se pudo marcar como entregado: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 500;
    final anchoDialog = esMovil ? tamano.width - 32 : 460.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: anchoDialog,
        constraints: const BoxConstraints(maxHeight: 680),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFF0F1B3D).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.payments_outlined, color: Color(0xFF0F1B3D)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Registrar Pago · ${widget.apartado.nombreCliente}',
                        style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _progresoPago(formatoFecha),
                    const SizedBox(height: 16),
                    if (_esCuotasFijas) ...[
                      _infoCuotasPendientes(formatoFecha),
                      const SizedBox(height: 16),
                    ],
                    Text('Monto a pagar', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    CampoTecladoCompacto(
                      controller: _montoController,
                      numerico: true,
                      child: TextField(
                        inputFormatters: [mayusculasInputFormatter],
                        autocorrect: false,
                        enableSuggestions: false,
                        controller: _montoController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: _decoracion('Monto pagado'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: _elegirFecha,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 10),
                            Text('Fecha del pago', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
                            const Spacer(),
                            Text(formatoFecha.format(_fecha), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                        child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F1B3D),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Registrar Pago', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barra de progreso general (pagado hasta ahora / monto total del
  /// apartado) -pedido explícito del dueño, visible en este mismo diálogo
  /// (no solo en el detalle)-.
  Widget _progresoPago(DateFormat formatoFecha) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Pagado', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
              const Spacer(),
              Text(
                '${formatearMoneda(_montoPagadoHastaAhora)} de ${formatearMoneda(widget.apartado.montoTotal)}',
                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progreso,
              minHeight: 10,
              backgroundColor: const Color(0xFFD5D9E2),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Saldo pendiente: ${formatearMoneda(widget.saldoPendiente)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  /// Solo informativo (cuotas_fijas): ya no se elige una cuota puntual acá
  /// -el monto es libre, ver comentario grande de la clase-, pero conviene
  /// seguir mostrando qué cuotas quedan pendientes y cuándo vencen.
  Widget _infoCuotasPendientes(DateFormat formatoFecha) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cuotas pendientes', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          if (widget.cuotasPendientes.isEmpty)
            Text('No hay cuotas pendientes.', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500))
          else
            Column(
              children: widget.cuotasPendientes.map((c) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Cuota ${c.numeroCuota}${c.vencida ? ' (vencida)' : ''}',
                            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: c.vencida ? const Color(0xFFB91C1C) : const Color(0xFF1A1A1A))),
                      ),
                      Text(formatoFecha.format(c.fechaProgramada), style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                      const SizedBox(width: 10),
                      Text(formatearMoneda(c.montoProgramado), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 6),
          Text(
            'El pago se aplica contra la(s) cuota(s) más antigua(s) hasta agotar el monto; se marca pagada solo la que se cubre por completo.',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
