/// Línea de un apartado -snapshot congelado (nombre/precio no cambian
/// aunque el producto de catálogo cambie después), mismo patrón que
/// ItemVentaModel/venta_items-.
class ApartadoItemModel {
  final String id;
  final String idApartado;
  final String? idProducto;
  final String nombreProducto;
  final double cantidad;
  final double precioUnitario;
  final double subtotal;

  ApartadoItemModel({
    required this.id,
    required this.idApartado,
    this.idProducto,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  factory ApartadoItemModel.fromMap(String id, Map<String, dynamic> data) {
    return ApartadoItemModel(
      id: id,
      idApartado: data['id_apartado'] ?? '',
      idProducto: data['id_producto'] as String?,
      nombreProducto: data['nombre_producto'] ?? '',
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      precioUnitario: (data['precio_unitario'] ?? 0).toDouble(),
      subtotal: (data['subtotal'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'idProducto': idProducto,
        'nombreProducto': nombreProducto,
        'cantidad': cantidad,
        'precioUnitario': precioUnitario,
        'subtotal': subtotal,
      };
}
