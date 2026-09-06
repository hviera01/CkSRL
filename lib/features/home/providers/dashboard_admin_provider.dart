import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reportes/providers/reportes_provider.dart';
import '../../apartados/providers/apartados_provider.dart';
import '../../apartados/data/apartado_model.dart';

/// Un punto del mini-gráfico "últimos 7 días" del dashboard del
/// Administrador: día corto (L, M, X...) + total vendido ese día.
class SerieDiaVenta {
  final String etiqueta;
  final double total;
  const SerieDiaVenta(this.etiqueta, this.total);
}

/// Datos ya calculados para el dashboard de Inicio que solo ve el
/// Administrador (ver DashboardAdmin) -pedido explícito del dueño: "ventas de
/// la semana" + un par de métricas más para un vistazo rápido al abrir el
/// sistema-.
class DashboardAdminData {
  final double totalSemana;
  final int cantidadVentasSemana;
  final double ticketPromedioSemana;
  final double saldoApartadosActivos;
  final List<SerieDiaVenta> serieUltimos7Dias;

  const DashboardAdminData({
    required this.totalSemana,
    required this.cantidadVentasSemana,
    required this.ticketPromedioSemana,
    required this.saldoApartadosActivos,
    required this.serieUltimos7Dias,
  });
}

const _diasCorto = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Saldo pendiente (monto_total - lo ya pagado) de TODOS los apartados con
/// estado 'activo' en este momento -reusa el mismo cálculo por-apartado que
/// ya usa ApartadosScreen (ver saldosApartadosProvider en
/// apartados/providers/apartados_provider.dart), acá solo se suma en vez de
/// mostrarse fila por fila-. No dispara ninguna consulta nueva: ambos
/// streams (apartados, abonos) ya están vivos apenas se abre esta pantalla o
/// la de Apartados.
final saldoApartadosActivosProvider = Provider<double>((ref) {
  final apartados = ref.watch(apartadosStreamProvider).value ?? const <ApartadoModel>[];
  final saldos = ref.watch(saldosApartadosProvider);
  return apartados.where((a) => a.activo).fold<double>(0, (s, a) => s + (saldos[a.id] ?? 0));
});

/// Solo la parte que depende del stream de ventas (separada de
/// [saldoApartadosActivosProvider] para no tener que re-suscribirse a
/// `observarReporteVentas` cada vez que cambia un apartado, que no tiene
/// nada que ver).
final _resumenVentasSemanaProvider = StreamProvider.autoDispose<DashboardAdminData>((ref) {
  final ahora = DateTime.now();
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final finHoy = DateTime(ahora.year, ahora.month, ahora.day, 23, 59, 59, 999);
  // Lunes de esta semana (DateTime.weekday: 1=lunes .. 7=domingo).
  final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));
  final hace6Dias = hoy.subtract(const Duration(days: 6));
  // Una sola consulta que cubre lo que haga falta para ambos cálculos (semana
  // calendario + últimos 7 días corridos), lo que sea más amplio.
  final inicioConsulta = inicioSemana.isBefore(hace6Dias) ? inicioSemana : hace6Dias;

  return ref.watch(reporteRepositoryProvider).observarReporteVentas(inicioConsulta, finHoy).map((lista) {
    final ventasValidas = lista.where((v) => v.esActiva && !v.esCotizacion).toList();

    final ventasSemana = ventasValidas.where((v) {
      final f = v.fechaRegistro;
      return f != null && !f.isBefore(inicioSemana);
    }).toList();
    final totalSemana = ventasSemana.fold<double>(0, (s, v) => s + v.totalAPagar);
    final cantidadVentasSemana = ventasSemana.length;
    final ticketPromedioSemana = cantidadVentasSemana == 0 ? 0.0 : totalSemana / cantidadVentasSemana;

    final serie = <SerieDiaVenta>[
      for (var i = 6; i >= 0; i--)
        () {
          final dia = hoy.subtract(Duration(days: i));
          final finDia = DateTime(dia.year, dia.month, dia.day, 23, 59, 59, 999);
          final totalDia = ventasValidas.where((v) {
            final f = v.fechaRegistro;
            return f != null && !f.isBefore(dia) && !f.isAfter(finDia);
          }).fold<double>(0, (s, v) => s + v.totalAPagar);
          return SerieDiaVenta(_diasCorto[dia.weekday - 1], totalDia);
        }(),
    ];

    return DashboardAdminData(
      totalSemana: totalSemana,
      cantidadVentasSemana: cantidadVentasSemana,
      ticketPromedioSemana: ticketPromedioSemana,
      // Se completa más abajo, en dashboardAdminHomeProvider: acá va 0 de
      // relleno para no acoplar este stream al de apartados.
      saldoApartadosActivos: 0,
      serieUltimos7Dias: serie,
    );
  });
});

/// Provider final que arma la pantalla: combina el resumen de ventas de la
/// semana (stream, se recalcula solo al registrar/anular una venta) con el
/// saldo pendiente de apartados activos (sync, ya vivo en memoria).
final dashboardAdminHomeProvider = Provider.autoDispose<AsyncValue<DashboardAdminData>>((ref) {
  final resumenVentas = ref.watch(_resumenVentasSemanaProvider);
  final saldoApartados = ref.watch(saldoApartadosActivosProvider);
  return resumenVentas.whenData(
    (d) => DashboardAdminData(
      totalSemana: d.totalSemana,
      cantidadVentasSemana: d.cantidadVentasSemana,
      ticketPromedioSemana: d.ticketPromedioSemana,
      saldoApartadosActivos: saldoApartados,
      serieUltimos7Dias: d.serieUltimos7Dias,
    ),
  );
});
