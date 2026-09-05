/// Reintenta [accion] varias veces con una pequeña espera entre intento e
/// intento antes de rendirse. Pensado para lecturas de red puntuales que son
/// intolerantes a la demora de conexión típica de un arranque de app en frío
/// (Supabase recién conectando): en vez de fallar al primer timeout -que en
/// gates de seguridad como `verificarAccesoEspecial` se traduce en bloquear
/// al cajero sin poder hacer nada-, le da a la red un par de oportunidades
/// más de responder antes de relanzar la excepción de verdad.
Future<T> conReintentos<T>(
  Future<T> Function() accion, {
  int intentos = 3,
  Duration esperaEntreIntentos = const Duration(seconds: 2),
}) async {
  for (var intento = 1; intento <= intentos; intento++) {
    try {
      return await accion();
    } catch (_) {
      if (intento == intentos) rethrow;
      await Future.delayed(esperaEntreIntentos);
    }
  }
  // Inalcanzable: el loop de arriba siempre retorna o relanza en el último intento.
  throw StateError('conReintentos: no debería llegar acá');
}
