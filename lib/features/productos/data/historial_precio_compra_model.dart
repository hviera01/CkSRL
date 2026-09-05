/// Un registro histórico del costo de un producto, calculado cada vez que se
/// registra una compra que lo incluye: precio unitario ingresado, menos el
/// descuento de línea (importe gravado), más el ISV de la compra — ese
/// resultado es el que se guarda como `precioCompra` vigente del producto.
class HistorialPrecioCompraModel {
  final String id;
  final String idCompra;
  final double precioCompra;
  final double precioUnitario;
  final double descuentoPorcentaje;
  final double isvPorcentaje;
  final double cantidad;
  final DateTime? fecha;
  final String numeroDocumento;
  final String noFactura;
  final String proveedor;
  final String usuario;

  HistorialPrecioCompraModel({
    required this.id,
    required this.idCompra,
    required this.precioCompra,
    required this.precioUnitario,
    required this.descuentoPorcentaje,
    required this.isvPorcentaje,
    required this.cantidad,
    required this.fecha,
    required this.numeroDocumento,
    required this.noFactura,
    required this.proveedor,
    required this.usuario,
  });

  factory HistorialPrecioCompraModel.fromMap(String id, Map<String, dynamic> data) {
    return HistorialPrecioCompraModel(
      id: id,
      idCompra: data['id_compra'] ?? '',
      precioCompra: (data['precio_compra'] ?? 0).toDouble(),
      precioUnitario: (data['precio_unitario'] ?? 0).toDouble(),
      descuentoPorcentaje: (data['descuento_porcentaje'] ?? 0).toDouble(),
      isvPorcentaje: (data['isv_porcentaje'] ?? 0).toDouble(),
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      fecha: data['fecha'] == null ? null : DateTime.parse(data['fecha'] as String),
      numeroDocumento: data['numero_documento'] ?? '',
      noFactura: data['no_factura'] ?? '',
      proveedor: data['proveedor'] ?? '',
      usuario: data['usuario'] ?? '',
    );
  }
}
