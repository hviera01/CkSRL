/// Un lote de costo: la cantidad de un producto que entró de una sola vez
/// (una compra o un ajuste manual de stock) a un costo unitario propio. El
/// costeo FIFO consume primero el lote más viejo con cantidadRestante > 0,
/// para que si un producto se compró una vez a 10 y otra vez a 12, la
/// primera unidad vendida cueste 10 y la segunda 12 (en vez de un costo
/// promediado por producto).
class LoteCostoModel {
  final String id;
  final double cantidadOriginal;
  final double cantidadRestante;
  final double costoUnitario;
  final DateTime fecha;
  final String origen; // 'compra' | 'ajuste'
  final String? idCompra;
  // Orden manual (0 = sale primero). Null = todavía nadie lo reordenó a
  // mano, así que se ordena por fecha (el comportamiento FIFO de siempre).
  // Ver LoteCostoRepository.reordenarLotes: al reordenar se le asigna
  // prioridad a TODOS los lotes con existencia de una vez, para no mezclar
  // lotes "con prioridad" y "sin prioridad" de forma ambigua.
  final int? prioridad;

  LoteCostoModel({
    required this.id,
    required this.cantidadOriginal,
    required this.cantidadRestante,
    required this.costoUnitario,
    required this.fecha,
    required this.origen,
    this.idCompra,
    this.prioridad,
  });

  factory LoteCostoModel.fromMap(String id, Map<String, dynamic> data) {
    return LoteCostoModel(
      id: id,
      cantidadOriginal: (data['cantidad_original'] ?? 0).toDouble(),
      cantidadRestante: (data['cantidad_restante'] ?? 0).toDouble(),
      costoUnitario: (data['costo_unitario'] ?? 0).toDouble(),
      fecha: data['fecha'] == null ? DateTime.now() : DateTime.parse(data['fecha'] as String),
      origen: data['origen'] ?? 'compra',
      idCompra: data['id_compra'],
      prioridad: (data['prioridad'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cantidad_original': cantidadOriginal,
      'cantidad_restante': cantidadRestante,
      'costo_unitario': costoUnitario,
      'fecha': fecha.toIso8601String(),
      'origen': origen,
      'id_compra': idCompra,
      'prioridad': prioridad,
    };
  }
}
