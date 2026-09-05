import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/roles.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Gate de acciones ad-hoc del rol Encargado: a diferencia de
/// `verificarAccesoEspecial` (clave especial compartida), esto no pide
/// ninguna clave — simplemente decide si el usuario logueado puede ver el
/// botón de una acción (crear/editar/eliminar) según lo que el
/// Administrador le haya marcado en `accionesPermitidas` al crearlo.
///
/// - Administrador: siempre true, sin excepción.
/// - Encargado: solo true si `accionesPermitidas[accionKey] == true`.
/// - Empleado/Semi Administrador: true (sin restricción ad-hoc nueva; para
///   ellos sigue rigiendo únicamente el flujo de clave especial existente de
///   `PermisosEspeciales`, que esta función no reemplaza).
bool puedeRealizarAccion(WidgetRef ref, String accionKey) {
  final usuario = ref.read(authProvider).usuario;
  if (usuario == null) return false;
  if (usuario.rol == Roles.administrador) return true;
  if (usuario.rol == Roles.encargado) return usuario.accionesPermitidas[accionKey] == true;
  return true;
}
