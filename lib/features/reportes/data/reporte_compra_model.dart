class ReporteCompraModel {
  final String id;
  final DateTime? fechaRegistro;
  final String tipoDocumento;
  final String noFactura;
  final String numeroDocumento;
  final double montoTotal;
  final int cantidadProductos;
  final String usuarioRegistro;
  final String documentoProveedor;
  final String idProveedor;
  final String razonSocial;
  final String condicion;
  final String metodoPago;
  final DateTime? fechaVencimiento;
  final double impuesto;
  final double descuentoTotalMonto;
  final double ajusteManual;
  final String estado;

  bool get esActiva => estado == 'Activa';

  ReporteCompraModel({
    required this.id,
    required this.fechaRegistro,
    required this.tipoDocumento,
    required this.noFactura,
    required this.numeroDocumento,
    required this.montoTotal,
    required this.cantidadProductos,
    required this.usuarioRegistro,
    required this.documentoProveedor,
    required this.idProveedor,
    required this.razonSocial,
    required this.condicion,
    required this.metodoPago,
    required this.fechaVencimiento,
    required this.impuesto,
    this.descuentoTotalMonto = 0,
    this.ajusteManual = 0,
    this.estado = 'Activa',
  });

  /// Lee una fila de la tabla `compras` (columnas snake_case) tal como la
  /// devuelve Supabase -mismo criterio que CompraModel.fromMap/ItemVentaModel.fromRow-.
  factory ReporteCompraModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return ReporteCompraModel(
      id: id,
      fechaRegistro: fecha(data['fecha_registro'] as String?),
      tipoDocumento: data['tipo_documento'] ?? 'Factura',
      noFactura: data['no_factura'] ?? '',
      numeroDocumento: data['numero_documento'] ?? '',
      montoTotal: (data['total_a_pagar'] ?? 0).toDouble(),
      cantidadProductos: (data['cantidad_productos'] ?? 0).toInt(),
      usuarioRegistro: data['usuario_registro'] ?? '',
      documentoProveedor: data['documento_proveedor'] ?? '',
      idProveedor: data['id_proveedor'] ?? '',
      razonSocial: data['razon_social'] ?? '',
      condicion: data['condicion'] ?? '',
      metodoPago: data['metodo_pago'] ?? '',
      fechaVencimiento: fecha(data['fecha_vencimiento'] as String?),
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      descuentoTotalMonto: (data['descuento_total_monto'] ?? 0).toDouble(),
      ajusteManual: (data['ajuste_manual'] ?? 0).toDouble(),
      estado: data['estado'] ?? 'Activa',
    );
  }

  String get textoBusqueda =>
      '$numeroDocumento $noFactura $razonSocial $documentoProveedor $metodoPago $tipoDocumento $condicion $usuarioRegistro';
}
