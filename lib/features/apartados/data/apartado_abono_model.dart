/// Abono de un apartado -de CUALQUIER modalidad, incluido el pago inicial
/// REAL (ver [esInicial])-, mismo patrón que AbonoModel (ventas_credito) /
/// AbonoCompraModel (compras_credito).
class ApartadoAbonoModel {
  final String id;
  final String idApartado;
  final double montoAbonado;
  final DateTime? fecha;
  final double saldoAnterior;
  final double saldoPendiente;
  // 'Efectivo' | 'Tarjeta' | 'Transferencia' (mismas opciones que
  // carrito_provider.dart en Ventas) -null en pagos viejos migrados antes de
  // que existiera esta columna, donde no se sabe cuál fue-.
  final String? metodoPago;
  // true solo en el PRIMER movimiento real (el pago inicial que el cliente
  // dio al armar el apartado, ver crear_apartado en supabase/schema.sql):
  // cuenta para el saldo general pero NO se reparte contra las cuotas
  // programadas (esas ya se calculan excluyendo el inicial sugerido).
  final bool esInicial;

  ApartadoAbonoModel({
    required this.id,
    required this.idApartado,
    required this.montoAbonado,
    required this.fecha,
    required this.saldoAnterior,
    required this.saldoPendiente,
    this.metodoPago,
    this.esInicial = false,
  });

  factory ApartadoAbonoModel.fromMap(String id, Map<String, dynamic> data) {
    return ApartadoAbonoModel(
      id: id,
      idApartado: data['id_apartado'] ?? '',
      montoAbonado: (data['monto_abonado'] ?? 0).toDouble(),
      fecha: data['fecha'] == null ? null : DateTime.parse(data['fecha'] as String),
      saldoAnterior: (data['saldo_anterior'] ?? 0).toDouble(),
      saldoPendiente: (data['saldo_pendiente'] ?? 0).toDouble(),
      metodoPago: data['metodo_pago'] as String?,
      esInicial: data['es_inicial'] ?? false,
    );
  }
}
