import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'egreso_model.dart';
import '../../reportes/data/reporte_repository.dart';
import '../../ventas_credito/data/venta_credito_repository.dart';
import '../../compras_credito/data/compra_credito_repository.dart';

class EgresoRepository with ConRedMixin {
  final _db = Supabase.instance.client;
  final _reporteRepository = ReporteRepository();
  final _ventaCreditoRepository = VentaCreditoRepository();
  final _compraCreditoRepository = CompraCreditoRepository();

  Future<void> crear(EgresoModel egreso) {
    return conRed(() => _db.from('egresos').insert(egreso.toMap()));
  }

  Future<void> actualizar(EgresoModel egreso) {
    return conRed(() => _db.from('egresos').update(egreso.toMap()).eq('id', egreso.id));
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('egresos').delete().eq('id', id));
  }

  Future<List<EgresoModel>> obtenerEgresosPorRango(DateTime inicio, DateTime finInclusive) {
    return conRed(() async {
      final filas = await _db
          .from('egresos')
          .select()
          .gte('fecha', inicio.toIso8601String())
          .lte('fecha', finInclusive.toIso8601String())
          .order('fecha', ascending: false);
      return filas.map((d) => EgresoModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  /// Junta ventas de contado, abonos a crédito (venta y compra) y egresos
  /// manuales del rango en una sola lista de movimientos, igual que el libro
  /// financiero del sistema anterior.
  Future<List<T>> _tolerante<T>(String fuente, Future<List<T>> future) {
    return future.catchError((Object e) {
      debugPrint('Libro financiero: falló la fuente "$fuente": $e');
      return <T>[];
    });
  }

  Future<List<MovimientoFinanciero>> obtenerLibroFinanciero(DateTime inicio, DateTime finInclusive) async {
    final resultados = await Future.wait([
      _tolerante('ventas', _reporteRepository.obtenerReporteVentas(inicio, finInclusive)),
      _tolerante('compras', _reporteRepository.obtenerReporteCompras(inicio, finInclusive)),
      _tolerante('abonos venta crédito', _ventaCreditoRepository.obtenerAbonosPorRango(inicio, finInclusive)),
      _tolerante('abonos compra crédito', _compraCreditoRepository.obtenerAbonosPorRango(inicio, finInclusive)),
      _tolerante('egresos manuales', obtenerEgresosPorRango(inicio, finInclusive)),
    ]);

    final ventas = resultados[0] as List;
    final compras = resultados[1] as List;
    final abonosVenta = resultados[2] as List;
    final abonosCompra = resultados[3] as List;
    final egresos = resultados[4] as List<EgresoModel>;

    final movimientos = <MovimientoFinanciero>[];

    for (final v in ventas) {
      if (v.estado != 'Activa' || v.condicion != 'Contado' || v.tipoDocumento == 'Cotizacion') continue;
      final descripcion = 'Doc. ${v.numeroDocumento} · ${v.nombreCliente.isEmpty ? 'Consumidor final' : v.nombreCliente}';
      if (v.metodoPago == 'Mixto' && v.pagosMixtos.isNotEmpty) {
        for (final pago in v.pagosMixtos) {
          movimientos.add(MovimientoFinanciero(
            fecha: v.fechaRegistro ?? DateTime.now(),
            tipoMovimiento: 'Venta (Contado)',
            descripcion: '$descripcion (mixto)',
            ingreso: pago.monto,
            metodoPago: pago.metodoPago,
            usuario: v.usuarioRegistro,
          ));
        }
      } else {
        movimientos.add(MovimientoFinanciero(
          fecha: v.fechaRegistro ?? DateTime.now(),
          tipoMovimiento: 'Venta (Contado)',
          descripcion: descripcion,
          ingreso: v.totalAPagar,
          metodoPago: v.metodoPago,
          usuario: v.usuarioRegistro,
        ));
      }
    }

    for (final c in compras) {
      if (c.condicion == 'Credito' || !c.esActiva) continue;
      movimientos.add(MovimientoFinanciero(
        fecha: c.fechaRegistro ?? DateTime.now(),
        tipoMovimiento: 'Compra (Contado)',
        descripcion: 'Doc. ${c.numeroDocumento} · ${c.razonSocial}',
        egreso: c.montoTotal,
        metodoPago: c.metodoPago,
        usuario: c.usuarioRegistro,
      ));
    }

    for (final a in abonosVenta) {
      movimientos.add(MovimientoFinanciero(
        fecha: a.fecha ?? DateTime.now(),
        tipoMovimiento: 'Abono a Crédito',
        descripcion: 'Recibo ${a.numeroRecibo}',
        ingreso: a.montoAbonado,
        metodoPago: a.metodoPago,
        usuario: a.usuario,
      ));
    }

    for (final a in abonosCompra) {
      movimientos.add(MovimientoFinanciero(
        fecha: a.fecha ?? DateTime.now(),
        tipoMovimiento: 'Abono Compra Crédito',
        descripcion: '${a.nombreProveedor} · Recibo ${a.numeroRecibo}',
        egreso: a.montoAbonado,
        metodoPago: a.metodoPago,
        usuario: a.usuario,
      ));
    }

    for (final e in egresos) {
      movimientos.add(MovimientoFinanciero(
        fecha: e.fecha,
        tipoMovimiento: 'Egreso Manual',
        descripcion: e.descripcion,
        egreso: e.monto,
        metodoPago: e.metodoPago,
        categoria: e.categoria,
        esPagado: e.esPagado,
        fechaPago: e.fechaPago,
        usuario: e.usuario,
        idEgreso: e.id,
      ));
    }

    movimientos.sort((a, b) => b.fecha.compareTo(a.fecha));
    return movimientos;
  }
}
