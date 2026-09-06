import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_abono_model.dart';
import '../../providers/apartados_provider.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import 'configuracion_apartado.dart' show metodosPagoApartado;

/// Corrige un pago ya registrado de un apartado (monto y/o fecha) -acción
/// sensible pensada para arreglar errores de carga, disponible SIEMPRE
/// (activo, completado o cancelado), ver DetalleApartadoScreen: quien abre
/// este diálogo ya pasó por verificarAccesoEspecial-. El recálculo de
/// saldo_anterior/saldo_pendiente de los abonos posteriores -y, si aplica,
/// de qué cuotas quedan cubiertas- lo hace por completo el servidor
/// (`editar_abono_apartado`, ver supabase/schema.sql), acá solo se manda el
/// nuevo monto/fecha.
class EditarAbonoApartadoDialog extends ConsumerStatefulWidget {
  final ApartadoAbonoModel abono;

  const EditarAbonoApartadoDialog({super.key, required this.abono});

  @override
  ConsumerState<EditarAbonoApartadoDialog> createState() => _EditarAbonoApartadoDialogState();
}

class _EditarAbonoApartadoDialogState extends ConsumerState<EditarAbonoApartadoDialog> {
  late final TextEditingController _montoController;
  late DateTime _fecha;
  late String? _metodoPago;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _montoController = TextEditingController(text: widget.abono.montoAbonado.toStringAsFixed(2));
    _fecha = widget.abono.fecha ?? DateTime.now();
    _metodoPago = widget.abono.metodoPago;
  }

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (fecha == null) return;
    setState(() => _fecha = DateTime(fecha.year, fecha.month, fecha.day, _fecha.hour, _fecha.minute, _fecha.second));
  }

  Future<void> _guardar() async {
    final monto = _parseDouble(_montoController.text);
    if (monto <= 0) {
      setState(() => _error = 'Ingresá un monto de pago válido');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apartadoRepositoryProvider).editarAbono(idAbono: widget.abono.id, montoAbonado: monto, fecha: _fecha, metodoPago: _metodoPago);
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
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 500;
    final anchoDialog = esMovil ? tamano.width - 32 : 440.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: anchoDialog,
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
                    decoration: BoxDecoration(color: const Color(0xFF0F1B3D).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.edit_outlined, color: Color(0xFF0F1B3D)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Editar Pago', style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Text('Método de pago', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final metodo in metodosPagoApartado)
                        ChoiceChip(
                          label: Text(metodo, style: GoogleFonts.poppins(fontSize: 12.5)),
                          selected: _metodoPago == metodo,
                          onSelected: (v) => setState(() => _metodoPago = metodo),
                        ),
                    ],
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
                          Text(DateFormat('dd/MM/yyyy').format(_fecha), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'El saldo de este apartado y, si aplica, el estado de las cuotas se recalculan automáticamente a partir de este pago.',
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
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
                        : Text('Guardar Cambios', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
