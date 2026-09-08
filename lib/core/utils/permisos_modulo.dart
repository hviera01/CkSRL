import '../constants/roles.dart';
import '../data/modulos_menu.dart';
import '../../features/auth/data/usuario_model.dart';

/// Único lugar que decide si un usuario puede ver [s] en el menú -antes esta
/// regla vivía duplicada (y desincronizada) entre `SideMenu` y `HomeScreen`:
/// `HomeScreen` ni siquiera aplicaba el filtro de `pantallasPermitidas` de
/// Encargado, solo el de `soloAdmin`-.
///
/// - Administrador: ve todo, siempre.
/// - Encargado: solo lo que el Administrador le marcó en `pantallasPermitidas`
///   al crearlo/editarlo (sin valor por defecto: si no se le marcó nada, no
///   ve nada, tal cual funcionaba antes de este cambio).
/// - Empleado: mismo mecanismo que Encargado (`pantallasPermitidas`,
///   personalizable por usuario), pero CON valor por defecto -corrige el bug
///   reportado por el dueño, "Empleado tiene acceso a todo"-: si el usuario
///   todavía no tiene `pantallasPermitidas` configurado (usuarios creados
///   antes de este cambio, o cualquiera al que nunca se le tocó nada), se usa
///   `pantallasPermitidasEmpleadoPorDefecto` (mismo acceso por defecto que
///   tiene este rol en `variedades_lopsi`) en vez de dejarlo sin ver nada.
/// - Semi Administrador: sigue exactamente igual que antes (`!soloAdmin`),
///   sin cambios de este pedido.
bool puedeVerSubModulo(UsuarioModel? usuario, SubModulo s) {
  final rol = usuario?.rol ?? Roles.empleado;
  if (rol == Roles.administrador) return true;
  if (rol == Roles.encargado) {
    return usuario?.pantallasPermitidas[s.moduleKey] == true;
  }
  if (rol == Roles.empleado) {
    final tieneConfiguracion = usuario?.pantallasPermitidas.isNotEmpty == true;
    if (tieneConfiguracion) {
      return usuario?.pantallasPermitidas[s.moduleKey] == true;
    }
    return pantallasPermitidasEmpleadoPorDefecto.contains(s.moduleKey);
  }
  return !s.soloAdmin;
}
