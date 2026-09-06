import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../data/cierre_caja_model.dart';
import '../../data/caja_export_service.dart';
import '../../providers/caja_provider.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../negocio/data/negocio_model.dart';
import '../../../negocio/providers/negocio_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

class CierreCajaScreen extends ConsumerStatefulWidget {
  const CierreCajaScreen({super.key});

  @override
  ConsumerState<CierreCajaScreen> createState() => _CierreCajaScreenState();
}

class _CierreCajaScreenState extends ConsumerState<CierreCajaScreen> {
  final _servicioExport = CajaExportService();
  final _totalRealController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _montoInicialController = TextEditingController();

  DateTime _fechaInicio = DateTime.now();
  DateTime _fechaFin = DateTime.now();
  TotalesCaja _totales = const TotalesCaja();
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _totalRealController.dispose();
    _observacionesController.dispose();
    _montoInicialController.dispose();
    super.dispose();
  }

  // Editable: el usuario puede escribir el monto inicial que quiere que
  // quede registrado, no solo ver el que ya venía calculado (igual que en
  // Lopsi).
  double get _montoInicial =>
      double.tryParse(_montoInicialController.text.replaceAll(',', '').trim()) ?? 0;

  double get _totalCalculadoEfectivo =>
      _montoInicial + _totales.ingresosEfectivo - _totales.egresosEfectivo;
  double get _totalTransferencia =>
      _totales.ingresosTransferencia - _totales.egresosTransferencia;
  double get _granTotal =>
      _montoInicial +
      _totales.ingresosEfectivo +
      _totales.ingresosTarjeta +
      _totales.ingresosTransferencia -
      _totales.egresosEfectivo -
      _totales.egresosTransferencia;
  double get _totalReal =>
      double.tryParse(_totalRealController.text.replaceAll(',', '').trim()) ??
      0;
  double get _diferencia => _totalReal - _totalCalculadoEfectivo;

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final repo = ref.read(cierreCajaRepositoryProvider);
      final estado = await repo.obtenerEstadoCaja();
      _fechaInicio = estado.fechaDesde;
      _montoInicialController.text = estado.montoInicial == estado.montoInicial.roundToDouble()
          ? estado.montoInicial.toStringAsFixed(0)
          : estado.montoInicial.toStringAsFixed(2);
      _fechaFin = DateTime.now();
      await _recalcular();
    } catch (e) {
      _mostrarMensaje('No se pudo cargar el estado de caja: $e', esError: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _recalcular() async {
    try {
      final repo = ref.read(cierreCajaRepositoryProvider);
      final totales = await repo.calcularTotales(_fechaInicio, _fechaFin);
      if (mounted) setState(() => _totales = totales);
    } catch (e) {
      _mostrarMensaje('No se pudieron calcular los totales: $e', esError: true);
    }
  }

  // Solo corrige el número guardado del monto inicial del periodo YA
  // seleccionado (_fechaInicio) — no lo mueve a "ahora" ni toca el resto de
  // los datos ya cargados (ingresos/egresos del periodo, total real
  // tecleado, etc.). Antes esto colapsaba _fechaInicio a _fechaFin y
  // limpiaba el total real, lo que hacía "desaparecer" de la vista todo lo
  // acumulado desde el inicio real del periodo con solo corregir este monto
  // (mismo bug ya corregido en Lopsi).
  Future<void> _guardarMontoInicial() async {
    if (_montoInicial <= 0) {
      _mostrarMensaje('Monto inicial inválido', esError: true);
      return;
    }
    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? 'Sistema';
    await ref
        .read(cierreCajaRepositoryProvider)
        .guardarMontoInicial(_fechaInicio, _montoInicial, usuario);
    _mostrarMensaje('Monto inicial guardado correctamente');
  }

  Future<void> _cerrarCaja() async {
    if (_totalRealController.text.trim().isEmpty) {
      _mostrarMensaje('Ingrese el total real de efectivo', esError: true);
      return;
    }
    final usuario = ref.read(authProvider).usuario?.nombreCompleto ?? 'Sistema';
    final cierre = CierreCajaModel(
      fechaInicio: _fechaInicio,
      fechaFin: _fechaFin,
      montoInicial: _montoInicial,
      ingresosEfectivo: _totales.ingresosEfectivo,
      ingresosTarjeta: _totales.ingresosTarjeta,
      ingresosTransferencia: _totales.ingresosTransferencia,
      egresosEfectivo: _totales.egresosEfectivo,
      egresosTransferencia: _totales.egresosTransferencia,
      totalCalculadoEfectivo: _totalCalculadoEfectivo,
      totalTransferencia: _totalTransferencia,
      granTotal: _granTotal,
      totalReal: _totalReal,
      diferencia: _diferencia,
      usuarioResponsable: usuario,
      observaciones: _observacionesController.text.trim(),
    );

    setState(() => _guardando = true);
    try {
      await ref.read(cierreCajaRepositoryProvider).registrarCierre(cierre);
      if (!mounted) return;
      _mostrarMensaje('Cierre de caja registrado correctamente');
      await _preguntarReporte(cierre);
      if (!mounted) return;
      _totalRealController.clear();
      _observacionesController.clear();
      // Recarga fresco desde Supabase (en vez de reconstruir el estado a
      // mano) para que _fechaInicio quede exactamente en lo que
      // registrarCierre acaba de guardar como próximo periodo (00:00 del
      // mismo día calendario del cierre, ver registrar_cierre_caja en
      // supabase/schema.sql).
      await _cargarTodo();
    } catch (e) {
      _mostrarMensaje('Error al registrar el cierre: $e', esError: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _preguntarReporte(CierreCajaModel cierre) async {
    final negocio = await ref
        .read(negocioRepositoryProvider)
        .obtenerNegocioActual();
    if (!mounted) return;

    // Igual que Registrar Venta (ver registrar_venta_screen._manejarImpresion):
    // con "imprimir sin preguntar" activo en Negocio, el ticket de cierre se
    // manda directo a la térmica configurada sin mostrar ninguno de los tres
    // diálogos de abajo (¿generar reporte? · ¿en qué formato? · vista
    // previa) — antes se mostraban los tres sin importar esta configuración,
    // lo que se sentía como "pregunta el diálogo de imprimir dos veces".
    if (negocio.modoImpresion == ModoImpresion.directo) {
      await _imprimirCierreDirecto(cierre, negocio);
      return;
    }

    final quiereReporte = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impresión y PDF'),
        content: const Text('¿Desea generar el reporte de cierre de caja?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (quiereReporte != true || !mounted) return;

    final tipo = await showDialog<String>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cómo desea el reporte?'),
        content: const Text('Seleccione el formato de salida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'termico'),
            child: const Text('Térmico'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'pdf'),
            child: const Text('PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'ambos'),
            child: const Text('Ambos'),
          ),
        ],
      ),
    );
    if (tipo == null || !mounted) return;

    if (tipo == 'termico' || tipo == 'ambos') {
      final impresora = negocio.impresoraTermicaUrl.isEmpty
          ? null
          : Printer(
              url: negocio.impresoraTermicaUrl,
              name: negocio.impresoraTermicaNombre,
            );
      await showDialog(
        useRootNavigator: false,
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Ticket · Cierre de Caja',
          nombreArchivo: 'cierre_caja_ticket.pdf',
          generarPdf: () =>
              _servicioExport.generarTicketCierre(cierre, negocio),
          generarPdfConFormato: (formato) => _servicioExport
              .generarTicketCierre(cierre, negocio, formatoImpresora: formato),
          impresora: impresora,
        ),
      );
      if (!mounted) return;
    }
    if (tipo == 'pdf' || tipo == 'ambos') {
      await showDialog(
        useRootNavigator: false,
        context: context,
        builder: (context) => PdfPreviewDialog(
          titulo: 'Vista previa · Cierre de Caja',
          nombreArchivo: 'cierre_caja.pdf',
          generarPdf: () => _servicioExport.generarPdfCierre(cierre, negocio),
        ),
      );
    }
  }

  // Imprime el ticket térmico de cierre directo, sin ningún diálogo de por
  // medio: la contraparte de _preguntarReporte para cuando Negocio tiene
  // "imprimir sin preguntar" activo. Mismas ramas por plataforma que
  // registrar_venta_screen._manejarImpresion, pero sin la infraestructura de
  // "venta pendiente de impresión" (no aplica acá, esto no es una venta) ni
  // impresión remota de respaldo: en Android/iOS, o en escritorio sin
  // impresora térmica configurada, no hay ningún destino al que mandar el
  // ticket sin preguntar, así que ahí se cae a la vista previa de siempre en
  // vez de fallar en silencio.
  Future<void> _imprimirCierreDirecto(
    CierreCajaModel cierre,
    NegocioModel negocio,
  ) async {
    final esMovilNativo = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!esMovilNativo && negocio.impresoraTermicaUrl.isNotEmpty) {
      if (kIsWeb) {
        try {
          await Printing.layoutPdf(
            onLayout: (formato) => _servicioExport.generarTicketCierre(
              cierre,
              negocio,
              formatoImpresora: formato,
            ),
            name: 'cierre_caja_ticket.pdf',
          );
        } catch (_) {
          _mostrarMensaje('No se pudo imprimir el ticket de cierre', esError: true);
        }
        return;
      }
      try {
        final impresora = Printer(
          url: negocio.impresoraTermicaUrl,
          name: negocio.impresoraTermicaNombre,
        );
        await Printing.directPrintPdf(
          printer: impresora,
          onLayout: (formato) => _servicioExport.generarTicketCierre(
            cierre,
            negocio,
            formatoImpresora: formato,
          ),
        );
      } catch (_) {
        _mostrarMensaje('No se pudo imprimir en la impresora configurada', esError: true);
      }
      return;
    }
    // Sin impresora térmica configurada (o en Android/iOS nativo, donde no
    // hay un destino directo al que mandar el ticket): se muestra la vista
    // previa de siempre en vez de dejar el cierre sin ningún ticket.
    if (!mounted) return;
    final impresora = negocio.impresoraTermicaUrl.isEmpty
        ? null
        : Printer(
            url: negocio.impresoraTermicaUrl,
            name: negocio.impresoraTermicaNombre,
          );
    await showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Ticket · Cierre de Caja',
        nombreArchivo: 'cierre_caja_ticket.pdf',
        generarPdf: () => _servicioExport.generarTicketCierre(cierre, negocio),
        generarPdfConFormato: (formato) => _servicioExport
            .generarTicketCierre(cierre, negocio, formatoImpresora: formato),
        impresora: impresora,
      ),
    );
  }

  // Antes fecha inicio/fin del periodo eran fijas (solo texto, no se podían
  // tocar): inicio salía siempre del último cierre guardado y fin siempre
  // era "ahora". Ahora se pueden editar las dos a mano (por ejemplo para
  // recalcular un periodo distinto al que quedó guardado), recalculando los
  // totales del rango elegido al confirmar (igual que en Lopsi).
  Future<void> _seleccionarFechaHora(bool esInicio) async {
    final actual = esInicio ? _fechaInicio : _fechaFin;
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actual),
    );
    if (hora == null || !mounted) return;
    final nuevaFecha = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
    setState(() {
      if (esInicio) {
        _fechaInicio = nuevaFecha;
      } else {
        _fechaFin = nuevaFecha;
      }
    });
    await _recalcular();
  }

  Widget _selectorFechaHora(String etiqueta, DateTime valor, VoidCallback onTap) {
    final formato = DateFormat('dd/MM/yyyy HH:mm');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_outlined, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 5),
            Text(
              '$etiqueta ${formato.format(valor)}',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 3),
            Icon(Icons.edit_outlined, size: 13, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? const Color(0xFF0F1B3D) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F3F7),
      child: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0F1B3D)),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final esMovil = constraints.maxWidth < 760;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(esMovil ? 14 : 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cierre de Caja',
                        style: GoogleFonts.poppins(
                          fontSize: esMovil ? 19 : 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _selectorFechaHora('Desde', _fechaInicio, () => _seleccionarFechaHora(true)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey.shade400),
                          ),
                          _selectorFechaHora('Hasta', _fechaFin, () => _seleccionarFechaHora(false)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _tarjetaResumen(esMovil, constraints.maxWidth),
                          _tarjetaCierre(esMovil, constraints.maxWidth),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _tarjetaResumen(bool esMovil, double anchoTotal) {
    return Container(
      width: esMovil ? anchoTotal - 28 : 420,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen del periodo',
            style: GoogleFonts.poppins(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Monto inicial efectivo',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          CampoTecladoCompacto(
            controller: _montoInicialController,
            numerico: true,
            titulo: '0.00',
            onSubmitted: (_) => setState(() {}),
            child: TextField(
              inputFormatters: [mayusculasInputFormatter],
              autocorrect: false,
              enableSuggestions: false,
              controller: _montoInicialController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: 'L. ',
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Escribí el monto con el que arrancó la caja en efectivo. Se guarda con "Guardar monto inicial", sin necesidad de cerrar caja.',
            style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 10),
          _filaMonto('Ingreso efectivo', _totales.ingresosEfectivo),
          _filaMonto('Ingreso tarjeta', _totales.ingresosTarjeta),
          _filaMonto('Ingreso transferencia', _totales.ingresosTransferencia),
          _filaMonto('Egreso efectivo', _totales.egresosEfectivo),
          _filaMonto('Egreso transferencia', _totales.egresosTransferencia),
          const Divider(height: 24),
          _filaMonto(
            'Total efectivo (calculado)',
            _totalCalculadoEfectivo,
            negrita: true,
          ),
          _filaMonto('Total transferencia', _totalTransferencia, negrita: true),
          _filaMonto(
            'Gran total',
            _granTotal,
            negrita: true,
            color: const Color(0xFF0F1B3D),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _guardando ? null : _guardarMontoInicial,
              icon: const Icon(Icons.savings_outlined, size: 18),
              label: Text(
                'Guardar monto inicial (sin cerrar)',
                style: GoogleFonts.poppins(fontSize: 12.5),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A1A1A),
                side: const BorderSide(color: Color(0xFFB6BCC7)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCierre(bool esMovil, double anchoTotal) {
    return Container(
      width: esMovil ? anchoTotal - 28 : 420,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7CBD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cerrar caja',
            style: GoogleFonts.poppins(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Total real efectivo',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          CampoTecladoCompacto(
            controller: _totalRealController,
            numerico: true,
            titulo: '0.00',
            child: TextField(
              inputFormatters: [mayusculasInputFormatter],
              autocorrect: false,
              enableSuggestions: false,
              controller: _totalRealController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: 'L. ',
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EAF0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Diferencia',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  formatearMoneda(_diferencia),
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _diferencia == 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF0F1B3D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Observaciones',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          CampoTecladoCompacto(
            controller: _observacionesController,
            numerico: false,
            titulo: 'Observaciones del cierre (opcional)',
            child: TextField(
              inputFormatters: [mayusculasInputFormatter],
              autocorrect: false,
              enableSuggestions: false,
              controller: _observacionesController,
              maxLines: 3,
              style: GoogleFonts.poppins(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Observaciones del cierre (opcional)',
                filled: true,
                fillColor: const Color(0xFFE8EAF0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _cerrarCaja,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_outline, size: 18),
              label: Text(
                _guardando ? 'Cerrando...' : 'Cerrar Caja',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F1B3D),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaMonto(
    String etiqueta,
    double valor, {
    bool negrita = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            etiqueta,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            formatearMoneda(valor),
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: negrita ? FontWeight.w700 : FontWeight.w500,
              color: color ?? const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}
