import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'lote_costo_model.dart';

/// Costeo FIFO por lotes (ver LoteCostoModel). El consumo/creación de lotes
/// dentro de una operación que también toca stock/historial (venta, compra,
/// ajuste) ahora vive en funciones de Postgres (ver
/// supabase/schema.sql: consumir_fifo_lotes, sincronizar_precio_compra_activo,
/// registrar_venta, registrar_compra, etc.) -Postgres sí permite una
/// transacción real de verdad, a diferencia de las limitaciones de
/// Transaction.get de Firestore que forzaban antes a separar lecturas de
/// escrituras a mano-. Esta clase queda para lo que la UI todavía consume
/// directo: ver los lotes de un producto y reordenarlos a mano.
class LoteCostoRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  /// Para mostrar en pantalla: todos los lotes de un producto (agotados o
  /// no), en el orden en que el costeo FIFO los va a ir consumiendo — por
  /// fecha (el más viejo primero), salvo que el usuario haya reordenado a
  /// mano con [reordenarLotes].
  Stream<List<LoteCostoModel>> obtenerLotes(String idProducto) {
    return conRedStream(() => _db
        .from('producto_lotes_costo')
        .stream(primaryKey: ['id'])
        .eq('id_producto', idProducto)
        .order('fecha')
        .map((filas) {
      final lotes = filas.map((d) => LoteCostoModel.fromMap(d['id'] as String, d)).toList();
      lotes.sort(_compararLotesPorPrioridad);
      return lotes;
    }));
  }

  /// Cambia a mano cuál lote sale primero (0 = primero) — ver
  /// reordenar_lotes en supabase/schema.sql.
  Future<void> reordenarLotes(String idProducto, List<String> idsEnOrdenDeseado) {
    return conRed(() => _db.rpc('reordenar_lotes', params: {
          'p_id_producto': idProducto,
          'p_ids_orden': idsEnOrdenDeseado,
        }));
  }
}

/// Lote que el FIFO va a consumir a continuación de una lista YA completa de
/// lotes de un producto (agotados o no): el primero, en el mismo orden que
/// usa el costeo real, que todavía tenga cantidadRestante > 0. Null si no
/// queda ninguno. Sin Supabase a propósito, para poder probarla con datos de
/// prueba sin necesitar un backend real.
LoteCostoModel? loteActivo(List<LoteCostoModel> lotes) {
  final ordenados = [...lotes]..sort(_compararLotesPorPrioridad);
  for (final lote in ordenados) {
    if (lote.cantidadRestante > 0) return lote;
  }
  return null;
}

/// Mismo criterio de orden que usa el costeo FIFO real en Postgres
/// (consumir_fifo_lotes): prioridad manual si existe, si no la fecha, más
/// viejo primero.
int _compararLotesPorPrioridad(LoteCostoModel a, LoteCostoModel b) {
  if (a.prioridad != null && b.prioridad != null) return a.prioridad!.compareTo(b.prioridad!);
  if (a.prioridad != null) return -1;
  if (b.prioridad != null) return 1;
  return a.fecha.compareTo(b.fecha);
}
