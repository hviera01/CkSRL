import 'package:cloud_firestore/cloud_firestore.dart';

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
      idCompra: data['idCompra'] ?? '',
      idProveedor: data['idProveedor'] ?? '',
      nombreProveedor: data['nombreProveedor'] ?? '',
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
