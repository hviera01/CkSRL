import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/apartado_repository.dart';
import '../data/apartado_model.dart';
import '../data/apartado_item_model.dart';
import '../data/apartado_cuota_model.dart';
import '../data/apartado_abono_model.dart';

final apartadoRepositoryProvider = Provider((ref) => ApartadoRepository());

final apartadosStreamProvider = StreamProvider<List<ApartadoModel>>((ref) {
  return ref.watch(apartadoRepositoryProvider).obtenerApartados();
});

final apartadoItemsProvider = StreamProvider.family<List<ApartadoItemModel>, String>((ref, idApartado) {
  return ref.watch(apartadoRepositoryProvider).obtenerItems(idApartado);
});

final apartadoCuotasProvider = StreamProvider.family<List<ApartadoCuotaModel>, String>((ref, idApartado) {
  return ref.watch(apartadoRepositoryProvider).obtenerCuotas(idApartado);
});

final apartadoAbonosProvider = StreamProvider.family<List<ApartadoAbonoModel>, String>((ref, idApartado) {
  return ref.watch(apartadoRepositoryProvider).obtenerAbonos(idApartado);
});

// --- Streams "globales" (todas las filas, sin filtrar por apartado) para
// calcular en memoria, sin ida y vuelta extra, cosas que dependen de más de
// un apartado a la vez -mismo patrón que ya usa el resto de la app para
// "joins" en memoria sobre streams (ver InventarioScreen con categorías)-.
final todosLosApartadoItemsProvider = StreamProvider<List<ApartadoItemModel>>((ref) {
  return ref.watch(apartadoRepositoryProvider).obtenerTodosLosItems();
});

final todosLosApartadoAbonosProvider = StreamProvider<List<ApartadoAbonoModel>>((ref) {
  return ref.watch(apartadoRepositoryProvider).obtenerTodosLosAbonos();
});

final todasLasApartadoCuotasProvider = StreamProvider<List<ApartadoCuotaModel>>((ref) {
  return ref.watch(apartadoRepositoryProvider).obtenerTodasLasCuotas();
});

/// Mapa idProducto -> cantidad apartada ACTIVA en este momento -para el
/// indicador "N apartados" en Inventario (ver InventarioScreen) y para poder
/// avisar disponibilidad real al armar un apartado nuevo-. Solo cuenta
/// líneas de apartados con estado == 'activo': uno completado ya descontó
/// stock de verdad, uno cancelado nunca reservó nada de verdad.
final cantidadesApartadasProvider = Provider<Map<String, double>>((ref) {
  final apartados = ref.watch(apartadosStreamProvider).value ?? const <ApartadoModel>[];
  final items = ref.watch(todosLosApartadoItemsProvider).value ?? const <ApartadoItemModel>[];
  final idsActivos = {for (final a in apartados) if (a.activo) a.id};
  final mapa = <String, double>{};
  for (final item in items) {
    final idProducto = item.idProducto;
    if (idProducto == null || !idsActivos.contains(item.idApartado)) continue;
    mapa[idProducto] = (mapa[idProducto] ?? 0) + item.cantidad;
  }
  return mapa;
});

/// Una fila del desglose "¿cuáles apartados tienen este producto?" (ver
/// _DialogoApartadosProducto en InventarioScreen): el apartado activo y
/// cuánto de ESE producto tiene reservado.
class ApartadoConCantidad {
  final ApartadoModel apartado;
  final double cantidad;
  ApartadoConCantidad(this.apartado, this.cantidad);
}

/// Desglose por apartado de cuánto de [idProducto] tiene reservado cada
/// apartado activo -para el diálogo que abre el badge "N apartados" de
/// Inventario-.
final apartadosActivosPorProductoProvider = Provider.family<List<ApartadoConCantidad>, String>((ref, idProducto) {
  final apartados = ref.watch(apartadosStreamProvider).value ?? const <ApartadoModel>[];
  final items = ref.watch(todosLosApartadoItemsProvider).value ?? const <ApartadoItemModel>[];
  final mapaApartados = {for (final a in apartados) a.id: a};
  final cantidadPorApartado = <String, double>{};
  for (final item in items) {
    if (item.idProducto != idProducto) continue;
    final apartado = mapaApartados[item.idApartado];
    if (apartado == null || !apartado.activo) continue;
    cantidadPorApartado[item.idApartado] = (cantidadPorApartado[item.idApartado] ?? 0) + item.cantidad;
  }
  return [
    for (final entry in cantidadPorApartado.entries)
      ApartadoConCantidad(mapaApartados[entry.key]!, entry.value),
  ];
});

/// Saldo pendiente de CADA apartado (monto_total - monto_inicial - lo ya
/// pagado, según abonos libres o cuotas pagadas) -calculado acá, en vez de
/// guardado en la tabla `apartados` (que a propósito no tiene columna de
/// saldo, ver comentario en supabase/schema.sql), para que el listado
/// (ApartadosScreen) muestre el saldo de todos sin abrir el detalle de cada
/// uno.
final saldosApartadosProvider = Provider<Map<String, double>>((ref) {
  final apartados = ref.watch(apartadosStreamProvider).value ?? const <ApartadoModel>[];
  final abonos = ref.watch(todosLosApartadoAbonosProvider).value ?? const <ApartadoAbonoModel>[];
  final cuotas = ref.watch(todasLasApartadoCuotasProvider).value ?? const <ApartadoCuotaModel>[];

  final abonadoPorApartado = <String, double>{};
  for (final a in abonos) {
    abonadoPorApartado[a.idApartado] = (abonadoPorApartado[a.idApartado] ?? 0) + a.montoAbonado;
  }
  final pagadoPorCuotasPorApartado = <String, double>{};
  for (final c in cuotas) {
    if (!c.pagada) continue;
    pagadoPorCuotasPorApartado[c.idApartado] = (pagadoPorCuotasPorApartado[c.idApartado] ?? 0) + c.montoProgramado;
  }

  final mapa = <String, double>{};
  for (final a in apartados) {
    final pagado = a.montoInicial +
        (a.esCuotasFijas ? (pagadoPorCuotasPorApartado[a.id] ?? 0) : (abonadoPorApartado[a.id] ?? 0));
    final saldo = a.montoTotal - pagado;
    mapa[a.id] = saldo < 0 ? 0 : saldo;
  }
  return mapa;
});
