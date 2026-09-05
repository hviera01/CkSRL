import 'package:cloud_firestore/cloud_firestore.dart';
import 'categoria_model.dart';

class CategoriaRepository {
  final _col = FirebaseFirestore.instance.collection('categorias');

  Stream<List<CategoriaModel>> obtenerCategorias() {
    return _col.orderBy('descripcion').snapshots().map((snap) {
      return snap.docs.map((d) => CategoriaModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crear(String descripcion, bool estado, {bool controlaStock = true}) async {
    final existe = await _col.where('descripcion', isEqualTo: descripcion).limit(1).get();
    if (existe.docs.isNotEmpty) {
      throw Exception('Ya existe una categoría con esa descripción');
    }
    await _col.add({
      'descripcion': descripcion,
      'estado': estado,
      'controlaStock': controlaStock,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
  }

  Future<void> actualizar(String id, String descripcion, bool estado, {bool controlaStock = true}) async {
    final existe = await _col.where('descripcion', isEqualTo: descripcion).limit(2).get();
    final duplicado = existe.docs.any((d) => d.id != id);
    if (duplicado) {
      throw Exception('Ya existe una categoría con esa descripción');
    }
    await _col.doc(id).update({
      'descripcion': descripcion,
      'estado': estado,
      'controlaStock': controlaStock,
    });
  }

  Future<void> eliminar(String id) async {
    final productos = await FirebaseFirestore.instance
        .collection('productos')
        .where('idCategoria', isEqualTo: id)
        .limit(1)
        .get();
    if (productos.docs.isNotEmpty) {
      throw Exception('La categoría se encuentra relacionada a un producto');
    }
    await _col.doc(id).delete();
  }
}