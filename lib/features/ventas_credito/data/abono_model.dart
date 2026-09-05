class AbonoModel {
  final String id;
  final DateTime? fecha;
  final double montoAbonado;
  final double saldoAnterior;
  final double interes;
  final double saldoPendiente;
  final String metodoPago;
  final String numeroRecibo;
  final String usuario;

  AbonoModel({
    required this.id,
    required this.fecha,
    required this.montoAbonado,
    required this.saldoAnterior,
    required this.interes,
    required this.saldoPendiente,
    required this.metodoPago,
    required this.numeroRecibo,
    required this.usuario,
  });

  factory AbonoModel.fromMap(String id, Map<String, dynamic> data) {
    return AbonoModel(
      id: id,
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
