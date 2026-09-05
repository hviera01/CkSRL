import 'package:cloud_firestore/cloud_firestore.dart';

class ColorModel {
  final String id;
  final String codigo;
  final String cliente;
  final String descripcion;
  final String ubicacionFisica;
  final String pagina;
  final DateTime? fechaRegistro;
  final String observaciones;

  ColorModel({
    required this.id,
    required this.codigo,
    required this.cliente,
    required this.descripcion,
    required this.ubicacionFisica,
    required this.pagina,
    required this.fechaRegistro,
    required this.observaciones,
  });

  factory ColorModel.fromMap(String id, Map<String, dynamic> data) {
    return ColorModel(
      id: id,
      codigo: data['codigo'] ?? '',
      cliente: data['cliente'] ?? '',
      descripcion: data['descripcion'] ?? '',
      ubicacionFisica: data['ubicacionFisica'] ?? '',
      pagina: data['pagina'] ?? '',
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      observaciones: data['observaciones'] ?? '',
    );
  }

  String get textoBusqueda => '$codigo $cliente $descripcion $ubicacionFisica $observaciones';
}
