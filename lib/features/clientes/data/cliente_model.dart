class ClienteModel {
  final String id;
  final String dni;
  final String nombreCompleto;
  final String direccion;
  final String telefono;
  final bool estado;
  // Denormalizado: se actualiza solo (merge) cada vez que este cliente
  // registra una venta real (ver VentaRepository.registrarVenta), para poder
  // detectar clientes inactivos sin tener que recorrer todas sus ventas cada
  // vez (Fase 3 del CRM).
  final DateTime? fechaUltimaCompra;

  ClienteModel({
    required this.id,
    required this.dni,
    required this.nombreCompleto,
    required this.direccion,
    required this.telefono,
    required this.estado,
    this.fechaUltimaCompra,
  });

  factory ClienteModel.fromMap(String id, Map<String, dynamic> data) {
    return ClienteModel(
      id: id,
      dni: data['dni'] ?? '',
      nombreCompleto: data['nombre_completo'] ?? '',
      direccion: data['direccion'] ?? '',
      telefono: data['telefono'] ?? '',
      estado: data['estado'] ?? true,
      fechaUltimaCompra: data['fecha_ultima_compra'] == null ? null : DateTime.parse(data['fecha_ultima_compra'] as String),
    );
  }

  /// Serialización completa del modelo. OJO: `ClienteRepository.actualizar`
  /// (el editar desde el formulario de Clientes) NO usa esto tal cual para
  /// no pisar `fechaUltimaCompra` con null cada vez que alguien solo corrige
  /// el teléfono -ese campo lo escribe otro flujo (registrar venta)-. Sí se
  /// usa completo en `crear`, donde no hay nada previo que perder.
  Map<String, dynamic> toMap() {
    return {
      'dni': dni,
      'nombre_completo': nombreCompleto,
      'direccion': direccion,
      'telefono': telefono,
      'estado': estado,
      'fecha_ultima_compra': fechaUltimaCompra?.toIso8601String(),
    };
  }

  String get textoBusqueda => '$dni $nombreCompleto $direccion $telefono';
}
