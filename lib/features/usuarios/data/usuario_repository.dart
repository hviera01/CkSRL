import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/clave_hash.dart';
import 'usuario_model.dart';

class UsuarioRepository {
  final _col = FirebaseFirestore.instance.collection('usuarios');

  Stream<List<UsuarioModel>> obtenerUsuarios() {
    return _col.orderBy('nombreCompleto').snapshots().map((snap) {
      return snap.docs.map((d) => UsuarioModel.fromMap(d.id, d.data())).toList();
    });
  }

  Future<void> crear(String documento, String nombreCompleto, String correo, String clave, String rol, bool estado) async {
    final existe = await _col.where('documento', isEqualTo: documento).limit(1).get();
    if (existe.docs.isNotEmpty) {
      throw Exception('El número de documento ya existe');
    }
    final sal = ClaveHash.generarSal();
    await _col.add({
      'documento': documento,
      'nombreCompleto': nombreCompleto,
      'correo': correo,
      'clave': ClaveHash.hash(clave, sal),
      'sal': sal,
      'rol': rol,
      'estado': estado,
      'intentosFallidos': 0,
      'fechaRegistro': FieldValue.serverTimestamp(),
    });
  }

  Future<void> actualizar(String id, String documento, String nombreCompleto, String correo, String rol, bool estado, [String? clave]) async {
    final existe = await _col.where('documento', isEqualTo: documento).limit(2).get();
    final duplicado = existe.docs.any((d) => d.id != id);
    if (duplicado) {
      throw Exception('El número de documento ya existe');
    }
    final data = <String, dynamic>{
      'documento': documento,
      'nombreCompleto': nombreCompleto,
      'correo': correo,
      'rol': rol,
      'estado': estado,
    };
    if (clave != null && clave.trim().isNotEmpty) {
      // Cambiar la clave desbloquea al usuario y reinicia los intentos
      // fallidos: es una acción administrativa deliberada.
      final sal = ClaveHash.generarSal();
      data['clave'] = ClaveHash.hash(clave, sal);
      data['sal'] = sal;
      data['intentosFallidos'] = 0;
      data['bloqueadoHasta'] = null;
    }
    await _col.doc(id).update(data);
  }

  Future<void> eliminar(String id) async {
    final compras = await FirebaseFirestore.instance
        .collection('compras')
        .where('idUsuario', isEqualTo: id)
        .limit(1)
        .get();
    if (compras.docs.isNotEmpty) {
      throw Exception('No se puede eliminar porque el usuario se encuentra relacionado a una compra');
    }
    final ventas = await FirebaseFirestore.instance
        .collection('ventas')
        .where('idUsuario', isEqualTo: id)
        .limit(1)
        .get();
    if (ventas.docs.isNotEmpty) {
      throw Exception('No se puede eliminar porque el usuario se encuentra relacionado a una venta');
    }
    await _col.doc(id).delete();
  }
}