import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/egreso_repository.dart';

final egresoRepositoryProvider = Provider((ref) => EgresoRepository());
