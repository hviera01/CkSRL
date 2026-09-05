class CategoriaModel {
  final String id;
  final String descripcion;
  final bool estado;
  // Si es false, los productos de esta categoría no bajan del inventario al
  // venderse y no bloquean/advierten la venta por tener existencia 0 o
  // negativa. Pensado para servicios o productos preparados al momento
  // (pintura preparada, mezclas, etc.) donde el stock no aplica.
  final bool controlaStock;

  CategoriaModel({
    required this.id,
    required this.descripcion,
    required this.estado,
    this.controlaStock = true,
  });

  factory CategoriaModel.fromMap(String id, Map<String, dynamic> data) {
    return CategoriaModel(
      id: id,
      descripcion: data['descripcion'] ?? '',
      estado: data['estado'] ?? true,
      controlaStock: data['controlaStock'] ?? true,
    );
  }
}