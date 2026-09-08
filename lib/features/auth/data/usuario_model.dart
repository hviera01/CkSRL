class UsuarioModel {
  final String id;
  final String documento;
  final String nombreCompleto;
  final String correo;
  final String rol;
  final bool estado;
  // Solo se usan (y se persisten) cuando rol == Roles.encargado o
  // Roles.empleado: qué pantallas (SubModulo.moduleKey) y qué acciones
  // (PermisosEspeciales.*) tiene habilitadas este usuario en particular.
  // Para cualquier otro rol quedan vacíos. Para Empleado, si el mapa viene
  // vacío (usuario creado antes de este cambio, o al que nunca se le tocó
  // nada) NO significa "sin acceso a nada": el menú aplica como respaldo
  // `pantallasPermitidasEmpleadoPorDefecto` (ver core/utils/permisos_modulo
  // .dart); para Encargado un mapa vacío sí significa "sin acceso a nada",
  // tal cual funcionaba antes.
  final Map<String, bool> pantallasPermitidas;
  final Map<String, bool> accionesPermitidas;

  UsuarioModel({
    required this.id,
    required this.documento,
    required this.nombreCompleto,
    required this.correo,
    required this.rol,
    required this.estado,
    this.pantallasPermitidas = const {},
    this.accionesPermitidas = const {},
  });

  factory UsuarioModel.fromMap(String id, Map<String, dynamic> data) {
    return UsuarioModel(
      id: id,
      documento: data['documento'] ?? '',
      nombreCompleto: data['nombre_completo'] ?? '',
      correo: data['correo'] ?? '',
      rol: data['rol'] ?? '',
      estado: data['estado'] ?? true,
      pantallasPermitidas: Map<String, bool>.from(data['pantallas_permitidas'] ?? {}),
      accionesPermitidas: Map<String, bool>.from(data['acciones_permitidas'] ?? {}),
    );
  }
}
