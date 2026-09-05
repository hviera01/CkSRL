import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/utils/clave_hash.dart';
import 'usuario_model.dart';

class UsuarioRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<UsuarioModel>> obtenerUsuarios() {
    return conRedStream(() => _db
        .from('usuarios')
        .stream(primaryKey: ['id'])
        .order('nombre_completo')
        .map((filas) => filas.map((d) => UsuarioModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<void> crear(String documento, String nombreCompleto, String correo, String clave, String rol, bool estado) {
    return conRed(() async {
      final existe = await _db.from('usuarios').select('id').eq('documento', documento).limit(1);
      if (existe.isNotEmpty) {
        throw Exception('El número de documento ya existe');
      }
      final sal = ClaveHash.generarSal();
      await _db.from('usuarios').insert({
        'documento': documento,
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'clave': ClaveHash.hash(clave, sal),
        'sal': sal,
        'rol': rol,
        'estado': estado,
        'intentos_fallidos': 0,
      });
    });
  }

  Future<void> actualizar(String id, String documento, String nombreCompleto, String correo, String rol, bool estado, [String? clave]) {
    return conRed(() async {
      final existe = await _db.from('usuarios').select('id').eq('documento', documento).limit(2);
      final duplicado = existe.any((d) => d['id'] != id);
      if (duplicado) {
        throw Exception('El número de documento ya existe');
      }
      final data = <String, dynamic>{
        'documento': documento,
        'nombre_completo': nombreCompleto,
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
        data['intentos_fallidos'] = 0;
        data['bloqueado_hasta'] = null;
      }
      await _db.from('usuarios').update(data).eq('id', id);
    });
  }

  Future<void> eliminar(String id) {
    return conRed(() async {
      final compras = await _db.from('compras').select('id').eq('usuario_registro', id).limit(1);
      if (compras.isNotEmpty) {
        throw Exception('No se puede eliminar porque el usuario se encuentra relacionado a una compra');
      }
      final ventas = await _db.from('ventas').select('id').eq('usuario_registro', id).limit(1);
      if (ventas.isNotEmpty) {
        throw Exception('No se puede eliminar porque el usuario se encuentra relacionado a una venta');
      }
      await _db.from('usuarios').delete().eq('id', id);
    });
  }
}
