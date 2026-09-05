import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';
import 'historico_venta_service.dart';

class ReporteRepository with ConRedMixin {
  final _db = Supabase.instance.client;
  final _historicoService = HistoricoVentaService();

  Future<List<ReporteVentaModel>> obtenerReporteVentas(
    DateTime inicio,
    DateTime finInclusive,
  ) {
    return conRed(() async {
      // En paralelo se pide el tramo histórico (sistema anterior, vía D1/Worker)
      // por si el rango toca fechas de antes del 2026-07-17 — ver
      // HistoricoVentaService. Nunca se dispara si el rango es todo posterior
      // al corte, así que el día a día no paga ningún costo extra.
      final filasFuture = _db
          .from('ventas')
          .select()
          .gte('fecha_registro', inicio.toIso8601String())
          .lte('fecha_registro', finInclusive.toIso8601String())
          .order('fecha_registro', ascending: false);
      final historicoFuture = _historicoService.obtenerVentas(
        inicio,
        finInclusive,
      );

      final filas = await filasFuture;
      final historico = await historicoFuture;

      final lista = [
        ...filas.map((d) => ReporteVentaModel.fromMap(d['id'] as String, d)),
        ...historico,
      ];
      // No hay 'creadoEn' propio en Postgres (ver ReporteVentaModel.fromMap):
      // se ordena directo por fechaRegistro descendente.
      lista.sort((a, b) {
        final claveA = a.creadoEn ?? a.fechaRegistro ?? DateTime(0);
        final claveB = b.creadoEn ?? b.fechaRegistro ?? DateTime(0);
        return claveB.compareTo(claveA);
      });
      return lista;
    });
  }

  /// Versión en vivo de [obtenerReporteVentas], para tarjetas de resumen
  /// (ej. venta del día/mes en Inicio) que deben actualizarse solas cuando
  /// se registra o anula una venta, sin necesidad de refrescar la pantalla.
  Stream<List<ReporteVentaModel>> observarReporteVentas(
    DateTime inicio,
    DateTime finInclusive,
  ) {
    return conRedStream(
      () => _db
          .from('ventas')
          .stream(primaryKey: ['id'])
          .order('fecha_registro', ascending: false)
          .map(
            (filas) => filas
                .where((d) {
                  final fechaTexto = d['fecha_registro'] as String?;
                  if (fechaTexto == null) return false;
                  final fecha = DateTime.parse(fechaTexto);
                  return !fecha.isBefore(inicio) &&
                      !fecha.isAfter(finInclusive);
                })
                .map((d) => ReporteVentaModel.fromMap(d['id'] as String, d))
                .toList(),
          ),
    );
  }

  Future<List<ReporteCompraModel>> obtenerReporteCompras(
    DateTime inicio,
    DateTime finInclusive, {
    String? idProveedor,
  }) {
    return conRed(() async {
      final filas = await _db
          .from('compras')
          .select()
          .gte('fecha_registro', inicio.toIso8601String())
          .lte('fecha_registro', finInclusive.toIso8601String())
          .order('fecha_registro', ascending: false);
      var lista = filas
          .map((d) => ReporteCompraModel.fromMap(d['id'] as String, d))
          .toList();
      if (idProveedor != null && idProveedor.isNotEmpty) {
        lista = lista.where((c) => c.idProveedor == idProveedor).toList();
      }
      return lista;
    });
  }
}
