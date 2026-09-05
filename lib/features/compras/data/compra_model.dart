import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_compra_model.dart';

class CompraModel {
  final String id;
  final String tipoDocumento;
  final String numeroDocumento;
  final String noFactura;
  final String idProveedor;
  final String documentoProveedor;
  final String razonSocial;
  final String condicion;
  final String metodoPago;
  final double subtotal;
  final double descuentoGlobalPorcentaje;
  final double descuentoTotalMonto;
  final double isvPorcentaje;
  final double impuesto;
  final double ajusteManual;
  final double totalAPagar;
  final DateTime? fechaRegistro;
  final DateTime? fechaVencimiento;
  final String estado;
  final String usuarioRegistro;
  final double cantidadProductos;
  final List<ItemCompraModel> detalle;
  final String usuarioAnulacion;
  final String motivoAnulacion;
  final DateTime? fechaAnulacion;

  bool get estaAnulada => estado == 'Anulada';

  CompraModel({
    required this.id,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.noFactura,
    required this.idProveedor,
    required this.documentoProveedor,
    required this.razonSocial,
    required this.condicion,
    required this.metodoPago,
    required this.subtotal,
    this.descuentoGlobalPorcentaje = 0,
    this.descuentoTotalMonto = 0,
    this.isvPorcentaje = 15,
    required this.impuesto,
    this.ajusteManual = 0,
    required this.totalAPagar,
    required this.fechaRegistro,
    required this.fechaVencimiento,
    required this.estado,
    required this.usuarioRegistro,
    required this.cantidadProductos,
    required this.detalle,
    this.usuarioAnulacion = '',
    this.motivoAnulacion = '',
    this.fechaAnulacion,
  });

  factory CompraModel.fromMap(String id, Map<String, dynamic> data, List<ItemCompraModel> detalle) {
    return CompraModel(
      id: id,
      tipoDocumento: data['tipoDocumento'] ?? 'Factura',
      numeroDocumento: data['numeroDocumento'] ?? '',
      noFactura: data['noFactura'] ?? '',
      idProveedor: data['idProveedor'] ?? '',
      documentoProveedor: data['documentoProveedor'] ?? '',
      razonSocial: data['razonSocial'] ?? '',
      condicion: data['condicion'] ?? '',
      metodoPago: data['metodoPago'] ?? '',
      subtotal: (data['subtotal'] ?? 0).toDouble(),
      descuentoGlobalPorcentaje: (data['descuentoGlobalPorcentaje'] ?? 0).toDouble(),
      descuentoTotalMonto: (data['descuentoTotalMonto'] ?? 0).toDouble(),
      isvPorcentaje: (data['isvPorcentaje'] ?? 15).toDouble(),
      impuesto: (data['impuesto'] ?? 0).toDouble(),
      ajusteManual: (data['ajusteManual'] ?? 0).toDouble(),
      totalAPagar: (data['totalAPagar'] ?? 0).toDouble(),
      fechaRegistro: (data['fechaRegistro'] as Timestamp?)?.toDate(),
      fechaVencimiento: (data['fechaVencimiento'] as Timestamp?)?.toDate(),
      estado: data['estado'] ?? 'Activa',
      usuarioRegistro: data['usuarioRegistro'] ?? '',
      cantidadProductos: (data['cantidadProductos'] ?? 0).toDouble(),
      detalle: detalle,
      usuarioAnulacion: data['usuarioAnulacion'] ?? '',
      motivoAnulacion: data['motivoAnulacion'] ?? '',
      fechaAnulacion: (data['fechaAnulacion'] as Timestamp?)?.toDate(),
    );
  }
}
