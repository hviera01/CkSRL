import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'cliente_model.dart';
import '../../../core/utils/texto_utils.dart';

class ClienteRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<ClienteModel>> obtenerClientes() {
    return conRedStream(() => _db
        .from('clientes')
        .stream(primaryKey: ['id'])
        .order('nombre_completo')
        .map((filas) => filas.map((d) => ClienteModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<ClienteModel?> obtenerPorId(String id) {
    return conRed(() async {
      final filas = await _db.from('clientes').select().eq('id', id).limit(1);
      if (filas.isEmpty) return null;
      return ClienteModel.fromMap(filas.first['id'] as String, filas.first);
    });
  }

  // Devuelve el ClienteModel recién creado (con su id real ya asignado) -lo
  // necesita, por ejemplo, "Crear cliente nuevo" desde BuscarClienteDialog
  // (ver item 5 del pedido del dueño): tiene que poder vincular ese cliente
  // a la venta en curso apenas se guarda, con el mismo Navigator.pop(context,
  // cliente) que usa elegir uno ya existente.
  Future<ClienteModel> crear({
    required String dni,
    required String nombreCompleto,
    required String direccion,
    required String telefono,
    required bool estado,
    String? idReferidor,
    bool esReferidor = false,
  }) {
    return conRed(() async {
      if (dni.isNotEmpty) {
        final existe = await _db.from('clientes').select('id').eq('dni', dni).limit(1);
        if (existe.isNotEmpty) {
          throw Exception('Ya existe un cliente con ese DNI');
        }
      }
      // 'nombre_normalizado' (mayúsculas/tildes/espacios colapsados) para que
      // VentaRepository pueda encontrar un cliente por nombre sin exigir
      // igualdad exacta de string.
      final fila = await _db.from('clientes').insert({
        'dni': dni,
        'nombre_completo': nombreCompleto,
        'nombre_normalizado': normalizarNombreCliente(nombreCompleto),
        'direccion': direccion,
        'telefono': telefono,
        'estado': estado,
        'id_referidor': idReferidor,
        'es_referidor': esReferidor,
      }).select().single();
      return ClienteModel.fromMap(fila['id'] as String, fila);
    });
  }

  Future<void> actualizar({
    required String id,
    required String dni,
    required String nombreCompleto,
    required String direccion,
    required String telefono,
    required bool estado,
    String? idReferidor,
    bool esReferidor = false,
  }) {
    return conRed(() async {
      if (dni.isNotEmpty) {
        final existe = await _db.from('clientes').select('id').eq('dni', dni).limit(2);
        final duplicado = existe.any((d) => d['id'] != id);
        if (duplicado) {
          throw Exception('Ya existe un cliente con ese DNI');
        }
      }
      // A propósito NO se toca fecha_ultima_compra acá (ver comentario en
      // ClienteModel.toMap): ese campo lo escribe otro flujo (registrar venta).
      await _db.from('clientes').update({
        'dni': dni,
        'nombre_completo': nombreCompleto,
        'nombre_normalizado': normalizarNombreCliente(nombreCompleto),
        'direccion': direccion,
        'telefono': telefono,
        'estado': estado,
        'id_referidor': idReferidor,
        'es_referidor': esReferidor,
      }).eq('id', id);
    });
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('clientes').delete().eq('id', id));
  }
}
