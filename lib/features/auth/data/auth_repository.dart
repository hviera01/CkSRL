import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/clave_hash.dart';
import 'usuario_model.dart';

class AuthRepository {
  final _db = FirebaseFirestore.instance;

  static const _maxIntentos = 5;
  static const _duracionBloqueo = Duration(minutes: 5);

  String hashClave(String clave) => ClaveHash.hashSinSal(clave);

  Future<UsuarioModel> login(String documento, String clave) async {
    final query = await _db
        .collection('usuarios')
        .where('documento', isEqualTo: documento)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Código de acceso no encontrado');
    }

    final doc = query.docs.first;
    final data = doc.data();

    if (data['estado'] != true) {
      throw Exception('Usuario inactivo, contacte al administrador');
    }

    final bloqueadoHasta = (data['bloqueadoHasta'] as Timestamp?)?.toDate();
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
        await doc.reference.update({'clave': ClaveHash.hash(clave, nuevaSal), 'sal': nuevaSal});
      }
    }

    if (!coincide) {
      final intentos = ((data['intentosFallidos'] ?? 0) as num).toInt() + 1;
      final actualizacion = <String, dynamic>{'intentosFallidos': intentos};
      if (intentos >= _maxIntentos) {
        actualizacion['bloqueadoHasta'] = Timestamp.fromDate(DateTime.now().add(_duracionBloqueo));
        actualizacion['intentosFallidos'] = 0;
      }
      await doc.reference.update(actualizacion);
      throw Exception('Contraseña incorrecta');
    }

    if (((data['intentosFallidos'] ?? 0) as num).toInt() != 0) {
      await doc.reference.update({'intentosFallidos': 0});
    }

    return UsuarioModel.fromMap(doc.id, data);
  }
}