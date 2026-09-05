import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'venta_credito_model.dart';
import 'abono_model.dart';
import 'venta_credito_import_service.dart';
import '../../../core/utils/formato_moneda.dart';

class VentaCreditoRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  String _generarNumeroDocumento() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return ahora.substring(ahora.length - 8);
  }

  Stream<List<VentaCreditoModel>> obtenerCreditos() {
    return conRedStream(() => _db
        .from('ventas_credito')
        .stream(primaryKey: ['id'])
        .order('fecha_registro', ascending: false)
        .map((filas) => filas.map((d) => VentaCreditoModel.fromMap(d['id'] as String, d)).toList()));
  }

  /// El registro de `ventas_credito` de una venta a crédito se crea con el
  /// mismo id que la venta (ver `registrar_venta` en supabase/schema.sql).
  Future<VentaCreditoModel?> obtenerPorId(String id) {
    return conRed(() async {
      final filas = await _db.from('ventas_credito').select().eq('id', id).limit(1);
      if (filas.isEmpty) return null;
      return VentaCreditoModel.fromMap(filas.first['id'] as String, filas.first);
    });
  }

  Stream<List<AbonoModel>> obtenerAbonos(String idCredito) {
    return conRedStream(() => _db
        .from('venta_credito_abonos')
        .stream(primaryKey: ['id'])
        .eq('id_venta_credito', idCredito)
        .order('fecha', ascending: false)
        .map((filas) => filas.map((d) => AbonoModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<List<AbonoModel>> obtenerAbonosUnaVez(String idCredito) {
    return conRed(() async {
      final filas = await _db.from('venta_credito_abonos').select().eq('id_venta_credito', idCredito);
      return filas.map((d) => AbonoModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  /// Créditos de un cliente vinculado. Prioriza [idCliente]; si no hay, cae
  /// a [documentoCliente].
  Future<List<VentaCreditoModel>> obtenerCreditosDeCliente({String? idCliente, String? documentoCliente}) {
    return conRed(() async {
      List<Map<String, dynamic>> filas;
      if (idCliente != null && idCliente.isNotEmpty) {
        filas = await _db.from('ventas_credito').select().eq('id_cliente', idCliente);
      } else if (documentoCliente != null && documentoCliente.trim().isNotEmpty && documentoCliente.trim() != 'N/A') {
        filas = await _db.from('ventas_credito').select().eq('documento_cliente', documentoCliente.trim());
      } else {
        return <VentaCreditoModel>[];
      }
      return filas.map((d) => VentaCreditoModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  Future<void> crearCreditoManual({
    required String documentoCliente,
    required String nombreCliente,
    String? idCliente,
    required String numeroDocumento,
    required double montoTotal,
    required double saldoPendiente,
    required DateTime fechaVencimiento,
    String telefono = '',
  }) {
    return conRed(() => _db.from('ventas_credito').insert({
          'documento_cliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
          'nombre_cliente': nombreCliente,
          'id_cliente': (idCliente == null || idCliente.isEmpty) ? null : idCliente,
          'numero_documento': numeroDocumento.isEmpty ? _generarNumeroDocumento() : numeroDocumento,
          'monto_total': redondearMoneda(montoTotal),
          'saldo_pendiente': redondearMoneda(saldoPendiente),
          'fecha_vencimiento': fechaVencimiento.toIso8601String(),
          'sin_venta_origen': true,
          'telefono': telefono.trim(),
        }));
  }

  /// Cambia (o agrega) el teléfono de contacto de ESTE crédito puntual, sin
  /// tocar el registro de 'clientes'.
  Future<void> actualizarTelefono(String id, String telefono) {
    return conRed(() => _db.from('ventas_credito').update({'telefono': telefono.trim()}).eq('id', id));
  }

  /// Pide que se mande YA el aviso de WhatsApp de crédito vencido — el envío
  /// real lo hace el script Node aparte, acá solo se marca el pedido.
  Future<void> solicitarAvisoWhatsApp(String idCredito) {
    return conRed(() => _db.from('ventas_credito').update({
          'solicitud_aviso_whatsapp': true,
          'error_aviso_whatsapp': null,
        }).eq('id', idCredito));
  }

  Future<void> registrarAbono({
    required String idCredito,
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
        throw Exception('El abono (${formatearMoneda(montoAbonado)}) supera el saldo disponible en este crédito (${formatearMoneda(saldoAnterior + interes)})');
      }
      await _db.rpc('registrar_abono_venta_credito', params: {
        'payload': {
          'idCredito': idCredito,
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

  Future<void> eliminarAbono({required String idCredito, required String idAbono, required double montoTotal}) {
    return conRed(() => _db.rpc('eliminar_abono_venta_credito', params: {
          'p_id_credito': idCredito,
          'p_id_abono': idAbono,
          'p_monto_total': montoTotal,
        }));
  }

  Future<void> editarAbono({
    required String idCredito,
    required String idAbono,
    required double montoTotal,
    required double montoAbonado,
    required double interes,
    required DateTime fecha,
    required String metodoPago,
    required String numeroRecibo,
  }) {
    return conRed(() => _db.rpc('editar_abono_venta_credito', params: {
          'payload': {
            'idCredito': idCredito,
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

  Future<void> unirFacturas({
    required List<VentaCreditoModel> facturas,
    required String documentoCliente,
    required String nombreCliente,
    required DateTime fechaVencimiento,
  }) {
    return conRed(() async {
      final total = redondearMoneda(facturas.fold<double>(0, (s, f) => s + f.saldoPendiente));
      for (final factura in facturas) {
        await _db.from('ventas_credito').update({'saldo_pendiente': 0, 'fusionada': true}).eq('id', factura.id);
      }
      // Si una de las facturas que se está uniendo ya era, a su vez, el
      // resultado de una unión anterior, se guardan sus facturas de origen
      // reales en vez de su propio id.
      final facturasOrigenPlanas = <FacturaOrigenModel>[
        for (final factura in facturas)
          if (factura.esFusion)
            ...factura.facturasOrigen
          else
            FacturaOrigenModel(id: factura.id, numeroDocumento: factura.numeroDocumento, saldoPendiente: factura.saldoPendiente),
      ];
      await _db.from('ventas_credito').insert({
        'documento_cliente': documentoCliente.isEmpty ? 'N/A' : documentoCliente,
        'nombre_cliente': nombreCliente,
        'numero_documento': _generarNumeroDocumento(),
        'monto_total': total,
        'saldo_pendiente': total,
        'fecha_vencimiento': fechaVencimiento.toIso8601String(),
        'sin_venta_origen': true,
        'facturas_origen': facturasOrigenPlanas.map((f) => f.toMap()).toList(),
      });
    });
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('ventas_credito').delete().eq('id', id));
  }

  /// Crea en lote los créditos de venta de una importación desde Excel.
  Future<int> importarCreditos(List<FilaImportacionVentaCredito> filas) {
    return conRed(() async {
      final validas = filas.where((f) => f.valido).toList();
      if (validas.isEmpty) return 0;
      final filasInsertar = validas.map((fila) => {
            'documento_cliente': fila.documentoCliente.isEmpty ? 'N/A' : fila.documentoCliente,
            'nombre_cliente': fila.nombreCliente,
            'numero_documento': fila.numeroDocumento.isEmpty ? fila.numeroFila.toString() : fila.numeroDocumento,
            'monto_total': fila.montoTotal,
            'saldo_pendiente': fila.saldoPendiente,
            'fecha_registro': fila.fechaRegistro?.toIso8601String(),
            'fecha_vencimiento': fila.fechaVencimiento.toIso8601String(),
            'sin_venta_origen': true,
          }).toList();
      await _db.from('ventas_credito').insert(filasInsertar);
      return validas.length;
    });
  }

  Future<List<AbonoModel>> obtenerAbonosPorRango(DateTime inicio, DateTime finInclusive) {
    return conRed(() async {
      final filas = await _db
          .from('venta_credito_abonos')
          .select()
          .gte('fecha', inicio.toIso8601String())
          .lte('fecha', finInclusive.toIso8601String());
      return filas.map((d) => AbonoModel.fromMap(d['id'] as String, d)).toList();
    });
  }
}
