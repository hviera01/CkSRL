import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ck_srl/core/utils/foto_producto.dart';
import 'package:ck_srl/features/productos/data/producto_export_service.dart';
import 'package:ck_srl/features/productos/data/producto_model.dart';
import 'package:image/image.dart' as img;

Future<int> _mayorPausaDelHiloPrincipal(Future<void> Function() tarea) async {
  final sw = Stopwatch()..start();
  var ultimo = sw.elapsedMilliseconds;
  var mayor = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    final ahora = sw.elapsedMilliseconds;
    if (ahora - ultimo > mayor) mayor = ahora - ultimo;
    ultimo = ahora;
  });
  await tarea();
  timer.cancel();
  return mayor;
}

void main() {
  test('el PDF de inventario grande no congela el hilo principal', () async {
    final productos = List.generate(
      1500,
      (i) => ProductoModel.fromMap('id$i', {
        'codigo': 'SKU$i',
        'codigo_barras': '200000000${i.toString().padLeft(4, '0')}',
        'nombre': 'Producto numero $i',
        'stock': i,
        'precio_venta': i * 1.5,
        'precio_compra': i * 1.0,
      }),
    );
    late Uint8List pdf;
    final pausa = await _mayorPausaDelHiloPrincipal(() async {
      pdf = await ProductoExportService().generarPdfInventario(productos, const {});
    });
    // ignore: avoid_print
    print('PDF 1500 productos: ${pdf.length ~/ 1024} KB, mayor pausa del hilo principal: $pausa ms');
    expect(pdf.isNotEmpty, isTrue);
    expect(pausa, lessThan(500));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('reducir una foto de 12MP no congela el hilo principal y la deja liviana', () async {
    final base = img.Image(width: 4000, height: 3000);
    for (var y = 0; y < base.height; y += 3) {
      for (var x = 0; x < base.width; x += 3) {
        base.setPixelRgb(x, y, x % 255, y % 255, (x + y) % 255);
      }
    }
    final original = Uint8List.fromList(img.encodeJpg(base, quality: 92));
    late FotoPreparada resultado;
    final pausa = await _mayorPausaDelHiloPrincipal(() async {
      resultado = await prepararFotoProducto(original, 'IMG_2044.JPG');
    });
    // ignore: avoid_print
    print('Foto ${original.length ~/ 1024} KB -> ${resultado.bytes.length ~/ 1024} KB, mayor pausa del hilo principal: $pausa ms');
    expect(resultado.bytes.length, lessThan(original.length));
    expect(resultado.nombreArchivo, 'IMG_2044.jpg');
    expect(pausa, lessThan(500));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
