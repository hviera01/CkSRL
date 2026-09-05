import 'package:cloud_firestore/cloud_firestore.dart';
import 'proveedor_model.dart';

class ProveedorRepository {
  final _col = FirebaseFirestore.instance.collection('proveedores');

  Stream<List<ProveedorModel>> obtenerProveedores() {
    return _col.orderBy('razonSocial').snapshots().map((snap) {
      return snap.docs.map((d) => ProveedorModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crear({
    required String rtn,
    required String razonSocial,
    required String correo,
    required String telefono,
    required bool estado,
  }) async {
    if (rtn.isNotEmpty) {
      final existe = await _col.where('rtn', isEqualTo: rtn).limit(1).get();
      if (existe.docs.isNotEmpty) {
        throw Exception('Ya existe un proveedor con ese RTN');
      }
    }
    await _col.add({
      'rtn': rtn,
      'razonSocial': razonSocial,
      'correo': correo,
      'telefono': telefono,
      'estado': estado,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
  }

  Future<void> actualizar({
    required String id,
    required String rtn,
    required String razonSocial,
    required String correo,
    required String telefono,
    required bool estado,
  }) async {
    if (rtn.isNotEmpty) {
      final existe = await _col.where('rtn', isEqualTo: rtn).limit(2).get();
      final duplicado = existe.docs.any((d) => d.id != id);
      if (duplicado) {
        throw Exception('Ya existe un proveedor con ese RTN');
      }
    }
    await _col.doc(id).update({
      'rtn': rtn,
      'razonSocial': razonSocial,
      'correo': correo,
      'telefono': telefono,
      'estado': estado,
    });
  }

  Future<void> eliminar(String id) async {
    await _col.doc(id).delete();
  }
}
