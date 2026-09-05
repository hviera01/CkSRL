import 'package:cloud_firestore/cloud_firestore.dart';

class EgresoModel {
  final String id;
  final DateTime fecha;
  final double monto;
  final String descripcion;
  final String usuario;
  final String metodoPago;
  final String categoria;
  final bool esPagado;
  final DateTime? fechaPago;
  final DateTime? fechaRegistro;

  EgresoModel({
    this.id = '',
    required this.fecha,
    required this.monto,
    required this.descripcion,
    required this.usuario,
    required this.metodoPago,
    required this.categoria,
    required this.esPagado,
    this.fechaPago,
    this.fechaRegistro,
  });

  Map<String, dynamic> toMap() {
    return {
      'fecha': Timestamp.fromDate(fecha),
      'monto': monto,
      'descripcion': descripcion,
      'usuario': usuario,
      'metodoPago': metodoPago,
      'categoria': categoria,
      'esPagado': esPagado,
      'fechaPago': fechaPago != null ? Timestamp.fromDate(fechaPago!) : null,
      'fechaRegistro': FieldValue.serverTimestamp(),
    };
  }

  factory EgresoModel.fromMap(String id, Map<String, dynamic> data) {
    return EgresoModel(
      id: id,
      fecha: (data['fecha'] as Timestamp?)?.toDate() ?? DateTime.now(),
      monto: (data['monto'] ?? 0).toDouble(),
      descripcion: data['descripcion'] ?? '',
      usuario: data['usuario'] ?? '',
      metodoPago: data['metodoPago'] ?? 'Efectivo',
      categoria: data['categoria'] ?? 'Negocio',
      esPagado: data['esPagado'] ?? true,
      fechaPago: (data['fechaPago'] as Timestamp?)?.toDate(),
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
    );
  }

  String get textoBusqueda => '$descripcion $usuario $metodoPago $categoria';
}

/// Un renglón del libro financiero: puede venir de una venta de contado, un
/// abono a crédito, una compra de contado, un abono a compra de crédito o un
/// egreso manual. `ingreso` y `egreso` son mutuamente excluyentes.
class MovimientoFinanciero {
  final DateTime fecha;
  final String tipoMovimiento;
  final String descripcion;
  final double ingreso;
  final double egreso;
  final String metodoPago;
  final String categoria;
  final bool esPagado;
  final DateTime? fechaPago;
  final String usuario;
  final String idEgreso;

  MovimientoFinanciero({
    required this.fecha,
    required this.tipoMovimiento,
    required this.descripcion,
    this.ingreso = 0,
    this.egreso = 0,
    this.metodoPago = '',
    this.categoria = '',
    this.esPagado = true,
    this.fechaPago,
    this.usuario = '',
    this.idEgreso = '',
  });

  bool get esEgresoManual => tipoMovimiento == 'Egreso Manual';
}
