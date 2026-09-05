/// Rastrea una línea de venta marcada "pendiente de compra" (venta
/// anticipada): se vendió un producto sin saber todavía cuál compra exacta
/// lo va a reponer -por ejemplo, pintura preparada antes de comprar el
/// insumo real-. Mientras [estado] sea 'Pendiente', la próxima compra que
/// entre de [idProducto] se reparte automáticamente contra esto (la más
/// vieja primero, ver CompraRepository.registrarCompra), corrigiendo el
/// costo de la línea de venta original al costo real de esa compra.
class PendienteReposicionModel {
  final String id;
  final String idVenta;
  final String numeroDocumentoVenta;
  final String idItemDetalle;
  final String idProducto;
  final String nombreProducto;
  final String idCategoria;
  final double cantidadOriginal;
  final double cantidadPendiente;
  final double costoRegistrado;
  final DateTime fechaRegistro;
  final String estado;
  final DateTime? fechaCompletado;
  final String usuario;

  PendienteReposicionModel({
    required this.id,
    required this.idVenta,
    required this.numeroDocumentoVenta,
    required this.idItemDetalle,
    required this.idProducto,
    required this.nombreProducto,
    required this.idCategoria,
    required this.cantidadOriginal,
    required this.cantidadPendiente,
    required this.costoRegistrado,
    required this.fechaRegistro,
    required this.estado,
    this.fechaCompletado,
    required this.usuario,
  });

  bool get completado => estado == 'Completado';
  bool get cancelado => estado == 'Cancelado';

  factory PendienteReposicionModel.fromMap(String id, Map<String, dynamic> data) {
    return PendienteReposicionModel(
      id: id,
      idVenta: data['id_venta'] ?? '',
      numeroDocumentoVenta: data['numero_documento_venta'] ?? '',
      idItemDetalle: data['id_item_detalle'] ?? '',
      idProducto: data['id_producto'] ?? '',
      nombreProducto: data['nombre_producto'] ?? '',
      idCategoria: data['id_categoria'] ?? '',
      cantidadOriginal: ((data['cantidad_original'] ?? 0) as num).toDouble(),
      cantidadPendiente: ((data['cantidad_pendiente'] ?? 0) as num).toDouble(),
      costoRegistrado: ((data['costo_registrado'] ?? 0) as num).toDouble(),
      fechaRegistro: data['fecha_registro'] == null ? DateTime.now() : DateTime.parse(data['fecha_registro'] as String),
      estado: data['estado'] ?? 'Pendiente',
      fechaCompletado: data['fecha_completado'] == null ? null : DateTime.parse(data['fecha_completado'] as String),
      usuario: data['usuario'] ?? '',
    );
  }
}
