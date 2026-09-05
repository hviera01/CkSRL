import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'proveedor_model.dart';

class ProveedorRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<ProveedorModel>> obtenerProveedores() {
    return conRedStream(() => _db
        .from('proveedores')
        .stream(primaryKey: ['id'])
        .order('razon_social')
        .map((filas) => filas.map((d) => ProveedorModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<void> crear({
    required String rtn,
    required String razonSocial,
    required String correo,
    required String telefono,
    required bool estado,
  }) {
    return conRed(() async {
      if (rtn.isNotEmpty) {
        final existe = await _db.from('proveedores').select('id').eq('rtn', rtn).limit(1);
        if (existe.isNotEmpty) {
          throw Exception('Ya existe un proveedor con ese RTN');
        }
      }
      await _db.from('proveedores').insert({
        'rtn': rtn,
        'razon_social': razonSocial,
        'correo': correo,
        'telefono': telefono,
        'estado': estado,
      });
    });
  }

  Future<void> actualizar({
    required String id,
    required String rtn,
    required String razonSocial,
    required String correo,
    required String telefono,
    required bool estado,
  }) {
    return conRed(() async {
      if (rtn.isNotEmpty) {
        final existe = await _db.from('proveedores').select('id').eq('rtn', rtn).limit(2);
        final duplicado = existe.any((d) => d['id'] != id);
        if (duplicado) {
          throw Exception('Ya existe un proveedor con ese RTN');
        }
      }
      await _db.from('proveedores').update({
        'rtn': rtn,
        'razon_social': razonSocial,
        'correo': correo,
        'telefono': telefono,
        'estado': estado,
      }).eq('id', id);
    });
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('proveedores').delete().eq('id', id));
  }
}
