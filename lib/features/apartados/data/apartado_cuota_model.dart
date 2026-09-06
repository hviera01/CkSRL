/// Cuota programada de un apartado en modalidad 'cuotas_fijas' (ver
/// apartado_cuotas en supabase/schema.sql). [fechaProgramada] es una fecha
/// de calendario sin hora significativa -columna `date`, no `timestamptz`-.
class ApartadoCuotaModel {
  final String id;
  final String idApartado;
  final int numeroCuota;
  final double montoProgramado;
  final DateTime fechaProgramada;
  // 'pendiente' | 'pagada' | 'vencida'. OJO: el valor guardado en la fila
  // nunca pasa solo a 'vencida' -no hay ningún proceso que la actualice-,
  // así que la UI calcula "vencida" a partir de [pendiente] + [fechaProgramada]
  // (ver [vencida] abajo) en vez de confiar ciegamente en este texto.
  final String estado;
  // Cuándo se terminó de cubrir de verdad -la escribe registrar_abono_apartado
  // con la misma fecha que el pago que la cerró-, no confundir con
  // [fechaProgramada] (la fecha límite original). Null mientras esté pendiente.
  final DateTime? fechaPago;

  ApartadoCuotaModel({
    required this.id,
    required this.idApartado,
    required this.numeroCuota,
    required this.montoProgramado,
    required this.fechaProgramada,
    required this.estado,
    this.fechaPago,
  });

  bool get pagada => estado == 'pagada';
  bool get pendiente => estado == 'pendiente';
  bool get vencida => pendiente && DateTime.now().isAfter(fechaProgramada);

  factory ApartadoCuotaModel.fromMap(String id, Map<String, dynamic> data) {
    return ApartadoCuotaModel(
      id: id,
      idApartado: data['id_apartado'] ?? '',
      numeroCuota: (data['numero_cuota'] ?? 0) as int,
      montoProgramado: (data['monto_programado'] ?? 0).toDouble(),
      fechaProgramada: DateTime.parse(data['fecha_programada'] as String),
      estado: data['estado'] ?? 'pendiente',
      fechaPago: data['fecha_pago'] == null ? null : DateTime.parse(data['fecha_pago'] as String),
    );
  }
}
