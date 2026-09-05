import 'package:cloud_firestore/cloud_firestore.dart';
import 'color_model.dart';
import 'color_import_service.dart';

class ColorRepository {
  final _col = FirebaseFirestore.instance.collection('colores');

  Stream<List<ColorModel>> obtenerColores() {
    return _col.orderBy('fechaRegistro', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => ColorModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crear({
    required String codigo,
    required String cliente,
    required String descripcion,
    required String ubicacionFisica,
    required String pagina,
    required DateTime? fechaRegistro,
    required String observaciones,
  }) async {
    await _col.add({
      'codigo': codigo,
      'cliente': cliente,
      'descripcion': descripcion,
      'ubicacionFisica': ubicacionFisica,
      'pagina': pagina,
      'fechaRegistro': fechaRegistro != null ? Timestamp.fromDate(fechaRegistro) : FieldValue.serverTimestamp(),
      'observaciones': observaciones,
    });
  }

  Future<void> actualizar({
    required String id,
    required String codigo,
    required String cliente,
    required String descripcion,
    required String ubicacionFisica,
    required String pagina,
    required DateTime? fechaRegistro,
    required String observaciones,
  }) async {
    await _col.doc(id).update({
      'codigo': codigo,
      'cliente': cliente,
      'descripcion': descripcion,
      'ubicacionFisica': ubicacionFisica,
      'pagina': pagina,
      'fechaRegistro': fechaRegistro != null ? Timestamp.fromDate(fechaRegistro) : null,
      'observaciones': observaciones,
    });
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }

  /// Crea en lote los registros de una importación desde Excel. No empareja
  /// con registros existentes (el libro histórico no trae ningún id único
  /// confiable): cada fila del archivo se agrega como un registro nuevo.
  Future<int> importarColores(List<FilaImportacionColor> filas) async {
    var creados = 0;
    var batch = FirebaseFirestore.instance.batch();
    var operacionesEnBatch = 0;

    Future<void> descargarBatch() async {
      if (operacionesEnBatch == 0) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      operacionesEnBatch = 0;
    }

    for (final fila in filas) {
      final ref = _col.doc();
      batch.set(ref, {
        'codigo': fila.codigo,
        'cliente': fila.cliente,
        'descripcion': fila.descripcion,
        'ubicacionFisica': fila.ubicacionFisica,
        'pagina': fila.pagina,
        'fechaRegistro': fila.fechaRegistro != null ? Timestamp.fromDate(fila.fechaRegistro!) : null,
        'observaciones': fila.observaciones,
      });
      creados++;
      operacionesEnBatch++;
      if (operacionesEnBatch >= 400) await descargarBatch();
    }
    await descargarBatch();
    return creados;
  }
}
