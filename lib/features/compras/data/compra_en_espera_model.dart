import 'item_compra_model.dart';

class CompraEnEsperaModel {
  final String id;
  final DateTime? fecha;
  final String idProveedor;
  final String documentoProveedor;
  final String razonSocial;
  final String noFactura;
  final String condicion;
  final String metodoPago;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final double descuentoGlobalPorcentaje;
  final double isvPorcentaje;
  final double ajusteManual;
  final List<ItemCompraModel> items;

  CompraEnEsperaModel({
    required this.id,
    required this.fecha,
    required this.idProveedor,
    required this.documentoProveedor,
    required this.razonSocial,
    required this.noFactura,
    required this.condicion,
    required this.metodoPago,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    this.descuentoGlobalPorcentaje = 0,
    this.isvPorcentaje = 15,
    this.ajusteManual = 0,
    required this.items,
  });

  double get total => items.fold<double>(0, (s, i) => s + i.subtotal);

  factory CompraEnEsperaModel.fromMap(String id, Map<String, dynamic> data) {
    final itemsRaw = (data['items'] as List<dynamic>? ?? []);
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return CompraEnEsperaModel(
      id: id,
      fecha: fecha(data['fecha'] as String?),
      idProveedor: data['id_proveedor'] ?? '',
      documentoProveedor: data['documento_proveedor'] ?? '',
      razonSocial: data['razon_social'] ?? '',
      noFactura: data['no_factura'] ?? '',
      condicion: data['condicion'] ?? 'Contado',
      metodoPago: data['metodo_pago'] ?? 'Efectivo',
      fechaRegistro: fecha(data['fecha_registro'] as String?),
      fechaVencimiento: fecha(data['fecha_vencimiento'] as String?),
      descuentoGlobalPorcentaje: (data['descuento_global_porcentaje'] ?? 0).toDouble(),
      isvPorcentaje: (data['isv_porcentaje'] ?? 15).toDouble(),
      ajusteManual: (data['ajuste_manual'] ?? 0).toDouble(),
      items: itemsRaw.map((e) => ItemCompraModel.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fecha': DateTime.now().toIso8601String(),
      'id_proveedor': idProveedor.isEmpty ? null : idProveedor,
      'documento_proveedor': documentoProveedor,
      'razon_social': razonSocial,
      'no_factura': noFactura,
      'condicion': condicion,
      'metodo_pago': metodoPago,
      'fecha_registro': fechaRegistro?.toIso8601String(),
      'fecha_vencimiento': fechaVencimiento?.toIso8601String(),
      'descuento_global_porcentaje': descuentoGlobalPorcentaje,
      'isv_porcentaje': isvPorcentaje,
      'ajuste_manual': ajusteManual,
      'items': items.map((i) => i.toMap()).toList(),
    };
  }
}
