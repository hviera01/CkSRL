import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const _ladoMaximo = 1600;
const _pesoQueNoNecesitaReducirse = 350 * 1024;

class FotoPreparada {
  final Uint8List bytes;
  final String nombreArchivo;

  const FotoPreparada(this.bytes, this.nombreArchivo);
}

Future<FotoPreparada> prepararFotoProducto(Uint8List original, String nombreOriginal) async {
  final base = nombreOriginal.contains('.')
      ? nombreOriginal.substring(0, nombreOriginal.lastIndexOf('.'))
      : nombreOriginal;
  final extension = nombreOriginal.contains('.')
      ? nombreOriginal.substring(nombreOriginal.lastIndexOf('.') + 1).toLowerCase()
      : 'jpg';

  if (kIsWeb) {
    return FotoPreparada(original, '$base.$extension');
  }

  final esJpg = extension == 'jpg' || extension == 'jpeg';
  if (esJpg && original.length <= _pesoQueNoNecesitaReducirse) {
    return FotoPreparada(original, '$base.jpg');
  }

  try {
    final reducida = await compute(_reducirFoto, original);
    if (reducida != null) return FotoPreparada(reducida, '$base.jpg');
  } catch (_) {}
  return FotoPreparada(original, '$base.$extension');
}

Uint8List? _reducirFoto(Uint8List bytes) {
  final decodificada = img.decodeImage(bytes);
  if (decodificada == null) return null;
  var imagen = img.bakeOrientation(decodificada);
  final mayor = imagen.width > imagen.height ? imagen.width : imagen.height;
  if (mayor > _ladoMaximo) {
    imagen = img.copyResize(
      imagen,
      width: imagen.width >= imagen.height ? _ladoMaximo : null,
      height: imagen.height > imagen.width ? _ladoMaximo : null,
      interpolation: img.Interpolation.average,
    );
  }
  return Uint8List.fromList(img.encodeJpg(imagen, quality: 85));
}
