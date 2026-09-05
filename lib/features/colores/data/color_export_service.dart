import 'dart:typed_data';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'color_model.dart';

class ColorExportService {
  Uint8List generarExcel(List<ColorModel> lista) {
    final formato = DateFormat('dd/MM/yyyy');
    final libro = xls.Excel.createExcel();
    final hoja = libro['Colores'];
    libro.delete('Sheet1');

    hoja.appendRow([
      xls.TextCellValue('Código'),
      xls.TextCellValue('Cliente'),
      xls.TextCellValue('Descripción'),
      xls.TextCellValue('Ubicación física'),
      xls.TextCellValue('Página'),
      xls.TextCellValue('Fecha de registro'),
      xls.TextCellValue('Observaciones'),
    ]);

    for (final c in lista) {
      hoja.appendRow([
        xls.TextCellValue(c.codigo),
        xls.TextCellValue(c.cliente),
        xls.TextCellValue(c.descripcion),
        xls.TextCellValue(c.ubicacionFisica),
        xls.TextCellValue(c.pagina),
        xls.TextCellValue(c.fechaRegistro != null ? formato.format(c.fechaRegistro!) : '-'),
        xls.TextCellValue(c.observaciones),
      ]);
    }

    final bytes = libro.save();
    return Uint8List.fromList(bytes ?? []);
  }
}
