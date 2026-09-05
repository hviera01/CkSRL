class UsuarioModel {
  final String id;
  final String documento;
  final String nombreCompleto;
  final String correo;
  final String rol;
  final bool estado;

  UsuarioModel({
    required this.id,
    required this.documento,
    required this.nombreCompleto,
    required this.correo,
    required this.rol,
    required this.estado,
  });

  factory UsuarioModel.fromMap(String id, Map<String, dynamic> data) {
    return UsuarioModel(
      id: id,
      documento: data['documento'] ?? '',
      nombreCompleto: data['nombreCompleto'] ?? '',
      correo: data['correo'] ?? '',
      rol: data['rol'] ?? '',
      estado: data['estado'] ?? true,
    );
  }
}