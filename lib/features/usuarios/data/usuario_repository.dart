import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/utils/clave_hash.dart';
import '../../../core/utils/reintentos.dart';
import '../../../core/constants/roles.dart';
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

  /// Lectura única (no depende de que un listener en vivo llegue a emitir
  /// su primer valor) para gates de seguridad como `verificarAccesoEspecial`
  /// que necesitan la lista de usuarios YA, con un timeout corto y algunos
  /// reintentos (ver [conReintentos]). A diferencia de esperar el primer
  /// valor de [obtenerUsuarios] -que en un arranque de app en frío, con la
  /// conexión todavía estableciéndose, puede tardar mucho o no resolver
  /// nunca sin avisar nada-, esto reintenta ante una demora pasajera y solo
  /// si de verdad se agotan los reintentos lanza la excepción, para que el
  /// llamador pueda mostrar un error real en vez de quedarse esperando en
  /// silencio o bloquear por una demora que se hubiera resuelto sola.
  Future<List<UsuarioModel>> obtenerUsuariosParaSeguridad() async {
    return conReintentos(() async {
      final filas = await _db.from('usuarios').select().order('nombre_completo').timeout(const Duration(seconds: 8));
      return filas.map((d) => UsuarioModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  Future<void> crear(
    String documento,
    String nombreCompleto,
    String correo,
    String clave,
    String rol,
    bool estado, [
    Map<String, bool> pantallasPermitidas = const {},
    Map<String, bool> accionesPermitidas = const {},
  ]) {
    return conRed(() async {
      final existe = await _db.from('usuarios').select('id').eq('documento', documento).limit(1);
      if (existe.isNotEmpty) {
        throw Exception('El número de documento ya existe');
      }
      final sal = ClaveHash.generarSal();
      // Los mapas de permisos ad-hoc solo tienen sentido (y solo se guardan)
      // para el rol Encargado: para cualquier otro rol se persisten vacíos,
      // así los registros no se ensucian con datos que no aplican.
      final esEncargado = rol == Roles.encargado;
      await _db.from('usuarios').insert({
        'documento': documento,
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'clave': ClaveHash.hash(clave, sal),
        'sal': sal,
        'rol': rol,
        'estado': estado,
        'intentos_fallidos': 0,
        'pantallas_permitidas': esEncargado ? pantallasPermitidas : {},
        'acciones_permitidas': esEncargado ? accionesPermitidas : {},
      });
    });
  }

  Future<void> actualizar(
    String id,
    String documento,
    String nombreCompleto,
    String correo,
    String rol,
    bool estado, [
    String? clave,
    Map<String, bool> pantallasPermitidas = const {},
    Map<String, bool> accionesPermitidas = const {},
  ]) {
    return conRed(() async {
      final existe = await _db.from('usuarios').select('id').eq('documento', documento).limit(2);
      final duplicado = existe.any((d) => d['id'] != id);
      if (duplicado) {
        throw Exception('El número de documento ya existe');
      }
      final esEncargado = rol == Roles.encargado;
      final data = <String, dynamic>{
        'documento': documento,
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'rol': rol,
        'estado': estado,
        'pantallas_permitidas': esEncargado ? pantallasPermitidas : {},
        'acciones_permitidas': esEncargado ? accionesPermitidas : {},
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
