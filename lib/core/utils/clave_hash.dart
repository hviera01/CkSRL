import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Hash de claves de usuario con sal por usuario, para que si alguien llega a
/// leer la colección `usuarios` (hoy es de lectura pública, ver
/// firestore.rules) no pueda romper las claves con una tabla rainbow
/// precalculada como sí podía con el sha256 plano anterior.
class ClaveHash {
  /// Sal aleatoria de 16 bytes, codificada en base64 URL-safe para guardarla
  /// como texto en Firestore.
  static String generarSal() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String hash(String clave, String sal) {
    return sha256.convert(utf8.encode('$sal:$clave')).toString();
  }

  /// Esquema anterior (sin sal), mantenido solo para validar y migrar en el
  /// momento a usuarios que todavía no iniciaron sesión desde el cambio.
  static String hashSinSal(String clave) {
    return sha256.convert(utf8.encode(clave)).toString();
  }
}
