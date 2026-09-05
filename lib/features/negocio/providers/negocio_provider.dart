import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/negocio_repository.dart';
import '../data/negocio_model.dart';

final negocioRepositoryProvider = Provider((ref) => NegocioRepository());

final negocioStreamProvider = StreamProvider<NegocioModel>((ref) {
  return ref.watch(negocioRepositoryProvider).obtenerNegocio();
});
