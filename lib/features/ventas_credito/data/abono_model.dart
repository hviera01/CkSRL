import 'package:cloud_firestore/cloud_firestore.dart';

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
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      montoAbonado: (data['montoAbonado'] ?? 0).toDouble(),
      saldoAnterior: (data['saldoAnterior'] ?? 0).toDouble(),
      interes: (data['interes'] ?? 0).toDouble(),
      saldoPendiente: (data['saldoPendiente'] ?? 0).toDouble(),
      metodoPago: data['metodoPago'] ?? '',
      numeroRecibo: data['numeroRecibo'] ?? '',
      usuario: data['usuario'] ?? '',
    );
  }
}
