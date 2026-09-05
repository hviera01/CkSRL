import 'package:cloud_firestore/cloud_firestore.dart';

class ReporteCompraModel {
  final String id;
  final DateTime? fechaRegistro;
  final String tipoDocumento;
  final String noFactura;
  final String numeroDocumento;
  final double montoTotal;
  final int cantidadProductos;
  final String usuarioRegistro;
  final String documentoProveedor;
  final String idProveedor;
  final String razonSocial;
  final String condicion;
  final String metodoPago;
  final DateTime? fechaVencimiento;
  final double impuesto;
  final double descuentoTotalMonto;
  final double ajusteManual;
  final String estado;

  bool get esActiva => estado == 'Activa';

  ReporteCompraModel({
    required this.id,
    required this.fechaRegistro,
    required this.tipoDocumento,
    required this.noFactura,
    required this.numeroDocumento,
    required this.montoTotal,
    required this.cantidadProductos,
    required this.usuarioRegistro,
    required this.documentoProveedor,
    required this.idProveedor,
    required this.razonSocial,
    required this.condicion,
    required this.metodoPago,
    required this.fechaVencimiento,
    required this.impuesto,
    this.descuentoTotalMonto = 0,
    this.ajusteManual = 0,
    this.estado = 'Activa',
  });

  factory ReporteCompraModel.fromMap(String id, Map<String, dynamic> data) {
    return ReporteCompraModel(
      id: id,
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      tipoDocumento: data['tipoDocumento'] ?? 'Factura',
      noFactura: data['noFactura'] ?? '',
      numeroDocumento: data['numeroDocumento'] ?? '',
      montoTotal: (data['totalAPagar'] ?? 0).toDouble(),
      cantidadProductos: (data['cantidadProductos'] ?? 0).toInt(),
      usuarioRegistro: data['usuarioRegistro'] ?? '',
      documentoProveedor: data['documentoProveedor'] ?? '',
      idProveedor: data['idProveedor'] ?? '',
      razonSocial: data['razonSocial'] ?? '',
      condicion: data['condicion'] ?? '',
      metodoPago: data['metodoPago'] ?? '',
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      descuentoTotalMonto: (data['descuentoTotalMonto'] ?? 0).toDouble(),
      ajusteManual: (data['ajusteManual'] ?? 0).toDouble(),
      estado: data['estado'] ?? 'Activa',
    );
  }

  String get textoBusqueda => '$numeroDocumento $noFactura $razonSocial $documentoProveedor $metodoPago $tipoDocumento $condicion $usuarioRegistro';
}
