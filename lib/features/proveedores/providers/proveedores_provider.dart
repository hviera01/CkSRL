import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/proveedor_repository.dart';
import '../data/proveedor_model.dart';

final proveedorRepositoryProvider = Provider((ref) => ProveedorRepository());

final proveedoresStreamProvider = StreamProvider<List<ProveedorModel>>((ref) {
  return ref.watch(proveedorRepositoryProvider).obtenerProveedores();
});

class ProveedoresBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final proveedoresBusquedaProvider = NotifierProvider<ProveedoresBusquedaNotifier, String>(ProveedoresBusquedaNotifier.new);

class ProveedoresVistaNotifier extends Notifier<String> {
  @override
  String build() => 'filtrados';
  void actualizar(String valor) => state = valor;
}

final proveedoresVistaProvider = NotifierProvider<ProveedoresVistaNotifier, String>(ProveedoresVistaNotifier.new);
