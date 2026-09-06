import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'cierre_caja_model.dart';
import '../../../core/utils/formato_moneda.dart';
import '../../../core/utils/logo_pdf.dart';
import '../../negocio/data/negocio_model.dart';

class CajaExportService {
  static const _colorMarca = PdfColor.fromInt(0xFF0F1B3D);
  static const _colorGrisTexto = PdfColor.fromInt(0xFF4B4F58);
  static const _colorGrisClaro = PdfColor.fromInt(0xFFF2F3F7);

  // Mismo criterio que venta_export_service._anchoValidoDesdeFormato: si el
  // `format` que reporta la impresora seleccionada en Windows parece de
  // rollo térmico (entre 40 y 120mm de ancho) se usa ese ancho real en vez
  // del fijo de 80mm, para que el ticket no salga pegado a un lado en vez de
  // centrado.
  double? _anchoValidoDesdeFormato(PdfPageFormat? formato) {
    if (formato == null) return null;
    final anchoMm = formato.width / PdfPageFormat.mm;
    if (anchoMm < 40 || anchoMm > 120) return null;
    return anchoMm;
  }

  Future<Uint8List> generarTicketCierre(CierreCajaModel cierre, NegocioModel negocio, {PdfPageFormat? formatoImpresora}) async {
    final doc = pw.Document();
    final logo = decodificarLogoPdf(negocio.logoBnBase64);
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    // Mismo tamaño que el ticket de venta (ver
    // venta_export_service._construirPaginaTicket).
    const fSmall = 7.5;
    const fNormal = 8.0;
    final anchoMm = _anchoValidoDesdeFormato(formatoImpresora);
    final alturaMm = _estimarAlturaTicketCierreMm(cierre, negocio, tieneLogo: logo != null);
    final anchoPaginaMm = anchoMm ?? 80.0;

    doc.addPage(
      // pw.MultiPage (no pw.Page con altura infinita fija): con una altura
      // fija en "infinito" el paquete arma la página mucho más alta que lo
      // que realmente se imprime y el resultado sale con un bloque de
      // espacio en blanco enorme arriba del contenido (mismo motivo que
      // venta_export_service._construirPaginaTicket). Con una altura
      // estimada según lo que de verdad va a imprimirse (ver
      // _estimarAlturaTicketCierreMm) el ticket sale ajustado, sin ese hueco.
      pw.MultiPage(
        pageFormat: PdfPageFormat(anchoPaginaMm * PdfPageFormat.mm, alturaMm * PdfPageFormat.mm, marginAll: 8 * PdfPageFormat.mm),
        build: (context) {
          return [
            if (logo != null) pw.Center(child: pw.Image(logo, height: 50)),
            if (negocio.nombre.isNotEmpty)
              pw.Center(child: pw.Text(negocio.nombre.toUpperCase(), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 6),
            _separador(),
            pw.Center(child: pw.Text('CIERRE DE CAJA', style: pw.TextStyle(fontSize: fNormal + 1, fontWeight: pw.FontWeight.bold))),
            _separador(),
            pw.Text('Desde: ${formatoFecha.format(cierre.fechaInicio)}', style: const pw.TextStyle(fontSize: fNormal)),
            pw.Text('Hasta: ${formatoFecha.format(cierre.fechaFin)}', style: const pw.TextStyle(fontSize: fNormal)),
            pw.Text('Usuario: ${cierre.usuarioResponsable}', style: const pw.TextStyle(fontSize: fNormal)),
            _separador(),
            _filaTicket('Monto inicial efectivo:', cierre.montoInicial, fNormal),
            _filaTicket('Ingreso efectivo:', cierre.ingresosEfectivo, fNormal),
            _filaTicket('Ingreso tarjeta:', cierre.ingresosTarjeta, fNormal),
            _filaTicket('Ingreso transferencia:', cierre.ingresosTransferencia, fNormal),
            _filaTicket('Egreso efectivo:', cierre.egresosEfectivo, fNormal),
            _filaTicket('Egreso transferencia:', cierre.egresosTransferencia, fNormal),
            _separador(),
            _filaTicket('Total efectivo:', cierre.totalCalculadoEfectivo, fNormal, negrita: true),
            _filaTicket('Total transferencia:', cierre.totalTransferencia, fNormal, negrita: true),
            _filaTicket('Gran total:', cierre.granTotal, fNormal, negrita: true),
            _filaTicket('Total real efectivo:', cierre.totalReal, fNormal, negrita: true),
            _filaTicket('Diferencia:', cierre.diferencia, fNormal, negrita: true),
            _separador(),
            if (cierre.observaciones.isNotEmpty) ...[
              pw.Text('Observaciones:', style: pw.TextStyle(fontSize: fSmall, fontWeight: pw.FontWeight.bold)),
              pw.Text(cierre.observaciones, style: const pw.TextStyle(fontSize: fSmall)),
              _separador(),
            ],
            pw.SizedBox(height: 6),
            pw.Center(child: pw.Text('REPORTE CIERRE DE CAJA', style: pw.TextStyle(fontSize: fSmall, fontWeight: pw.FontWeight.bold))),
          ];
        },
      ),
    );
    return doc.save();
  }

  // Estima cuánto va a ocupar el ticket según lo que realmente se imprime
  // (mismo criterio que _estimarAlturaTicketMm en venta_export_service):
  // título, desde/hasta/usuario, los 11 renglones de montos, separadores
  // entre cada bloque y el pie, más colchón de seguridad. MultiPage no
  // recorta si la estimación se queda corta (a lo sumo pasa a una segunda
  // página), así que no hace falta que sea exacta al milímetro.
  double _estimarAlturaTicketCierreMm(CierreCajaModel cierre, NegocioModel negocio, {required bool tieneLogo}) {
    double alto = 140.0;
    if (tieneLogo) alto += 20.0;
    if (negocio.nombre.isNotEmpty) alto += 7.0;
    if (cierre.observaciones.isNotEmpty) {
      alto += 14.0;
      // Texto libre: a este tamaño de letra entra aprox. una línea nueva
      // cada 45 caracteres dentro del ancho del ticket (80mm).
      alto += (cierre.observaciones.length / 45).ceil() * 4.0;
    }
    return alto;
  }

  Future<Uint8List> generarPdfCierre(CierreCajaModel cierre, NegocioModel negocio) async {
    final doc = pw.Document();
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(negocio.nombre.isEmpty ? 'MI NEGOCIO' : negocio.nombre.toUpperCase(),
                      style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: pw.BoxDecoration(color: _colorMarca, borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Text('CIERRE DE CAJA', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),
              pw.Row(
                children: [
                  pw.Expanded(child: pw.Text('Desde: ${formatoFecha.format(cierre.fechaInicio)}', style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(child: pw.Text('Hasta: ${formatoFecha.format(cierre.fechaFin)}', style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(child: pw.Text('Usuario: ${cierre.usuarioResponsable}', style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
              pw.SizedBox(height: 16),
              _tablaResumen(cierre),
              pw.SizedBox(height: 16),
              if (cierre.observaciones.isNotEmpty) ...[
                pw.Text('Observaciones', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _colorGrisTexto)),
                pw.SizedBox(height: 4),
                pw.Text(cierre.observaciones, style: const pw.TextStyle(fontSize: 10)),
              ],
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _tablaResumen(CierreCajaModel cierre) {
    final filas = [
      ['Monto inicial efectivo', cierre.montoInicial],
      ['Ingreso efectivo', cierre.ingresosEfectivo],
      ['Ingreso tarjeta', cierre.ingresosTarjeta],
      ['Ingreso transferencia', cierre.ingresosTransferencia],
      ['Egreso efectivo', cierre.egresosEfectivo],
      ['Egreso transferencia', cierre.egresosTransferencia],
      ['Total efectivo (calculado)', cierre.totalCalculadoEfectivo],
      ['Total transferencia', cierre.totalTransferencia],
      ['Gran total', cierre.granTotal],
      ['Total real efectivo', cierre.totalReal],
      ['Diferencia', cierre.diferencia],
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE0E2E8), width: 0.6),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2)},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _colorGrisClaro),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Concepto', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Monto', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
          ],
        ),
        for (final fila in filas)
          pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(fila[0] as String, style: const pw.TextStyle(fontSize: 10))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(formatearMoneda(fila[1] as double), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
            ],
          ),
      ],
    );
  }

  pw.Widget _separador() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Divider(thickness: 0.7),
    );
  }

  pw.Widget _filaTicket(String etiqueta, double valor, double tamano, {bool negrita = false}) {
    final estilo = pw.TextStyle(fontSize: tamano, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(etiqueta, style: estilo),
        pw.Text(formatearMoneda(valor), style: estilo),
      ],
    );
  }
}
