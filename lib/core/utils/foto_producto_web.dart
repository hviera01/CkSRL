import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> partes, _OpcionesBlob opciones);
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _OpcionesBlob._(JSObject _) implements JSObject {
  external factory _OpcionesBlob({String type});
}

@JS('URL')
extension type _Url._(JSObject _) implements JSObject {
  external static String createObjectURL(_Blob blob);
  external static void revokeObjectURL(String url);
}

@JS('Image')
extension type _Imagen._(JSObject _) implements JSObject {
  external factory _Imagen();
  external set src(String valor);
  external int get naturalWidth;
  external int get naturalHeight;
  external JSPromise<JSAny?> decode();
}

@JS('document')
external _Documento get _documento;

extension type _Documento._(JSObject _) implements JSObject {
  external _Canvas createElement(String etiqueta);
}

extension type _Canvas._(JSObject _) implements JSObject {
  external set width(int valor);
  external set height(int valor);
  external _Contexto2d? getContext(String tipo);
  external void toBlob(JSFunction alTerminar, String tipo, num calidad);
}

extension type _Contexto2d._(JSObject _) implements JSObject {
  external set fillStyle(String valor);
  external set imageSmoothingQuality(String valor);
  external void fillRect(num x, num y, num ancho, num alto);
  external void drawImage(_Imagen imagen, num x, num y, num ancho, num alto);
}

Future<Uint8List?> reducirFotoEnNavegador(
  Uint8List bytes,
  int ladoMaximo,
  double calidad,
) async {
  final blobOriginal = _Blob([bytes.toJS].toJS, _OpcionesBlob(type: ''));
  final url = _Url.createObjectURL(blobOriginal);
  try {
    final imagen = _Imagen()..src = url;
    await imagen.decode().toDart;
    final anchoOriginal = imagen.naturalWidth;
    final altoOriginal = imagen.naturalHeight;
    if (anchoOriginal <= 0 || altoOriginal <= 0) return null;

    final mayor = anchoOriginal > altoOriginal ? anchoOriginal : altoOriginal;
    final escala = mayor > ladoMaximo ? ladoMaximo / mayor : 1.0;
    final ancho = (anchoOriginal * escala).round().clamp(1, ladoMaximo);
    final alto = (altoOriginal * escala).round().clamp(1, ladoMaximo);

    final canvas = _documento.createElement('canvas')
      ..width = ancho
      ..height = alto;
    final ctx = canvas.getContext('2d');
    if (ctx == null) return null;
    ctx.imageSmoothingQuality = 'high';
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, ancho, alto);
    ctx.drawImage(imagen, 0, 0, ancho, alto);

    final listo = Completer<_Blob?>();
    canvas.toBlob(
      ((_Blob? blob) => listo.complete(blob)).toJS,
      'image/jpeg',
      calidad,
    );
    final blob = await listo.future.timeout(const Duration(seconds: 20));
    if (blob == null) return null;
    final buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } finally {
    _Url.revokeObjectURL(url);
  }
}
