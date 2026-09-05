import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'egreso_model.dart';
import '../../../core/utils/formato_moneda.dart';

class TotalesLibro {
  final double ingresos;
  final double aProveedores;
  final double gastosNegocio;
  final double gastosCasa;

  const TotalesLibro({this.ingresos = 0, this.aProveedores = 0, this.gastosNegocio = 0, this.gastosCasa = 0});

  double get utilidad => ingresos - (aProveedores + gastosNegocio + gastosCasa);

  factory TotalesLibro.desde(List<MovimientoFinanciero> movimientos) {
    double ingresos = 0, aProveedores = 0, gastosNegocio = 0, gastosCasa = 0;
    for (final m in movimientos) {
      if (m.tipoMovimiento == 'Venta (Contado)' || m.tipoMovimiento == 'Abono a Crédito') {
        ingresos += m.ingreso;
      } else if (m.tipoMovimiento == 'Compra (Contado)' || m.tipoMovimiento == 'Abono Compra Crédito') {
        aProveedores += m.egreso;
      } else if (m.esEgresoManual) {
        if (m.categoria == 'Negocio') {
          gastosNegocio += m.egreso;
        } else if (m.categoria == 'Casa') {
          gastosCasa += m.egreso;
        }
      }
    }
    return TotalesLibro(ingresos: ingresos, aProveedores: aProveedores, gastosNegocio: gastosNegocio, gastosCasa: gastosCasa);
  }
}

class EgresoExportService {
  static const _colorMarca = PdfColor.fromInt(0xFF0F1B3D);
  static const _colorGrisClaro = PdfColor.fromInt(0xFFF2F3F7);

  Uint8List generarExcelLibro(List<MovimientoFinanciero> movimientos) {
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final libro = xls.Excel.createExcel();
    final hoja = libro['Libro Financiero'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('Movimiento'),
      xls.TextCellValue('Descripción'),
      xls.TextCellValue('Ingreso'),
      xls.TextCellValue('Egreso'),
      xls.TextCellValue('Método'),
      xls.TextCellValue('Categoría'),
      xls.TextCellValue('Estado'),
      xls.TextCellValue('Usuario'),
    ]);

    for (final m in movimientos) {
      hoja.appendRow([
        xls.TextCellValue(formatoFecha.format(m.fecha)),
        xls.TextCellValue(m.tipoMovimiento),
        xls.TextCellValue(m.descripcion),
        xls.DoubleCellValue(m.ingreso),
        xls.DoubleCellValue(m.egreso),
        xls.TextCellValue(m.metodoPago),
        xls.TextCellValue(m.categoria),
        xls.TextCellValue(m.esEgresoManual ? (m.esPagado ? 'Pagado' : 'No pagado') : ''),
        xls.TextCellValue(m.usuario),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }

  Future<Uint8List> generarPdfLibro(List<MovimientoFinanciero> movimientos, DateTime inicio, DateTime fin) async {
    final doc = pw.Document();
    final formatoDia = DateFormat('dd/MM/yyyy');
    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
    final totales = TotalesLibro.desde(movimientos);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Libro Financiero', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _colorMarca)),
                pw.Text('${formatoDia.format(inicio)} — ${formatoDia.format(fin)}', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE0E2E8), width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.4),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(2.6),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(1),
              5: pw.FlexColumnWidth(1),
              6: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _colorGrisClaro),
                children: [
                  _celdaHeader('Fecha'),
                  _celdaHeader('Movimiento'),
                  _celdaHeader('Descripción'),
                  _celdaHeader('Ingreso'),
                  _celdaHeader('Egreso'),
                  _celdaHeader('Método'),
                  _celdaHeader('Usuario'),
                ],
              ),
              for (final m in movimientos)
                pw.TableRow(children: [
                  _celda(formatoFecha.format(m.fecha)),
                  _celda(m.tipoMovimiento),
                  _celda(m.descripcion),
                  _celda(m.ingreso == 0 ? '' : formatearMoneda(m.ingreso)),
                  _celda(m.egreso == 0 ? '' : formatearMoneda(m.egreso)),
                  _celda(m.metodoPago),
                  _celda(m.usuario),
                ]),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Table(
              columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1)},
              children: [
                _filaTotal('Ingresos', totales.ingresos),
                _filaTotal('A proveedores', totales.aProveedores),
                _filaTotal('Gastos operativos', totales.gastosNegocio),
                _filaTotal('Gastos casa', totales.gastosCasa),
                _filaTotal('Utilidad', totales.utilidad, negrita: true),
              ],
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _celdaHeader(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _celda(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(texto, style: const pw.TextStyle(fontSize: 8)),
      );

  pw.TableRow _filaTotal(String etiqueta, double valor, {bool negrita = false}) {
    final estilo = pw.TextStyle(fontSize: 10, fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.TableRow(children: [
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(etiqueta, style: estilo, textAlign: pw.TextAlign.right)),
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(formatearMoneda(valor), style: estilo, textAlign: pw.TextAlign.right)),
    ]);
  }
}
