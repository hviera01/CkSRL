import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'categoria_model.dart';

class CategoriaRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<CategoriaModel>> obtenerCategorias() {
    return conRedStream(() => _db
        .from('categorias')
        .stream(primaryKey: ['id'])
        .order('descripcion')
        .map((filas) => filas.map((d) => CategoriaModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<void> crear(String descripcion, bool estado, {bool controlaStock = true}) {
    return conRed(() async {
      final existe = await _db.from('categorias').select('id').eq('descripcion', descripcion).limit(1);
      if (existe.isNotEmpty) {
        throw Exception('Ya existe una categoría con esa descripción');
      }
      await _db.from('categorias').insert({
        'descripcion': descripcion,
        'estado': estado,
        'controla_stock': controlaStock,
      });
    });
  }

  Future<void> actualizar(String id, String descripcion, bool estado, {bool controlaStock = true}) {
    return conRed(() async {
      final existe = await _db.from('categorias').select('id').eq('descripcion', descripcion).limit(2);
      final duplicado = existe.any((d) => d['id'] != id);
      if (duplicado) {
        throw Exception('Ya existe una categoría con esa descripción');
      }
      await _db.from('categorias').update({
        'descripcion': descripcion,
        'estado': estado,
        'controla_stock': controlaStock,
      }).eq('id', id);
    });
  }

  Future<void> eliminar(String id) {
    return conRed(() async {
      final productos = await _db.from('productos').select('id').eq('id_categoria', id).limit(1);
      if (productos.isNotEmpty) {
        throw Exception('La categoría se encuentra relacionada a un producto');
      }
      await _db.from('categorias').delete().eq('id', id);
    });
  }
}
