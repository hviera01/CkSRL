class ProveedorModel {
  final String id;
  final String rtn;
  final String razonSocial;
  final String correo;
  final String telefono;
  final bool estado;

  ProveedorModel({
    required this.id,
    required this.rtn,
    required this.razonSocial,
    required this.correo,
    required this.telefono,
    required this.estado,
  });

  factory ProveedorModel.fromMap(String id, Map<String, dynamic> data) {
    return ProveedorModel(
      id: id,
      rtn: data['rtn'] ?? '',
      razonSocial: data['razonSocial'] ?? '',
      correo: data['correo'] ?? '',
      telefono: data['telefono'] ?? '',
      estado: data['estado'] ?? true,
    );
  }

  String get textoBusqueda => '$rtn $razonSocial $correo $telefono';
}
