import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/cierre_caja_repository.dart';
import '../data/cierre_caja_model.dart';

final cierreCajaRepositoryProvider = Provider((ref) => CierreCajaRepository());

final historialCierresProvider = StreamProvider<List<CierreCajaModel>>((ref) {
  return ref.watch(cierreCajaRepositoryProvider).obtenerHistorial();
});
