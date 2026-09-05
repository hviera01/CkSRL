import 'item_compra_model.dart';

class CompraModel {
  final String id;
  final String tipoDocumento;
  final String numeroDocumento;
  final String noFactura;
  final String idProveedor;
  final String documentoProveedor;
  final String razonSocial;
  final String condicion;
  final String metodoPago;
  final double subtotal;
  final double descuentoGlobalPorcentaje;
  final double descuentoTotalMonto;
  final double isvPorcentaje;
  final double impuesto;
  final double ajusteManual;
  final double totalAPagar;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final String estado;
  final String usuarioRegistro;
  final double cantidadProductos;
  final List<ItemCompraModel> detalle;
  final String usuarioAnulacion;
  final String motivoAnulacion;
  final DateTime? fechaAnulacion;

  bool get estaAnulada => estado == 'Anulada';

  CompraModel({
    required this.id,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.noFactura,
    required this.idProveedor,
    required this.documentoProveedor,
    required this.razonSocial,
    required this.condicion,
    required this.metodoPago,
    required this.subtotal,
    this.descuentoGlobalPorcentaje = 0,
    this.descuentoTotalMonto = 0,
    this.isvPorcentaje = 15,
    required this.impuesto,
    this.ajusteManual = 0,
    required this.totalAPagar,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    required this.estado,
    required this.usuarioRegistro,
    required this.cantidadProductos,
    required this.detalle,
    this.usuarioAnulacion = '',
    this.motivoAnulacion = '',
    this.fechaAnulacion,
  });

  factory CompraModel.fromMap(String id, Map<String, dynamic> data, List<ItemCompraModel> detalle) {
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return CompraModel(
      id: id,
      tipoDocumento: data['tipo_documento'] ?? 'Factura',
      numeroDocumento: data['numero_documento'] ?? '',
      noFactura: data['no_factura'] ?? '',
      idProveedor: data['id_proveedor'] ?? '',
      documentoProveedor: data['documento_proveedor'] ?? '',
      razonSocial: data['razon_social'] ?? '',
      condicion: data['condicion'] ?? '',
      metodoPago: data['metodo_pago'] ?? '',
      subtotal: (data['subtotal'] ?? 0).toDouble(),
      descuentoGlobalPorcentaje: (data['descuento_global_porcentaje'] ?? 0).toDouble(),
      descuentoTotalMonto: (data['descuento_total_monto'] ?? 0).toDouble(),
      isvPorcentaje: (data['isv_porcentaje'] ?? 15).toDouble(),
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      ajusteManual: (data['ajuste_manual'] ?? 0).toDouble(),
      totalAPagar: (data['total_a_pagar'] ?? 0).toDouble(),
      fechaRegistro: fecha(data['fecha_registro'] as String?),
      fechaVencimiento: fecha(data['fecha_vencimiento'] as String?),
      estado: data['estado'] ?? 'Activa',
      usuarioRegistro: data['usuario_registro'] ?? '',
      cantidadProductos: (data['cantidad_productos'] ?? 0).toDouble(),
      detalle: detalle,
      usuarioAnulacion: data['usuario_anulacion'] ?? '',
      motivoAnulacion: data['motivo_anulacion'] ?? '',
      fechaAnulacion: fecha(data['fecha_anulacion'] as String?),
    );
  }
}
