import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/usuario_repository.dart';
import '../data/usuario_model.dart';

final usuarioRepositoryProvider = Provider((ref) => UsuarioRepository());

final usuariosStreamProvider = StreamProvider<List<UsuarioModel>>((ref) {
  return ref.watch(usuarioRepositoryProvider).obtenerUsuarios();
});

class UsuarioBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';

  void actualizar(String valor) {
    state = valor;
  }
}

final usuarioBusquedaProvider = NotifierProvider<UsuarioBusquedaNotifier, String>(UsuarioBusquedaNotifier.new);