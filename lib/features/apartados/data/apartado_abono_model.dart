/// Abono libre de un apartado en modalidad 'abonos_libres' -mismo patrón que
/// AbonoModel (ventas_credito) / AbonoCompraModel (compras_credito)-.
class ApartadoAbonoModel {
  final String id;
  final String idApartado;
  final double montoAbonado;
  final DateTime? fecha;
  final double saldoAnterior;
  final double saldoPendiente;

  ApartadoAbonoModel({
    required this.id,
    required this.idApartado,
    required this.montoAbonado,
    required this.fecha,
    required this.saldoAnterior,
    required this.saldoPendiente,
  });

  factory ApartadoAbonoModel.fromMap(String id, Map<String, dynamic> data) {
    return ApartadoAbonoModel(
      id: id,
      idApartado: data['id_apartado'] ?? '',
      montoAbonado: (data['monto_abonado'] ?? 0).toDouble(),
      fecha: data['fecha'] == null ? null : DateTime.parse(data['fecha'] as String),
      saldoAnterior: (data['saldo_anterior'] ?? 0).toDouble(),
      saldoPendiente: (data['saldo_pendiente'] ?? 0).toDouble(),
    );
  }
}
