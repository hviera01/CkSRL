import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/utils/clave_hash.dart';
import 'usuario_model.dart';

class AuthRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  static const _maxIntentos = 5;
  static const _duracionBloqueo = Duration(minutes: 5);

  String hashClave(String clave) => ClaveHash.hashSinSal(clave);

  Future<UsuarioModel> login(String documento, String clave) {
    return conRed(() async {
      final filas = await _db.from('usuarios').select().eq('documento', documento).limit(1);
      if (filas.isEmpty) {
        throw Exception('Código de acceso no encontrado');
      }
      final data = filas.first;
      final id = data['id'] as String;

      if (data['estado'] != true) {
        throw Exception('Usuario inactivo, contacte al administrador');
      }

      final bloqueadoHastaTexto = data['bloqueado_hasta'] as String?;
      final bloqueadoHasta = bloqueadoHastaTexto == null ? null : DateTime.parse(bloqueadoHastaTexto);
      if (bloqueadoHasta != null && bloqueadoHasta.isAfter(DateTime.now())) {
        final minutos = bloqueadoHasta.difference(DateTime.now()).inMinutes + 1;
        throw Exception('Demasiados intentos fallidos, esperá $minutos minuto(s) e intentá de nuevo');
      }

      final sal = data['sal'] as String?;
      bool coincide;
      if (sal != null && sal.isNotEmpty) {
        coincide = data['clave'] == ClaveHash.hash(clave, sal);
      } else {
        // Usuario creado antes de agregar la sal: valida contra el esquema
        // viejo y, si coincide, migra la clave a uno con sal en este mismo
        // login (transparente para el usuario, no tiene que hacer nada).
        coincide = data['clave'] == ClaveHash.hashSinSal(clave);
        if (coincide) {
          final nuevaSal = ClaveHash.generarSal();
          await _db.from('usuarios').update({'clave': ClaveHash.hash(clave, nuevaSal), 'sal': nuevaSal}).eq('id', id);
        }
      }

      if (!coincide) {
        final intentos = ((data['intentos_fallidos'] ?? 0) as num).toInt() + 1;
        final actualizacion = <String, dynamic>{'intentos_fallidos': intentos};
        if (intentos >= _maxIntentos) {
          actualizacion['bloqueado_hasta'] = DateTime.now().add(_duracionBloqueo).toIso8601String();
          actualizacion['intentos_fallidos'] = 0;
        }
        await _db.from('usuarios').update(actualizacion).eq('id', id);
        throw Exception('Contraseña incorrecta');
      }

      if (((data['intentos_fallidos'] ?? 0) as num).toInt() != 0) {
        await _db.from('usuarios').update({'intentos_fallidos': 0}).eq('id', id);
      }

      return UsuarioModel.fromMap(id, data);
    });
  }
}
