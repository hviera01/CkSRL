import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'promocion_model.dart';

/// Colección chica (se arman a mano, no crecen como las ventas) y se
/// consulta en vivo durante una venta en curso -por eso usa `.stream()`
/// igual que productos/categorías/clientes-. Las listas de productos de cada
/// promoción viven normalizadas en `promocion_productos` (catálogo VIVO, ver
/// comentario en supabase/schema.sql), así que además del stream de
/// `promociones` hace falta resolver esa tabla puente (con el nombre ACTUAL
/// de cada producto, vía join) cada vez que la lista cambia -esta colección
/// es chica, así que ese round-trip extra por cambio es barato-.
class PromocionRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<PromocionModel>> obtenerPromociones() {
    return conRedStream(() => _db
        .from('promociones')
        .stream(primaryKey: ['id'])
        .order('creado_en', ascending: false)
        .asyncMap(_resolverConProductos));
  }

  Future<List<PromocionModel>> _resolverConProductos(List<Map<String, dynamic>> filas) async {
    if (filas.isEmpty) return const [];
    final ids = filas.map((f) => f['id'] as String).toList();
    final puente = await _db
        .from('promocion_productos')
        .select('id_promocion, rol, productos(id, nombre)')
        .inFilter('id_promocion', ids);

    // Agrupa por promoción y rol: {idPromocion: {rol: [(id, nombre), ...]}}
    final porPromocion = <String, Map<String, List<(String, String)>>>{};
    for (final fila in puente) {
      final idPromocion = fila['id_promocion'] as String;
      final rol = fila['rol'] as String;
      final producto = fila['productos'] as Map<String, dynamic>?;
      if (producto == null) continue;
      porPromocion.putIfAbsent(idPromocion, () => {});
      porPromocion[idPromocion]!.putIfAbsent(rol, () => []);
      porPromocion[idPromocion]![rol]!.add((producto['id'] as String, producto['nombre'] as String? ?? ''));
    }

    return filas.map((fila) {
      final id = fila['id'] as String;
      final grupos = porPromocion[id] ?? const {};
      List<String> idsDe(String rol) => (grupos[rol] ?? const []).map((p) => p.$1).toList();
      List<String> nombresDe(String rol) => (grupos[rol] ?? const []).map((p) => p.$2).toList();
      return PromocionModel.fromMap(
        id,
        fila,
        idsProductos: idsDe('individual'),
        nombresProductos: nombresDe('individual'),
        idsProductosCombo: idsDe('combo'),
        nombresProductosCombo: nombresDe('combo'),
        idsProductosRegalo: idsDe('regalo'),
        nombresProductosRegalo: nombresDe('regalo'),
      );
    }).toList();
  }

  Future<void> _guardarProductosPuente(String idPromocion, PromocionModel promocion) async {
    await _db.from('promocion_productos').delete().eq('id_promocion', idPromocion);
    final filas = <Map<String, dynamic>>[
      for (final id in promocion.idsProductos) {'id_promocion': idPromocion, 'id_producto': id, 'rol': 'individual'},
      for (final id in promocion.idsProductosCombo) {'id_promocion': idPromocion, 'id_producto': id, 'rol': 'combo'},
      for (final id in promocion.idsProductosRegalo) {'id_promocion': idPromocion, 'id_producto': id, 'rol': 'regalo'},
    ];
    if (filas.isNotEmpty) await _db.from('promocion_productos').insert(filas);
  }

  Future<void> crear(PromocionModel promocion) {
    return conRed(() async {
      final fila = await _db.from('promociones').insert(promocion.toMap()).select('id').single();
      await _guardarProductosPuente(fila['id'] as String, promocion);
    });
  }

  Future<void> actualizar(PromocionModel promocion) {
    return conRed(() async {
      await _db.from('promociones').update(promocion.toMap()).eq('id', promocion.id);
      await _guardarProductosPuente(promocion.id, promocion);
    });
  }

  Future<void> alternarActivo(String id, bool activo) {
    return conRed(() => _db.from('promociones').update({'activo': activo}).eq('id', id));
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('promociones').delete().eq('id', id));
  }
}
