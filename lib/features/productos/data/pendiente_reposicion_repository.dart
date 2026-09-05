import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'pendiente_reposicion_model.dart';

class PendienteReposicionRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  /// Solo las que siguen esperando compra, la más vieja primero -mismo
  /// orden en el que registrar_compra las va a repartir-.
  Stream<List<PendienteReposicionModel>> obtenerPendientes() {
    return conRedStream(() => _db
        .from('pendientes_reposicion')
        .stream(primaryKey: ['id'])
        .eq('estado', 'Pendiente')
        .order('fecha_registro')
        .map((filas) => filas.map((d) => PendienteReposicionModel.fromMap(d['id'] as String, d)).toList()));
  }

  /// El negocio decide a mano que esto ya no va a esperar una compra. No
  /// borra la fila -queda como 'Cancelado' para no perder el rastro-, pero
  /// deja de aparecer en [obtenerPendientes] y de competir por futuras compras.
  Future<void> cancelar(String id) {
    return conRed(() => _db.from('pendientes_reposicion').update({
          'estado': 'Cancelado',
          'fecha_completado': DateTime.now().toIso8601String(),
        }).eq('id', id));
  }
}
