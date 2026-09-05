import 'package:cloud_firestore/cloud_firestore.dart';

/// Un registro histórico de venta de un producto: precio unitario con ISV al
/// que se vendió (ya con el descuento de línea aplicado), en el orden en que
/// se fueron registrando las ventas.
class HistorialVentaProductoModel {
  final String id;
  final String idVenta;
  final double precioVenta;
  final double precioUnitario;
  final double descuentoPorcentaje;
  final double cantidad;
  final DateTime? fecha;
  final String tipoDocumento;
  final String numeroDocumento;
  final String cliente;
  final String usuario;

  HistorialVentaProductoModel({
    required this.id,
    required this.idVenta,
    required this.precioVenta,
    required this.precioUnitario,
    required this.descuentoPorcentaje,
    required this.cantidad,
    required this.fecha,
    required this.tipoDocumento,
    required this.numeroDocumento,
    required this.cliente,
    required this.usuario,
  });

  factory HistorialVentaProductoModel.fromMap(String id, Map<String, dynamic> data) {
    return HistorialVentaProductoModel(
      id: id,
      idVenta: data['idVenta'] ?? '',
      precioVenta: (data['precioVenta'] ?? 0).toDouble(),
      precioUnitario: (data['precioUnitario'] ?? 0).toDouble(),
      descuentoPorcentaje: (data['descuentoPorcentaje'] ?? 0).toDouble(),
      cantidad: (data['cantidad'] ?? 0).toDouble(),
      fecha: (data['fecha'] as Timestamp?)?.toDate(),
      tipoDocumento: data['tipoDocumento'] ?? '',
      numeroDocumento: data['numeroDocumento'] ?? '',
      cliente: data['cliente'] ?? '',
      usuario: data['usuario'] ?? '',
    );
  }
}
