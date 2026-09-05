class CierreCajaModel {
  final String id;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final double montoInicial;
  final double ingresosEfectivo;
  final double ingresosTarjeta;
  final double ingresosTransferencia;
  final double egresosEfectivo;
  final double egresosTransferencia;
  final double totalCalculadoEfectivo;
  final double totalTransferencia;
  final double granTotal;
  final double totalReal;
  final double diferencia;
  final String usuarioResponsable;
  final String observaciones;
  final DateTime? fechaRegistro;

  CierreCajaModel({
    this.id = '',
    required this.fechaInicio,
    required this.fechaFin,
    required this.montoInicial,
    required this.ingresosEfectivo,
    required this.ingresosTarjeta,
    required this.ingresosTransferencia,
    required this.egresosEfectivo,
    required this.egresosTransferencia,
    required this.totalCalculadoEfectivo,
    required this.totalTransferencia,
    required this.granTotal,
    required this.totalReal,
    required this.diferencia,
    required this.usuarioResponsable,
    this.observaciones = '',
    this.fechaRegistro,
  });

  Map<String, dynamic> toMap() {
    return {
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'monto_inicial': montoInicial,
      'ingresos_efectivo': ingresosEfectivo,
      'ingresos_tarjeta': ingresosTarjeta,
      'ingresos_transferencia': ingresosTransferencia,
      'egresos_efectivo': egresosEfectivo,
      'egresos_transferencia': egresosTransferencia,
      'total_calculado_efectivo': totalCalculadoEfectivo,
      'total_transferencia': totalTransferencia,
      'gran_total': granTotal,
      'total_real': totalReal,
      'diferencia': diferencia,
      'usuario_responsable': usuarioResponsable,
      'observaciones': observaciones,
    };
  }

  factory CierreCajaModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? fecha(String? iso) => iso == null ? null : DateTime.parse(iso);
    return CierreCajaModel(
      id: id,
      fechaInicio: fecha(data['fecha_inicio'] as String?) ?? DateTime.now(),
      fechaFin: fecha(data['fecha_fin'] as String?) ?? DateTime.now(),
      montoInicial: (data['monto_inicial'] ?? 0).toDouble(),
      ingresosEfectivo: (data['ingresos_efectivo'] ?? 0).toDouble(),
      ingresosTarjeta: (data['ingresos_tarjeta'] ?? 0).toDouble(),
      ingresosTransferencia: (data['ingresos_transferencia'] ?? 0).toDouble(),
      egresosEfectivo: (data['egresos_efectivo'] ?? 0).toDouble(),
      egresosTransferencia: (data['egresos_transferencia'] ?? 0).toDouble(),
      totalCalculadoEfectivo: (data['total_calculado_efectivo'] ?? 0).toDouble(),
      totalTransferencia: (data['total_transferencia'] ?? 0).toDouble(),
      granTotal: (data['gran_total'] ?? 0).toDouble(),
      totalReal: (data['total_real'] ?? 0).toDouble(),
      diferencia: (data['diferencia'] ?? 0).toDouble(),
      usuarioResponsable: data['usuario_responsable'] ?? '',
      observaciones: data['observaciones'] ?? '',
      fechaRegistro: fecha(data['fecha_registro'] as String?),
    );
  }
}

class TotalesCaja {
  final double ingresosEfectivo;
  final double ingresosTarjeta;
  final double ingresosTransferencia;
  final double egresosEfectivo;
  final double egresosTransferencia;

  const TotalesCaja({
    this.ingresosEfectivo = 0,
    this.ingresosTarjeta = 0,
    this.ingresosTransferencia = 0,
    this.egresosEfectivo = 0,
    this.egresosTransferencia = 0,
  });
}
