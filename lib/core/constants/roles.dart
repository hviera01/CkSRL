class Roles {
  static const administrador = 'Administrador';
  static const semiAdministrador = 'Semi Administrador';
  static const empleado = 'Empleado';
  // Rol con permisos ad-hoc por usuario (pantallas y acciones elegidas a
  // mano por el Administrador al crearlo): no tiene nivel dentro de la
  // jerarquía de cumpleNivel, se evalúa aparte (ver side_menu.dart y
  // core/utils/permisos_usuario.dart).
  static const encargado = 'Encargado';

  static const List<String> todos = [administrador, semiAdministrador, empleado, encargado];

  static int _nivel(String rol) {
    switch (rol) {
      case administrador:
        return 2;
      case semiAdministrador:
        return 1;
      default:
        return 0;
    }
  }

  /// true si [rolUsuario] tiene al menos el nivel de [rolMinimo] (Empleado <
  /// Semi Administrador < Administrador).
  static bool cumpleNivel(String rolUsuario, String rolMinimo) => _nivel(rolUsuario) >= _nivel(rolMinimo);
}
