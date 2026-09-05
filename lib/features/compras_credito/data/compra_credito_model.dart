class CompraCreditoModel {
  final String id;
  final String idProveedor;
  final String documentoProveedor;
  final String nombreProveedor;
  final String numeroDocumento;
  final String noFactura;
  final double montoTotal;
  final double saldoPendiente;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final bool manual;

  CompraCreditoModel({
    required this.id,
    required this.idProveedor,
    required this.documentoProveedor,
    required this.nombreProveedor,
    required this.numeroDocumento,
    required this.noFactura,
    required this.montoTotal,
    required this.saldoPendiente,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    this.manual = true,
  });

  bool get liquidada => saldoPendiente <= 0;

  bool get vencida => !liquidada && fechaVencimiento != null && DateTime.now().isAfter(fechaVencimiento!);

  factory CompraCreditoModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return CompraCreditoModel(
      id: id,
      idProveedor: data['id_proveedor'] ?? '',
      documentoProveedor: data['documento_proveedor'] ?? '',
      nombreProveedor: data['nombre_proveedor'] ?? '',
      numeroDocumento: data['numero_documento'] ?? '',
      noFactura: data['no_factura'] ?? '',
      montoTotal: (data['monto_total'] ?? 0).toDouble(),
      saldoPendiente: (data['saldo_pendiente'] ?? 0).toDouble(),
      fechaRegistro: fecha(data['fecha_registro'] as String?),
      fechaVencimiento: fecha(data['fecha_vencimiento'] as String?),
      manual: data['manual'] ?? true,
    );
  }

  String get textoBusqueda => '$numeroDocumento $noFactura $nombreProveedor';
}
