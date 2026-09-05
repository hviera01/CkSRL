import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'compra_credito_model.dart';
import 'abono_compra_model.dart';
import 'compra_credito_import_service.dart';
import '../../../core/utils/formato_moneda.dart';

class DistribucionAbono {
  final CompraCreditoModel compra;
  final double montoAplicado;
  final double saldoResultante;

  DistribucionAbono({required this.compra, required this.montoAplicado, required this.saldoResultante});
}

class ResumenImportacionComprasCredito {
  final int creados;
  final int proveedoresCreados;

  ResumenImportacionComprasCredito({required this.creados, required this.proveedoresCreados});
}

class CompraCreditoRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  String _generarNumeroDocumento() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return ahora.substring(ahora.length - 8);
  }

  Stream<List<CompraCreditoModel>> obtenerCompras() {
    return conRedStream(() => _db
        .from('compras_credito')
        .stream(primaryKey: ['id'])
        .order('fecha_registro', ascending: false)
        .map((filas) => filas.map((d) => CompraCreditoModel.fromMap(d['id'] as String, d)).toList()));
  }

  Stream<List<AbonoCompraModel>> obtenerAbonos(String idCompra) {
    return conRedStream(() => _db
        .from('compra_credito_abonos')
        .stream(primaryKey: ['id'])
        .eq('id_compra_credito', idCompra)
        .order('fecha', ascending: false)
        .map((filas) => filas.map((d) => AbonoCompraModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<void> crearCreditoManual({
    required String idProveedor,
    required String documentoProveedor,
    required String nombreProveedor,
    required String numeroDocumento,
    required String noFactura,
    required double montoTotal,
    required double saldoPendiente,
    required DateTime fechaVencimiento,
  }) {
    return conRed(() => _db.from('compras_credito').insert({
          'id_proveedor': idProveedor.isEmpty ? null : idProveedor,
          'documento_proveedor': documentoProveedor.isEmpty ? 'N/A' : documentoProveedor,
          'nombre_proveedor': nombreProveedor,
          'numero_documento': numeroDocumento.isEmpty ? _generarNumeroDocumento() : numeroDocumento,
          'no_factura': noFactura,
          'monto_total': redondearMoneda(montoTotal),
          'saldo_pendiente': redondearMoneda(saldoPendiente),
          'fecha_vencimiento': fechaVencimiento.toIso8601String(),
          'manual': true,
        }));
  }

  Future<void> registrarAbono({
    required String idCompra,
    required String idProveedor,
    required String nombreProveedor,
    required double saldoAnterior,
    required double montoAbonado,
    required double interes,
    required String metodoPago,
    required String numeroRecibo,
    required String usuario,
    required DateTime fecha,
  }) {
    return conRed(() async {
      if (montoAbonado > saldoAnterior + interes + 0.01) {
        throw Exception('El abono (${formatearMoneda(montoAbonado)}) supera el saldo disponible en esa factura (${formatearMoneda(saldoAnterior + interes)})');
      }
      await _db.rpc('registrar_abono_compra_credito', params: {
        'payload': {
          'idCompra': idCompra,
          'idProveedor': idProveedor.isEmpty ? null : idProveedor,
          'nombreProveedor': nombreProveedor,
          'saldoAnterior': saldoAnterior,
          'montoAbonado': montoAbonado,
          'interes': interes,
          'metodoPago': metodoPago,
          'numeroRecibo': numeroRecibo,
          'usuario': usuario,
          'fecha': fecha.toIso8601String(),
        },
      });
    });
  }

  Future<void> eliminarAbono({required String idCompra, required String idAbono, required double montoTotal}) {
    return conRed(() => _db.rpc('eliminar_abono_compra_credito', params: {
          'p_id_compra': idCompra,
          'p_id_abono': idAbono,
          'p_monto_total': montoTotal,
        }));
  }

  Future<void> editarAbono({
    required String idCompra,
    required String idAbono,
    required double montoTotal,
    required double montoAbonado,
    required double interes,
    required DateTime fecha,
    required String metodoPago,
    required String numeroRecibo,
  }) {
    return conRed(() => _db.rpc('editar_abono_compra_credito', params: {
          'payload': {
            'idCompra': idCompra,
            'idAbono': idAbono,
            'montoTotal': montoTotal,
            'montoAbonado': montoAbonado,
            'interes': interes,
            'fecha': fecha.toIso8601String(),
            'metodoPago': metodoPago,
            'numeroRecibo': numeroRecibo,
          },
        }));
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('compras_credito').delete().eq('id', id));
  }

  Future<List<CompraCreditoModel>> obtenerComprasPorProveedor(String idProveedor) {
    return conRed(() async {
      final filas = await _db.from('compras_credito').select().eq('id_proveedor', idProveedor);
      return filas.map((d) => CompraCreditoModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  Future<List<AbonoCompraModel>> obtenerAbonosPorProveedor(String idProveedor) {
    return conRed(() async {
      final filas = await _db.from('compra_credito_abonos').select().eq('id_proveedor', idProveedor);
      return filas.map((d) => AbonoCompraModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  /// Crea en lote los créditos de compra de una importación desde Excel. Los
  /// proveedores que no existan todavía por nombre se crean automáticamente.
  Future<ResumenImportacionComprasCredito> importarCreditos(List<FilaImportacionCompraCredito> filas) {
    return conRed(() async {
      final proveedoresExistentes = await _db.from('proveedores').select('id, razon_social, rtn');
      final idProveedorPorNombre = <String, String>{};
      final rtnPorId = <String, String>{};
      for (final d in proveedoresExistentes) {
        final nombre = (d['razon_social'] as String? ?? '').trim().toLowerCase();
        if (nombre.isNotEmpty) idProveedorPorNombre[nombre] = d['id'] as String;
        rtnPorId[d['id'] as String] = (d['rtn'] as String? ?? '');
      }

      var creados = 0, proveedoresCreados = 0;
      final proveedoresNuevos = <String, Map<String, dynamic>>{};

      for (final fila in filas.where((f) => f.valido)) {
        final nombreNorm = fila.nombreProveedor.trim().toLowerCase();
        if (idProveedorPorNombre[nombreNorm] == null && !proveedoresNuevos.containsKey(nombreNorm)) {
          proveedoresNuevos[nombreNorm] = {'rtn': '', 'razon_social': fila.nombreProveedor.trim(), 'correo': '', 'telefono': '', 'estado': true};
        }
      }

      if (proveedoresNuevos.isNotEmpty) {
        final insertados = await _db.from('proveedores').insert(proveedoresNuevos.values.toList()).select('id, razon_social');
        for (final p in insertados) {
          idProveedorPorNombre[(p['razon_social'] as String).trim().toLowerCase()] = p['id'] as String;
          rtnPorId[p['id'] as String] = '';
        }
        proveedoresCreados = insertados.length;
      }

      final filasInsertar = <Map<String, dynamic>>[];
      for (final fila in filas.where((f) => f.valido)) {
        final idProveedor = idProveedorPorNombre[fila.nombreProveedor.trim().toLowerCase()];
        filasInsertar.add({
          'id_proveedor': idProveedor,
          'documento_proveedor': (idProveedor != null && (rtnPorId[idProveedor]?.isNotEmpty ?? false)) ? rtnPorId[idProveedor] : 'N/A',
          'nombre_proveedor': fila.nombreProveedor,
          'numero_documento': fila.numeroDocumento.isEmpty ? fila.numeroFila.toString() : fila.numeroDocumento,
          'no_factura': fila.noFactura,
          'monto_total': fila.montoTotal,
          'saldo_pendiente': fila.saldoPendiente,
          'fecha_registro': fila.fechaRegistro?.toIso8601String(),
          'fecha_vencimiento': fila.fechaVencimiento.toIso8601String(),
          'manual': true,
        });
        creados++;
      }
      if (filasInsertar.isNotEmpty) await _db.from('compras_credito').insert(filasInsertar);

      return ResumenImportacionComprasCredito(creados: creados, proveedoresCreados: proveedoresCreados);
    });
  }

  /// Calcula cómo se repartiría [monto] entre las facturas pendientes de un
  /// proveedor, pagando primero las que vencen antes. No escribe nada todavía.
  List<DistribucionAbono> calcularDistribucion(List<CompraCreditoModel> comprasProveedor, double monto) {
    final pendientes = comprasProveedor.where((c) => !c.liquidada).toList()
      ..sort((a, b) {
        if (a.fechaVencimiento == null && b.fechaVencimiento == null) return 0;
        if (a.fechaVencimiento == null) return 1;
        if (b.fechaVencimiento == null) return -1;
        return a.fechaVencimiento!.compareTo(b.fechaVencimiento!);
      });

    var restante = redondearMoneda(monto);
    final resultado = <DistribucionAbono>[];
    for (final compra in pendientes) {
      if (restante <= 0) break;
      final aplicado = restante >= compra.saldoPendiente ? compra.saldoPendiente : restante;
      resultado.add(DistribucionAbono(compra: compra, montoAplicado: aplicado, saldoResultante: redondearMoneda(compra.saldoPendiente - aplicado)));
      restante = redondearMoneda(restante - aplicado);
    }
    return resultado;
  }

  Future<void> registrarAbonoGeneral({
    required List<DistribucionAbono> distribucion,
    required String metodoPago,
    required String usuario,
    required DateTime fecha,
  }) {
    return conRed(() async {
      for (final item in distribucion) {
        if (item.montoAplicado > item.compra.saldoPendiente + 0.01) {
          throw Exception('El monto asignado a la factura ${item.compra.noFactura} supera su saldo pendiente');
        }
      }
      await _db.rpc('registrar_abono_general_compra_credito', params: {
        'payload': {
          'metodoPago': metodoPago,
          'usuario': usuario,
          'fecha': fecha.toIso8601String(),
          'distribucion': distribucion
              .map((item) => {
                    'idCompra': item.compra.id,
                    'idProveedor': item.compra.idProveedor.isEmpty ? null : item.compra.idProveedor,
                    'nombreProveedor': item.compra.nombreProveedor,
                    'montoAplicado': item.montoAplicado,
                  })
              .toList(),
        },
      });
    });
  }

  Future<List<AbonoCompraModel>> obtenerAbonosPorRango(DateTime inicio, DateTime finInclusive) {
    return conRed(() async {
      final filas = await _db
          .from('compra_credito_abonos')
          .select()
          .gte('fecha', inicio.toIso8601String())
          .lte('fecha', finInclusive.toIso8601String());
      return filas.map((d) => AbonoCompraModel.fromMap(d['id'] as String, d)).toList();
    });
  }
}
