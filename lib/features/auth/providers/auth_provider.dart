import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/auth_repository.dart';
import '../data/usuario_model.dart';
import '../../../core/providers/tabs_provider.dart';
import '../../negocio/providers/negocio_provider.dart';

final authRepositoryProvider = Provider((ref) => AuthRepository());

class AuthState {
  final UsuarioModel? usuario;
  final bool cargando;
  final String? error;

  AuthState({this.usuario, this.cargando = false, this.error});
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState();
  }

  Future<void> login(String documento, String clave) async {
    state = AuthState(cargando: true);
    try {
      final usuario = await ref.read(authRepositoryProvider).login(documento, clave);
      state = AuthState(usuario: usuario);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usuario_id', usuario.id);

      // Precarga (sin esperar) la configuración del negocio para que, una
      // vez adentro, acciones como pedir la clave especial o abrir el
      // código de barras no tengan que esperar la primera ida y vuelta a
      // Firestore: ya quedó resuelta durante el login.
      unawaited(ref.read(negocioRepositoryProvider).obtenerNegocioActual());
    } catch (e) {
      state = AuthState(error: e.toString().replaceAll('Exception: ', ''));
    }
  }

 Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('usuario_id');
    state = AuthState();
    ref.invalidate(tabsProvider);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);