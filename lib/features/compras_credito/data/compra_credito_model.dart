import 'package:cloud_firestore/cloud_firestore.dart';

class CompraCreditoModel {
  final String id;
  final String idProveedor;
  final String documentoProveedor;
  final String nombreProveedor;
  final String numeroDocumento;
  final String noFactura;
  final double montoTotal;
  final double saldoPendiente;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final bool manual;

  CompraCreditoModel({
    required this.id,
    required this.idProveedor,
    required this.documentoProveedor,
    required this.nombreProveedor,
    required this.numeroDocumento,
    required this.noFactura,
    required this.montoTotal,
    required this.saldoPendiente,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    this.manual = true,
  });

  bool get liquidada => saldoPendiente <= 0;

  bool get vencida => !liquidada && fechaVencimiento != null && DateTime.now().isAfter(fechaVencimiento!);

  factory CompraCreditoModel.fromMap(String id, Map<String, dynamic> data) {
    return CompraCreditoModel(
      id: id,
      idProveedor: data['idProveedor'] ?? '',
      documentoProveedor: data['documentoProveedor'] ?? '',
      nombreProveedor: data['nombreProveedor'] ?? '',
      numeroDocumento: data['numeroDocumento'] ?? '',
      noFactura: data['noFactura'] ?? '',
      montoTotal: (data['montoTotal'] ?? 0).toDouble(),
      saldoPendiente: (data['saldoPendiente'] ?? 0).toDouble(),
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      manual: data['manual'] ?? true,
    );
  }

  String get textoBusqueda => '$numeroDocumento $noFactura $nombreProveedor';
}
