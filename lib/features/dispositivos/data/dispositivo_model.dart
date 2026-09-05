class DispositivoModel {
  final String id;
  final String plataforma;
  final int versionApp;
  final String usuario;
  final DateTime? ultimaConexion;

  DispositivoModel({
    required this.id,
    required this.plataforma,
    required this.versionApp,
    required this.usuario,
    required this.ultimaConexion,
  });

  factory DispositivoModel.fromMap(String id, Map<String, dynamic> data) {
    return DispositivoModel(
      id: id,
      plataforma: data['plataforma'] ?? '',
      versionApp: (data['version_app'] as num?)?.toInt() ?? 0,
      usuario: data['usuario'] ?? '',
      ultimaConexion: data['ultima_conexion'] == null ? null : DateTime.parse(data['ultima_conexion'] as String),
    );
  }
}
