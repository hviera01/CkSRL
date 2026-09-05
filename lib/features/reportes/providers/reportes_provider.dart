import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reporte_repository.dart';
import '../data/reporte_financiero_repository.dart';

final reporteRepositoryProvider = Provider((ref) => ReporteRepository());

final reporteFinancieroRepositoryProvider = Provider((ref) => ReporteFinancieroRepository());
