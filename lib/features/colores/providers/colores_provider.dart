import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/color_repository.dart';
import '../data/color_model.dart';

final colorRepositoryProvider = Provider((ref) => ColorRepository());

final coloresStreamProvider = StreamProvider<List<ColorModel>>((ref) {
  return ref.watch(colorRepositoryProvider).obtenerColores();
});

class ColoresBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final coloresBusquedaProvider = NotifierProvider<ColoresBusquedaNotifier, String>(ColoresBusquedaNotifier.new);

class ColoresVistaNotifier extends Notifier<String> {
  @override
  String build() => 'filtrados';
  void actualizar(String valor) => state = valor;
}

final coloresVistaProvider = NotifierProvider<ColoresVistaNotifier, String>(ColoresVistaNotifier.new);
