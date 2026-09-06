import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_model.dart';
import '../../data/apartado_cuota_model.dart';
import '../../providers/apartados_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Registra un pago sobre un apartado activo: según [apartado.modalidad],
/// deja elegir UNA cuota pendiente para marcarla pagada (cuotas_fijas) o
/// tipear un monto de abono libre (abonos_libres) -mismo espíritu que
/// RegistrarAbonoDialog de Ventas a Crédito, pero con las dos modalidades
/// resueltas en un solo diálogo porque comparten cabecera/estilo-.
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
  ApartadoCuotaModel? _cuotaElegida;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.cuotasPendientes.isNotEmpty) {
      _cuotaElegida = widget.cuotasPendientes.first;
    }
  }

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

  bool get _esCuotasFijas => widget.apartado.esCuotasFijas;

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(apartadoRepositoryProvider);
      if (_esCuotasFijas) {
        final cuota = _cuotaElegida;
        if (cuota == null) {
          setState(() {
            _error = 'Elegí qué cuota se va a pagar';
            _guardando = false;
          });
          return;
        }
        await repo.registrarCuotaPagada(idApartado: widget.apartado.id, numeroCuota: cuota.numeroCuota);
      } else {
        final monto = _parseDouble(_montoController.text);
        if (monto <= 0) {
          setState(() {
            _error = 'Ingresá un monto de abono válido';
            _guardando = false;
          });
          return;
        }
        if (monto > widget.saldoPendiente + 0.01) {
          setState(() {
            _error = 'El abono no puede superar el saldo pendiente (${formatearMoneda(widget.saldoPendiente)})';
            _guardando = false;
          });
          return;
        }
        await repo.registrarAbono(idApartado: widget.apartado.id, montoAbonado: monto);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
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
        constraints: const BoxConstraints(maxHeight: 620),
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
                    _filaSoloLectura('Saldo pendiente', formatearMoneda(widget.saldoPendiente)),
                    const SizedBox(height: 16),
                    if (_esCuotasFijas) ...[
                      Text('Elegí la cuota que se está pagando', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      if (widget.cuotasPendientes.isEmpty)
                        Text('No hay cuotas pendientes.', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500))
                      else
                        Column(
                          children: widget.cuotasPendientes.map((c) {
                            final elegida = _cuotaElegida?.id == c.id;
                            return InkWell(
                              onTap: () => setState(() => _cuotaElegida = c),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: elegida ? const Color(0xFF0F1B3D).withOpacity(0.08) : const Color(0xFFE8EAF0),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: elegida ? const Color(0xFF0F1B3D) : Colors.transparent, width: 1.4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(elegida ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                        size: 18, color: elegida ? const Color(0xFF0F1B3D) : Colors.grey.shade500),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text('Cuota ${c.numeroCuota}${c.vencida ? ' (vencida)' : ''}',
                                          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: c.vencida ? const Color(0xFFB91C1C) : const Color(0xFF1A1A1A))),
                                    ),
                                    Text(formatoFecha.format(c.fechaProgramada), style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
                                    const SizedBox(width: 10),
                                    Text(formatearMoneda(c.montoProgramado), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ] else ...[
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
                          decoration: _decoracion('Monto abonado'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
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

  Widget _filaSoloLectura(String etiqueta, String valor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(etiqueta, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          const Spacer(),
          Text(valor, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
        ],
      ),
    );
  }
}
