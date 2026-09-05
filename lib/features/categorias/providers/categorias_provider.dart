import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/categoria_repository.dart';
import '../data/categoria_model.dart';

final categoriaRepositoryProvider = Provider((ref) => CategoriaRepository());

final categoriasStreamProvider = StreamProvider<List<CategoriaModel>>((ref) {
  return ref.watch(categoriaRepositoryProvider).obtenerCategorias();
});

class CategoriaBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';

  void actualizar(String valor) {
    state = valor;
  }
}

final categoriaBusquedaProvider = NotifierProvider<CategoriaBusquedaNotifier, String>(CategoriaBusquedaNotifier.new);