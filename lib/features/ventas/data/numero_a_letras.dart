const _unidades = [
  '', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez',
  'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte',
];
const _decenas = ['', '', 'veinte', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
const _centenas = ['', 'cien', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos', 'ochocientos', 'novecientos'];

const _conY = ['treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];

String _aplicarY(String letras, int resto) {
  if (resto <= 0) return letras;
  for (final palabra in _conY) {
    if (letras.contains(palabra)) {
      return letras.replaceFirst(palabra, '$palabra y');
    }
  }
  return letras;
}

String _convertirMenosDeMil(int numero) {
  var letras = '';
  var n = numero;

  if (n >= 100) {
    final centena = n ~/ 100;
    if (centena == 1 && n == 100) {
      letras += 'cien ';
    } else {
      letras += '${_centenas[centena]} ';
    }
    n %= 100;
  }

  if (n >= 20) {
    final decena = n ~/ 10;
    letras += '${_decenas[decena]} ';
    n %= 10;
  }

  if (n > 0) {
    letras += '${_unidades[n]} ';
  }

  letras = _aplicarY(letras, n);
  return letras.trim();
}

/// Convierte un monto en lempiras a su representación en letras,
/// ej: 1250.50 -> "mil doscientos cincuenta lempiras con 50/100 centavos".
String convertirNumeroALetras(double monto) {
  if (monto == 0) return 'cero lempiras con 00/100 centavos';

  final enteros = monto.floor();
  final centavos = ((monto - enteros) * 100).round();

  var resto = enteros;
  var letras = '';

  if (resto >= 1000000) {
    final millones = resto ~/ 1000000;
    letras += '${_convertirMenosDeMil(millones)} millón ';
    resto %= 1000000;
  }

  if (resto >= 1000) {
    final miles = resto ~/ 1000;
    if (miles == 1) {
      letras += 'mil ';
    } else {
      letras += '${_convertirMenosDeMil(miles)} mil ';
    }
    resto %= 1000;
  }

  letras += _convertirMenosDeMil(resto);
  letras = letras.trim();
  if (letras.isEmpty) letras = 'cero';

  return '$letras lempiras con ${centavos.toString().padLeft(2, '0')}/100 centavos';
}
