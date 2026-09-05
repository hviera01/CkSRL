import 'dart:async';
import 'dart:io';
import 'package:postgrest/postgrest.dart';

/// Se relanza en vez del error genérico/silencioso de Supabase cuando una
/// operación falla específicamente por falta de red (no por otro tipo de
/// error -permiso, dato inválido, restricción de la base, etc-). Las
/// pantallas que ya muestran errores (SnackBar/diálogo) pueden chequear
/// `if (e is SinConexionException)` para mostrar un mensaje claro en vez del
/// genérico -ver README de la migración en el reporte de la tarea para la
/// lista de pantallas que ya lo hacen vs. las que quedaron pendientes-.
class SinConexionException implements Exception {
  final String mensaje;
  const SinConexionException([this.mensaje = 'Sin conexión a internet']);

  @override
  String toString() => mensaje;
}

/// Mixin para los repositorios de datos: envuelve cualquier operación contra
/// Supabase (tabla, RPC, Realtime) para relanzar errores de red como
/// [SinConexionException] en vez del error crudo de Supabase/socket -que
/// hoy, en toda la familia de apps, se traga silencioso en un catch genérico
/// o se muestra como un mensaje técnico que no le dice nada al cajero-.
///
/// Uso: `Future<T> algo() => conRed(() async { ... });` en vez de llamar a
/// Supabase directo. Los streams (`.stream()` de Realtime) no pasan por acá
/// -no hay un "resultado" puntual que envolver-, pero si su primer error los
/// deja sin reintentar, `conRedStream` los envuelve para transformar ese
/// error también.
mixin ConRedMixin {
  Future<T> conRed<T>(Future<T> Function() operacion) async {
    try {
      return await operacion();
    } catch (e) {
      throw _traducirError(e);
    }
  }

  Stream<T> conRedStream<T>(Stream<T> Function() operacion) {
    late StreamController<T> controller;
    StreamSubscription<T>? suscripcion;
    controller = StreamController<T>(
      onListen: () {
        suscripcion = operacion().listen(
          controller.add,
          onError: (Object e, StackTrace st) => controller.addError(_traducirError(e), st),
          onDone: controller.close,
        );
      },
      onCancel: () => suscripcion?.cancel(),
    );
    return controller.stream;
  }

  Object _traducirError(Object e) {
    if (e is SinConexionException) return e;
    if (_esErrorDeRed(e)) return const SinConexionException();
    return e;
  }

  bool _esErrorDeRed(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    // PostgrestException con código nulo/vacío suele ser el envoltorio que
    // deja Supabase cuando el fetch de verdad nunca llegó a responder (sin
    // red) — con respuesta real del servidor siempre viene un código Postgres.
    if (e is PostgrestException && (e.code == null || e.code!.isEmpty)) return true;
    final texto = e.toString().toLowerCase();
    return texto.contains('socketexception') ||
        texto.contains('failed host lookup') ||
        texto.contains('network is unreachable') ||
        texto.contains('connection failed') ||
        texto.contains('connection closed') ||
        texto.contains('clientexception') ||
        texto.contains('sin conexión');
  }
}
