import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';

/// Sesiones cortas para usar el celular como lector de código de barras de
/// una venta que se está armando en la PC: la PC genera un código, lo
/// muestra como QR, y cada código que el celular escanea (sin necesidad de
/// iniciar sesión en la app) se manda a la tabla `escaneo_remoto_eventos` de
/// esa sesión, que la PC escucha en vivo con Supabase Realtime.
///
/// Ver el comentario junto a `escaneo_remoto_eventos`/`escaneos_remotos` en
/// supabase/schema.sql: el diseño original del esquema dejaba esto
/// explícitamente FUERA (recomendaba un canal de Realtime puro -broadcast/
/// presence-, sin fila de Postgres, por ser sesiones de segundos de vida).
/// Se optó en cambio por estas 2 tablas chicas y efímeras (con RLS abierto y
/// agregadas a la publicación `supabase_realtime`) para reusar el mismo
/// patrón `.stream()` que ya usa el resto de los repositorios de esta app,
/// en vez de una reimplementación sobre broadcast/presence sin poder
/// probarla en este entorno. Si el volumen de sesiones efímeras llegara a
/// ser un problema (no debería: se borran solas al terminar cada venta),
/// migrar esto a un canal puro queda como mejora futura.
class EscaneoRemotoRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  // Sin caracteres ambiguos (0/O, 1/I/L) para que sea fácil de leer/tipear a
  // mano si hiciera falta.
  static const _caracteres = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String generarCodigo() {
    final azar = Random.secure();
    return List.generate(
      6,
      (_) => _caracteres[azar.nextInt(_caracteres.length)],
    ).join();
  }

  Future<void> crearSesion(String codigo) {
    return conRed(() => _db.from('escaneos_remotos').insert({'codigo': codigo}));
  }

  Future<bool> existeSesion(String codigo) {
    return conRed(() async {
      final filas = await _db.from('escaneos_remotos').select('codigo').eq('codigo', codigo).limit(1);
      return filas.isNotEmpty;
    });
  }

  /// El celular se suscribe a esto (en vez de solo comprobar una vez al
  /// abrir) para enterarse al instante si la sesión terminó de verdad
  /// (`eliminarSesion`, al tocar "Finalizar escaneo" o cerrar la pestaña de
  /// venta): recién ahí el celular deja de mandar códigos, aunque la cámara
  /// siga abierta.
  Stream<bool> existeSesionEnVivo(String codigo) {
    return conRedStream(
      () => _db.from('escaneos_remotos').stream(primaryKey: ['codigo']).eq('codigo', codigo),
    ).map((filas) => filas.isNotEmpty);
  }

  /// El celular marca esto apenas confirma la sesión y muestra la cámara,
  /// para que la PC sepa que ya se emparejó y pueda cerrar solo la ventanita
  /// del QR (sin necesidad de que el usuario la cierre a mano).
  Future<void> marcarConectado(String codigo) {
    return conRed(() => _db.from('escaneos_remotos').update({'conectado': true}).eq('codigo', codigo));
  }

  Stream<bool> escucharConectado(String codigo) {
    return conRedStream(
      () => _db.from('escaneos_remotos').stream(primaryKey: ['codigo']).eq('codigo', codigo),
    ).map((filas) => filas.isNotEmpty && (filas.first['conectado'] as bool? ?? false));
  }

  Future<void> enviarCodigo(String codigoSesion, String codigoEscaneado) {
    return conRed(
      () => _db.from('escaneo_remoto_eventos').insert({'codigo': codigoSesion, 'valor': codigoEscaneado}),
    );
  }

  /// Lista completa (en vivo) de eventos de la sesión -EscaneoActivoDialog
  /// solo la usa para mostrar un contador de cuántos códigos van escaneados-.
  Stream<List<Map<String, dynamic>>> escucharEventos(String codigoSesion) {
    return conRedStream(
      () => _db.from('escaneo_remoto_eventos').stream(primaryKey: ['id']).eq('codigo', codigoSesion).order('fecha'),
    );
  }

  /// Emite CADA código nuevo escaneado, uno a la vez, apenas llega -antes se
  /// lograba filtrando `docChanges`/`DocumentChangeType.added` de Firestore
  /// sobre la lista completa; acá se logra recordando (dentro de esta misma
  /// suscripción) qué ids ya se vieron sobre el mismo stream de
  /// [escucharEventos]-.
  Stream<String> escucharCodigosNuevos(String codigoSesion) {
    final vistos = <String>{};
    return escucharEventos(codigoSesion).expand(
      (filas) => [
        for (final fila in filas)
          if (vistos.add(fila['id'] as String)) fila['valor'] as String,
      ],
    );
  }

  /// Se llama al cerrar el diálogo de escaneo en la PC: borra la sesión (los
  /// eventos se van solos por `on delete cascade`, ver supabase/schema.sql)
  /// para no dejar basura acumulándose.
  Future<void> eliminarSesion(String codigo) {
    return conRed(() => _db.from('escaneos_remotos').delete().eq('codigo', codigo));
  }
}
