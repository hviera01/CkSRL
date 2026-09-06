/// Cabecera de un apartado (lay-away): el cliente deja pagado un % o un
/// monto fijo de uno o más productos y se los lleva SOLO cuando termina de
/// pagar el resto -a diferencia de una venta a crédito
/// (lib/features/ventas_credito/), donde el cliente sí se lleva el producto
/// de una vez-. Por eso el stock físico no se toca mientras [estado] sea
/// 'activo': ver ApartadoRepository.marcarEntregado, el único momento en que
/// de verdad se descuenta.
class ApartadoModel {
  final String id;
  final String? idCliente;
  // Snapshot congelado del nombre del cliente (mismo criterio que
  // VentaModel.nombreCliente/VentaCreditoModel.nombreCliente): no depende de
  // un join en vivo contra 'clientes' para listar apartados.
  final String nombreCliente;
  final double montoTotal;
  final double montoInicial;
  // 'cuotas_fijas' | 'abonos_libres'.
  final String modalidad;
  // 'activo' | 'completado' | 'cancelado'.
  final String estado;
  final DateTime? fechaCreacion;
  final DateTime? fechaEntrega;

  ApartadoModel({
    required this.id,
    this.idCliente,
    required this.nombreCliente,
    required this.montoTotal,
    required this.montoInicial,
    required this.modalidad,
    required this.estado,
    required this.fechaCreacion,
    this.fechaEntrega,
  });

  bool get esCuotasFijas => modalidad == 'cuotas_fijas';
  bool get activo => estado == 'activo';
  bool get completado => estado == 'completado';
  bool get cancelado => estado == 'cancelado';

  factory ApartadoModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return ApartadoModel(
      id: id,
      idCliente: data['id_cliente'] as String?,
      nombreCliente: data['nombre_cliente'] ?? '',
      montoTotal: (data['monto_total'] ?? 0).toDouble(),
      montoInicial: (data['monto_inicial'] ?? 0).toDouble(),
      modalidad: data['modalidad'] ?? 'abonos_libres',
      estado: data['estado'] ?? 'activo',
      fechaCreacion: fecha(data['fecha_creacion'] as String?),
      fechaEntrega: fecha(data['fecha_entrega'] as String?),
    );
  }

  String get textoBusqueda => nombreCliente;
}
