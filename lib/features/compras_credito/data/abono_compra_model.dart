class AbonoCompraModel {
  final String id;
  final String idCompra;
  final String idProveedor;
  final String nombreProveedor;
  final DateTime? fecha;
  final double montoAbonado;
  final double saldoAnterior;
  final double interes;
  final double saldoPendiente;
  final String metodoPago;
  final String numeroRecibo;
  final String usuario;

  AbonoCompraModel({
    required this.id,
    required this.idCompra,
    required this.idProveedor,
    required this.nombreProveedor,
    required this.fecha,
    required this.montoAbonado,
    required this.saldoAnterior,
    required this.interes,
    required this.saldoPendiente,
    required this.metodoPago,
    required this.numeroRecibo,
    required this.usuario,
  });

  factory AbonoCompraModel.fromMap(String id, Map<String, dynamic> data) {
    return AbonoCompraModel(
      id: id,
      idCompra: data['id_compra_credito'] ?? '',
      idProveedor: data['id_proveedor'] ?? '',
      nombreProveedor: data['nombre_proveedor'] ?? '',
      fecha: data['fecha'] == null ? null : DateTime.parse(data['fecha'] as String),
      montoAbonado: (data['monto_abonado'] ?? 0).toDouble(),
      saldoAnterior: (data['saldo_anterior'] ?? 0).toDouble(),
      interes: (data['interes'] ?? 0).toDouble(),
      saldoPendiente: (data['saldo_pendiente'] ?? 0).toDouble(),
      metodoPago: data['metodo_pago'] ?? '',
      numeroRecibo: data['numero_recibo'] ?? '',
      usuario: data['usuario'] ?? '',
    );
  }
}
