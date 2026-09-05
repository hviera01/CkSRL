import 'package:cloud_firestore/cloud_firestore.dart';

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
      'fechaInicio': Timestamp.fromDate(fechaInicio),
      'fechaFin': Timestamp.fromDate(fechaFin),
      'montoInicial': montoInicial,
      'ingresosEfectivo': ingresosEfectivo,
      'ingresosTarjeta': ingresosTarjeta,
      'ingresosTransferencia': ingresosTransferencia,
      'egresosEfectivo': egresosEfectivo,
      'egresosTransferencia': egresosTransferencia,
      'totalCalculadoEfectivo': totalCalculadoEfectivo,
      'totalTransferencia': totalTransferencia,
      'granTotal': granTotal,
      'totalReal': totalReal,
      'diferencia': diferencia,
      'usuarioResponsable': usuarioResponsable,
      'observaciones': observaciones,
      'fechaRegistro': FieldValue.serverTimestamp(),
    };
  }

  factory CierreCajaModel.fromMap(String id, Map<String, dynamic> data) {
    return CierreCajaModel(
      id: id,
      fechaInicio: (data['fechaInicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fechaFin: (data['fechaFin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      montoInicial: (data['montoInicial'] ?? 0).toDouble(),
      ingresosEfectivo: (data['ingresosEfectivo'] ?? 0).toDouble(),
      ingresosTarjeta: (data['ingresosTarjeta'] ?? 0).toDouble(),
      ingresosTransferencia: (data['ingresosTransferencia'] ?? 0).toDouble(),
      egresosEfectivo: (data['egresosEfectivo'] ?? 0).toDouble(),
      egresosTransferencia: (data['egresosTransferencia'] ?? 0).toDouble(),
      totalCalculadoEfectivo: (data['totalCalculadoEfectivo'] ?? 0).toDouble(),
      totalTransferencia: (data['totalTransferencia'] ?? 0).toDouble(),
      granTotal: (data['granTotal'] ?? 0).toDouble(),
      totalReal: (data['totalReal'] ?? 0).toDouble(),
      diferencia: (data['diferencia'] ?? 0).toDouble(),
      usuarioResponsable: data['usuarioResponsable'] ?? '',
      observaciones: data['observaciones'] ?? '',
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
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
