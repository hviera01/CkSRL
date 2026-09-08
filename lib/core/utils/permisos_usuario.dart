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
/// - Encargado: solo true si `accionesPermitidas[accionKey] == true` (sin
///   valor por defecto: un mapa vacío es "no puede nada de esto").
/// - Empleado: personalizable igual que Encargado, pero solo si el
///   Administrador de verdad le tocó algo en "Acciones permitidas" del
///   formulario (`accionesPermitidas` no vacío) -así un Empleado al que
///   nunca se le configuró nada sigue exactamente igual que antes de este
///   mecanismo: sin restricción ad-hoc nueva-. Distinto de `pantallasPermitidas`
///   (ver core/utils/permisos_modulo.dart), acá no hay un "valor por defecto
///   de Lopsi" para acciones: solo aplica cuando el Administrador lo pidió.
/// - Semi Administrador: true (sin restricción ad-hoc nueva; para ellos y
///   para un Empleado sin configurar sigue rigiendo únicamente el flujo de
///   clave especial existente de `PermisosEspeciales`, que esta función no
///   reemplaza).
bool puedeRealizarAccion(WidgetRef ref, String accionKey) {
  final usuario = ref.read(authProvider).usuario;
  if (usuario == null) return false;
  if (usuario.rol == Roles.administrador) return true;
  if (usuario.rol == Roles.encargado) return usuario.accionesPermitidas[accionKey] == true;
  if (usuario.rol == Roles.empleado && usuario.accionesPermitidas.isNotEmpty) {
    return usuario.accionesPermitidas[accionKey] == true;
  }
  return true;
}
