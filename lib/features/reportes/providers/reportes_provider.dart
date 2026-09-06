import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reporte_repository.dart';
import '../data/reporte_financiero_repository.dart';

final reporteRepositoryProvider = Provider((ref) => ReporteRepository());

final reporteFinancieroRepositoryProvider = Provider((ref) => ReporteFinancieroRepository());

/// Un stream liviano por tabla (family), para que las pantallas de Reporte
/// (Ventas/Compras/Financiero) se refresquen solas cuando algo cambia en las
/// tablas de las que dependen -ver ReporteRepository.observarCambiosEnTabla-.
/// autoDispose: el canal de Realtime se cierra solo al cerrar la pestaña del
/// reporte (deja de haber quien lo escuche), no se queda abierto de más.
final cambiosEnTablaProvider = StreamProvider.family.autoDispose<void, String>(
  (ref, tabla) => ref.watch(reporteRepositoryProvider).observarCambiosEnTabla(tabla),
);
