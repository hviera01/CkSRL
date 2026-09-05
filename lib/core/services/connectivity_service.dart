import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expone si el dispositivo tiene conexión a internet, en vivo. A diferencia
/// de Firestore (que tiene caché/persistencia offline nativa y "disimulaba"
/// la falta de red), Supabase no tiene nada de eso: sin este aviso, un cajero
/// sin internet no se entera de que una acción falló hasta que revisa el
/// resultado -o, peor, ni eso, si el error quedaba tragado en un catch
/// silencioso (ver SinConexionException en core/data/base_repository.dart).
class ConnectivityService {
  final _connectivity = Connectivity();

  /// `true` = hay alguna conexión de red (no garantiza que haya internet de
  /// verdad -un wifi sin salida real también cuenta como "conectado" para
  /// connectivity_plus-, pero alcanza para el aviso pasivo: distingue el caso
  /// más común, "no hay red del todo", que es el que de verdad deja a un
  /// cajero varado sin saberlo).
  Stream<bool> get estadoConexion {
    return _connectivity.onConnectivityChanged.map(_hayConexion);
  }

  Future<bool> tieneConexionAhora() async {
    final resultado = await _connectivity.checkConnectivity();
    return _hayConexion(resultado);
  }

  bool _hayConexion(List<ConnectivityResult> resultados) {
    return resultados.any((r) => r != ConnectivityResult.none);
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

/// `true` = hay conexión. Arranca en `true` (optimista) mientras se resuelve
/// la primera lectura real, para no mostrar el banner de "sin conexión" un
/// instante de más apenas abre la app.
final conectividadProvider = StreamProvider<bool>((ref) {
  final servicio = ref.watch(connectivityServiceProvider);
  return servicio.estadoConexion.startWith(true);
});

extension _StartWith on Stream<bool> {
  Stream<bool> startWith(bool valorInicial) async* {
    yield valorInicial;
    yield* this;
  }
}
