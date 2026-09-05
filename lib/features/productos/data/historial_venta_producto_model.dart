/// Un registro histórico de venta de un producto: precio unitario con ISV al
/// que se vendió (ya con el descuento de línea aplicado), en el orden en que
/// se fueron registrando las ventas.
class HistorialVentaProductoModel {
  final String id;
  final String idVenta;
  final double precioVenta;
  final double precioUnitario;
  final double descuentoPorcentaje;
  final double cantidad;
  final DateTime? fecha;
  final String tipoDocumento;
  final String numeroDocumento;
  final String cliente;
  final String usuario;

  HistorialVentaProductoModel({
    required this.id,
    required this.idVenta,
    required this.precioVenta,
    required this.precioUnitario,
    required this.descuentoPorcentaje,
    required this.cantidad,
    required this.fecha,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.cliente,
    required this.usuario,
  });

  factory HistorialVentaProductoModel.fromMap(String id, Map<String, dynamic> data) {
    return HistorialVentaProductoModel(
      id: id,
      idVenta: data['id_venta'] ?? '',
      precioVenta: (data['precio_venta'] ?? 0).toDouble(),
      precioUnitario: (data['precio_unitario'] ?? 0).toDouble(),
      descuentoPorcentaje: (data['descuento_porcentaje'] ?? 0).toDouble(),
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      fecha: data['fecha'] == null ? null : DateTime.parse(data['fecha'] as String),
      tipoDocumento: data['tipo_documento'] ?? '',
      numeroDocumento: data['numero_documento'] ?? '',
      cliente: data['cliente'] ?? '',
      usuario: data['usuario'] ?? '',
    );
  }
}
