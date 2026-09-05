import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'compra_en_espera_model.dart';
import 'compra_model.dart';
import 'item_compra_model.dart';

class CompraRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  // ---------- Compras en espera (borrador autoguardado) ----------

  Stream<List<CompraEnEsperaModel>> obtenerComprasEnEspera() {
    return conRedStream(() => _db
        .from('compras_en_espera')
        .stream(primaryKey: ['id'])
        .order('fecha', ascending: false)
        .map((filas) => filas.map((d) => CompraEnEsperaModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<String> guardarCompraEnEspera(CompraEnEsperaModel sesion) {
    return conRed(() async {
      final fila = await _db.from('compras_en_espera').insert(sesion.toMap()).select('id').single();
      return fila['id'] as String;
    });
  }

  Future<void> actualizarCompraEnEspera(String id, CompraEnEsperaModel sesion) {
    return conRed(() => _db.from('compras_en_espera').update(sesion.toMap()).eq('id', id));
  }

  Future<void> eliminarCompraEnEspera(String id) {
    return conRed(() => _db.from('compras_en_espera').delete().eq('id', id));
  }

  String _formatearCorrelativo(int numero) => numero.toString().padLeft(8, '0');

  /// Registra una compra completa — ver `registrar_compra` en
  /// supabase/schema.sql: hace atómicamente lo que en Firestore era una
  /// Transaction (contador, detalle, stock, lotes de costo, historial,
  /// emparejamiento con ventas anticipadas).
  Future<CompraModel> registrarCompra({
    required String noFactura,
    required String idProveedor,
    required String documentoProveedor,
    required String razonSocial,
    required String condicion,
    required String metodoPago,
    required DateTime fechaRegistro,
    required DateTime? fechaVencimiento,
    double descuentoGlobalPorcentaje = 0,
    double descuentoTotalMonto = 0,
    double isvPorcentaje = 15,
    double ajusteManual = 0,
    required List<ItemCompraModel> items,
    required double subtotal,
    required double impuesto,
    required double totalAPagar,
    required String usuario,
  }) {
    return conRed(() async {
      final resultado = await _db.rpc('registrar_compra', params: {
        'payload': {
          'noFactura': noFactura,
          'idProveedor': idProveedor.isEmpty ? null : idProveedor,
          'documentoProveedor': documentoProveedor,
          'razonSocial': razonSocial,
          'condicion': condicion,
          'metodoPago': metodoPago,
          'fechaRegistro': fechaRegistro.toIso8601String(),
          'fechaVencimiento': fechaVencimiento?.toIso8601String(),
          'descuentoGlobalPorcentaje': descuentoGlobalPorcentaje,
          'descuentoTotalMonto': descuentoTotalMonto,
          'isvPorcentaje': isvPorcentaje,
          'ajusteManual': ajusteManual,
          'subtotal': subtotal,
          'impuesto': impuesto,
          'totalAPagar': totalAPagar,
          'usuario': usuario,
          'items': items.map((i) => i.toMap()).toList(),
        },
      }) as Map<String, dynamic>;

      return CompraModel(
        id: resultado['id'] as String,
        tipoDocumento: 'Factura',
        numeroDocumento: resultado['numeroDocumento'] as String,
        noFactura: noFactura,
        idProveedor: idProveedor,
        documentoProveedor: documentoProveedor,
        razonSocial: razonSocial,
        condicion: condicion,
        metodoPago: metodoPago,
        subtotal: subtotal,
        descuentoGlobalPorcentaje: descuentoGlobalPorcentaje,
        descuentoTotalMonto: descuentoTotalMonto,
        isvPorcentaje: isvPorcentaje,
        impuesto: impuesto,
        ajusteManual: ajusteManual,
        totalAPagar: totalAPagar,
        fechaRegistro: fechaRegistro,
        fechaVencimiento: fechaVencimiento,
        estado: 'Activa',
        usuarioRegistro: usuario,
        cantidadProductos: items.fold<double>(0, (s, i) => s + i.cantidad),
        detalle: items,
      );
    });
  }

  Future<CompraModel?> obtenerCompraPorId(String id) {
    return conRed(() async {
      final filas = await _db.from('compras').select().eq('id', id).limit(1);
      if (filas.isEmpty) return null;
      final detalleFilas = await _db.from('compra_items').select().eq('id_compra', id).order('orden');
      final items = detalleFilas.map((d) => ItemCompraModel.fromRow(d)).toList();
      return CompraModel.fromMap(id, filas.first, items);
    });
  }

  /// Busca por número de documento (correlativo interno) o por número de
  /// factura (el que trae la factura física del proveedor).
  Future<CompraModel?> obtenerCompraPorNumeroDocumento(String numeroDocumento) {
    return conRed(() async {
      final texto = numeroDocumento.trim();
      if (texto.isEmpty) return null;

      final soloDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
      Map<String, dynamic>? fila;

      if (soloDigitos.isNotEmpty) {
        final sinCeros = soloDigitos.replaceFirst(RegExp(r'^0+'), '');
        final correlativo = _formatearCorrelativo(int.parse(sinCeros.isEmpty ? '0' : sinCeros));
        final porDocumento = await _db.from('compras').select().eq('numero_documento', correlativo).limit(1);
        if (porDocumento.isNotEmpty) fila = porDocumento.first;
      }

      if (fila == null) {
        final porFactura = await _db.from('compras').select().eq('no_factura', texto).limit(1);
        if (porFactura.isNotEmpty) fila = porFactura.first;
      }

      if (fila == null) return null;
      final detalleFilas = await _db.from('compra_items').select().eq('id_compra', fila['id']).order('orden');
      final items = detalleFilas.map((d) => ItemCompraModel.fromRow(d)).toList();
      return CompraModel.fromMap(fila['id'] as String, fila, items);
    });
  }

  /// Anula una compra: la marca como 'Anulada', descuenta el inventario que
  /// había sumado — ver `anular_compra` en supabase/schema.sql.
  Future<void> anularCompra({
    required String id,
    required String usuario,
    String motivo = '',
  }) {
    return conRed(() async {
      try {
        await _db.rpc('anular_compra', params: {'p_id': id, 'p_usuario': usuario, 'p_motivo': motivo});
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    });
  }
}
