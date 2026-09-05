import 'package:excel/excel.dart' as xls;
import '../../../core/utils/xlsx_reparar.dart';

class FilaImportacionCompraCredito {
  final int numeroFila;
  final String numeroDocumento;
  final String noFactura;
  final String nombreProveedor;
  final double montoTotal;
  final double saldoPendiente;
  final DateTime? fechaRegistro;
  final DateTime fechaVencimiento;
  final String? error;

  FilaImportacionCompraCredito({
    required this.numeroFila,
    required this.numeroDocumento,
    required this.noFactura,
    required this.nombreProveedor,
    required this.montoTotal,
    required this.saldoPendiente,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    this.error,
  });

  bool get valido => error == null;
}

/// Lee el "Reporte de Compras a Crédito" que exporta el sistema anterior.
class CompraCreditoImportService {
  static const _sinonimos = <String, List<String>>{
    'numeroDocumento': ['numerodedocumento', 'numerodocumento'],
    'noFactura': ['numerodefactura', 'numerofactura', 'nofactura'],
    'proveedor': ['proveedor'],
    'montoTotal': ['montototal'],
    'saldoPendiente': ['saldopendiente'],
    'fechaRegistro': ['fecharegistro', 'fechaderegistro'],
    'fechaVencimiento': ['fechavencimiento', 'fechadevencimiento'],
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

  /// Las fechas vienen como d/M/yyyy o, cuando Excel guardó la celda como
  /// fecha real en vez de texto, como el número de serie de Excel (días
  /// desde 1899-12-30).
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

  double? _parseMonto(String texto) {
    final limpio = texto.trim().replaceAll(',', '').replaceAll('L', '').replaceAll('Lps.', '').trim();
    if (limpio.isEmpty) return null;
    return double.tryParse(limpio);
  }

  /// Lee un .xlsx y devuelve las filas encontradas (válidas o con error).
  /// Lanza [FormatException] si el archivo no se pudo leer en absoluto.
  List<FilaImportacionCompraCredito> leer(List<int> bytes) {
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

    if (!indicePorCampo.containsKey('proveedor')) {
      throw const FormatException('No encontré una columna "Proveedor" en el archivo. Revisá que la primera fila tenga los encabezados.');
    }

    String celda(List<xls.Data?> fila, String campo) {
      final indice = indicePorCampo[campo];
      if (indice == null || indice >= fila.length) return '';
      return fila[indice]?.value?.toString() ?? '';
    }

    final filas = <FilaImportacionCompraCredito>[];
    for (var i = 1; i < hoja.rows.length; i++) {
      final fila = hoja.rows[i];
      if (fila.every((c) => (c?.value?.toString() ?? '').trim().isEmpty)) continue;

      final proveedor = celda(fila, 'proveedor').trim();
      final montoTexto = celda(fila, 'montoTotal');
      final saldoTexto = celda(fila, 'saldoPendiente');
      final montoTotal = _parseMonto(montoTexto);
      final saldoPendiente = _parseMonto(saldoTexto);
      final fechaRegistro = _parseFecha(celda(fila, 'fechaRegistro'));
      final fechaVencimiento = _parseFecha(celda(fila, 'fechaVencimiento'));

      String? error;
      if (proveedor.isEmpty) {
        error = 'El proveedor está vacío';
      } else if (montoTotal == null || montoTotal <= 0) {
        error = 'Monto total inválido: "$montoTexto"';
      }

      filas.add(FilaImportacionCompraCredito(
        numeroFila: i + 1,
        numeroDocumento: celda(fila, 'numeroDocumento').trim(),
        noFactura: celda(fila, 'noFactura').trim(),
        nombreProveedor: proveedor,
        montoTotal: montoTotal ?? 0,
        // Sin saldo en el archivo o inválido: se asume liquidado (no deuda), nunca se
        // inventa un saldo pendiente igual al total porque podría ya estar pagado.
        saldoPendiente: saldoPendiente ?? 0,
        fechaRegistro: fechaRegistro,
        // Igual que en el alta manual: sin fecha de vencimiento en el archivo se
        // usa fecha de registro (o de importación) + 30 días.
        fechaVencimiento: fechaVencimiento ?? (fechaRegistro ?? DateTime.now()).add(const Duration(days: 30)),
        error: error,
      ));
    }
    return filas;
  }
}
