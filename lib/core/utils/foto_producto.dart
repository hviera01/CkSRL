import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'foto_producto_stub.dart'
    if (dart.library.js_interop) 'foto_producto_web.dart'
    as impl;

const _ladoMaximo = 1600;
const _calidad = 85;

class FotoPreparada {
  final Uint8List bytes;
  final String nombreArchivo;

  const FotoPreparada(this.bytes, this.nombreArchivo);
}

Future<FotoPreparada> prepararFotoProducto(Uint8List original, String nombreOriginal) async {
  final base = nombreOriginal.contains('.')
      ? nombreOriginal.substring(0, nombreOriginal.lastIndexOf('.'))
      : nombreOriginal;
  var extension = nombreOriginal.contains('.')
      ? nombreOriginal.substring(nombreOriginal.lastIndexOf('.') + 1).toLowerCase()
      : 'jpg';
  if (extension == 'jpeg') extension = 'jpg';

  try {
    final Uint8List? reducida = kIsWeb
        ? await impl.reducirFotoEnNavegador(original, _ladoMaximo, _calidad / 100)
        : await compute(_reducirFoto, original);
    if (reducida != null &&
        reducida.isNotEmpty &&
        (reducida.length < original.length || extension != 'jpg')) {
      return FotoPreparada(reducida, '$base.jpg');
    }
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
  if (imagen.hasAlpha) {
    final fondo = img.Image(width: imagen.width, height: imagen.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    imagen = img.compositeImage(fondo, imagen);
  }
  return Uint8List.fromList(img.encodeJpg(imagen, quality: _calidad));
}
