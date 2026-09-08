import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';

class ReporteRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Future<List<ReporteVentaModel>> obtenerReporteVentas(
    DateTime inicio,
    DateTime finInclusive,
  ) {
    return conRed(() async {
      final filas = await _db
          .from('ventas')
          .select()
          .gte('fecha_registro', inicio.toIso8601String())
          .lte('fecha_registro', finInclusive.toIso8601String())
          .order('fecha_registro', ascending: false);

      final lista = filas
          .map((d) => ReporteVentaModel.fromMap(d['id'] as String, d))
          .toList();
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

  /// Emite un evento (sin contenido útil, solo "avisa") cada vez que cambia
  /// algo en [tabla] vía Supabase Realtime. No trae ni mapea filas -a
  /// diferencia de [observarReporteVentas]-, solo sirve para que una
  /// pantalla de Reporte ya abierta se re-dispare sola (misma consulta,
  /// mismo rango de fecha ya elegido, sin resetear ningún filtro) cuando el
  /// dueño registra/anula algo en otra pestaña mientras el reporte sigue
  /// abierto en esta -pedido explícito: "entro a ver el reporte y la venta
  /// que acabo de hacer no aparece hasta que lo busco de nuevo a mano"-.
  ///
  /// Escucha directo los eventos de Postgres Changes (INSERT/UPDATE/DELETE)
  /// -a propósito, NO usa `.from(tabla).stream()`-: ese `.stream()` mantiene
  /// una copia completa de la tabla y la re-emite entera no solo cuando algo
  /// cambia sino también cada vez que el canal de Realtime se reconecta (un
  /// blip de red, la pestaña quedó en segundo plano, etc. -algo que puede
  /// pasar sin que el dueño toque nada-), y esa re-emisión de reconexión
  /// llega al código de arriba indistinguible de un cambio real, disparando
  /// una recarga espontánea del reporte. Con Postgres Changes puro, una
  /// reconexión no emite nada por sí sola -solo un INSERT/UPDATE/DELETE de
  /// verdad dispara [callback]-, así que ya no hace falta descartar "el
  /// primer evento" a mano en la pantalla.
  Stream<void> observarCambiosEnTabla(String tabla) {
    return conRedStream(() => _streamCambiosPostgres(tabla));
  }

  Stream<void> _streamCambiosPostgres(String tabla) {
    RealtimeChannel? canal;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        canal = _db.channel('reporte_cambios_$tabla')
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: tabla,
            callback: (payload) {
              if (!controller.isClosed) controller.add(null);
            },
          )
          ..subscribe((status, [error]) {
            if (controller.isClosed) return;
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              controller.addError(
                error ?? Exception('No se pudo suscribir a cambios de $tabla'),
              );
            }
          });
      },
      onCancel: () => canal?.unsubscribe(),
    );
    return controller.stream;
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
