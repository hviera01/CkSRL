import 'package:excel/excel.dart' as xls;
import '../../../core/utils/xlsx_reparar.dart';

class FilaImportacionColor {
  final int numeroFila;
  final String codigo;
  final String cliente;
  final String descripcion;
  final String ubicacionFisica;
  final String pagina;
  final DateTime? fechaRegistro;
  final String observaciones;

  FilaImportacionColor({
    required this.numeroFila,
    required this.codigo,
    required this.cliente,
    required this.descripcion,
    required this.ubicacionFisica,
    required this.pagina,
    required this.fechaRegistro,
    required this.observaciones,
  });
}

/// Lee los excel del "Registro de Colores", que vienen de dos fuentes con
/// encabezados distintos (el libro histórico "Super Color" y el informe que
/// exporta el sistema anterior), por lo que empareja columnas por nombre en
/// vez de por posición. Muchas filas del libro histórico no tienen cliente o
/// código (se anotaba solo el color y la ubicación en el libro físico), así
/// que no se exige ningún campo: se importa toda fila que no esté vacía.
class ColorImportService {
  static const _sinonimos = <String, List<String>>{
    'codigo': ['codigo'],
    'cliente': ['cliente'],
    'descripcion': ['descripcion'],
    'ubicacionFisica': ['ubicacionfisica'],
    'pagina': ['pagina'],
    'fechaRegistro': ['fecharegistro', 'fechaderegistro'],
    'observaciones': ['observaciones'],
  };

  String _normalizar(String texto) {
    var t = texto.trim().toLowerCase();
    const conAcento = 'áéíóúñ';
    const sinAcento = 'aeioun';
    for (var i = 0; i < conAcento.length; i++) {
      t = t.replaceAll(conAcento[i], sinAcento[i]);
    }
    return t.replaceAll(RegExp(r'\s+'), '');
  }

  /// Las fechas vienen como d/M/yyyy (a veces sin ceros a la izquierda) o,
  /// cuando Excel guardó la celda como fecha real en vez de texto, como el
  /// número de serie de Excel (días desde 1899-12-30). No es un dato crítico
  /// del registro, así que si no se puede leer simplemente se deja en null en
  /// vez de invalidar toda la fila.
  DateTime? _parseFecha(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty || limpio == '-') return null;
    if (RegExp(r'^\d+$').hasMatch(limpio)) {
      final serial = int.parse(limpio);
      return DateTime(1899, 12, 30).add(Duration(days: serial));
    }
    final partes = limpio.split(RegExp(r'[/\-]'));
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    var anio = int.tryParse(partes[2]);
    if (dia == null || mes == null || anio == null) return null;
    if (anio < 100) anio += 2000;
    try {
      final fecha = DateTime(anio, mes, dia);
      if (fecha.month != mes || fecha.day != dia) return null;
      return fecha;
    } catch (_) {
      return null;
    }
  }

  /// Lee un .xlsx y devuelve las filas encontradas (no vacías).
  /// Lanza [FormatException] si el archivo no se pudo leer en absoluto.
  List<FilaImportacionColor> leer(List<int> bytes) {
    xls.Excel excel;
    try {
      excel = xls.Excel.decodeBytes(bytes);
    } catch (_) {
      try {
        excel = xls.Excel.decodeBytes(repararRutasXlsx(bytes));
      } catch (_) {
        throw const FormatException(
          'No se pudo leer el archivo. Abrilo en Google Sheets (gratis, sin instalar nada), '
          'descargalo de nuevo como .xlsx (Archivo → Descargar → Microsoft Excel) y volvé a subirlo.',
        );
      }
    }

    if (excel.tables.isEmpty) {
      throw const FormatException('El archivo no tiene ninguna hoja con datos.');
    }
    final hoja = excel.tables[excel.tables.keys.first]!;
    if (hoja.maxRows < 2) {
      throw const FormatException('El archivo no tiene filas de datos (solo encabezado o está vacío).');
    }

    final encabezado = hoja.rows.first;
    final indicePorCampo = <String, int>{};
    for (var col = 0; col < encabezado.length; col++) {
      final valor = encabezado[col]?.value?.toString() ?? '';
      final normalizado = _normalizar(valor);
      for (final entrada in _sinonimos.entries) {
        if (entrada.value.contains(normalizado) && !indicePorCampo.containsKey(entrada.key)) {
          indicePorCampo[entrada.key] = col;
        }
      }
    }

    if (!indicePorCampo.containsKey('cliente') && !indicePorCampo.containsKey('descripcion')) {
      throw const FormatException('No encontré columnas de "Cliente" ni "Descripción" en el archivo. Revisá que la primera fila tenga los encabezados.');
    }

    String celda(List<xls.Data?> fila, String campo) {
      final indice = indicePorCampo[campo];
      if (indice == null || indice >= fila.length) return '';
      return fila[indice]?.value?.toString() ?? '';
    }

    final filas = <FilaImportacionColor>[];
    for (var i = 1; i < hoja.rows.length; i++) {
      final fila = hoja.rows[i];
      if (fila.every((c) => (c?.value?.toString() ?? '').trim().isEmpty)) continue;

      filas.add(FilaImportacionColor(
        numeroFila: i + 1,
        codigo: celda(fila, 'codigo').trim(),
        cliente: celda(fila, 'cliente').trim(),
        descripcion: celda(fila, 'descripcion').trim(),
        ubicacionFisica: celda(fila, 'ubicacionFisica').trim(),
        pagina: celda(fila, 'pagina').trim(),
        fechaRegistro: _parseFecha(celda(fila, 'fechaRegistro')),
        observaciones: celda(fila, 'observaciones').trim(),
      ));
    }
    return filas;
  }
}
