import 'package:supabase_flutter/supabase_flutter.dart';

/// Le permite a la PC principal (la que tiene la impresora térmica
/// conectada) avisar que está viva mientras la app está abierta, para que
/// una venta hecha desde el celular sepa si vale la pena pedirle que
/// imprima en el momento en vez de dejarla directamente pendiente.
///
/// Postgres no tiene una noción nativa de presencia -a diferencia de
/// Realtime Database con `onDisconnect`-, así que se simula con un latido
/// periódico igual que antes: si el último latido es reciente, se asume que
/// la PC sigue conectada. Ver AppShell (quien envía el latido) y
/// RegistrarVentaScreen (quien lo consulta antes de pedir impresión en vivo).
class PresenciaImpresionRepository {
  static const umbralConectada = Duration(seconds: 40);
  static const _id = 'pc_principal';

  final _db = Supabase.instance.client;

  Future<void> enviarLatido() async {
    try {
      await _db.from('presencia').upsert({'id': _id, 'ultimo_latido': DateTime.now().toIso8601String()});
    } catch (_) {
      // Best-effort: si falla (sin internet justo en ese instante), el
      // próximo latido -unos segundos después- lo vuelve a intentar.
    }
  }

  Future<bool> estaConectada() async {
    try {
      final filas = await _db.from('presencia').select('ultimo_latido').eq('id', _id).limit(1);
      if (filas.isEmpty) return false;
      final texto = filas.first['ultimo_latido'] as String?;
      if (texto == null) return false;
      return DateTime.now().difference(DateTime.parse(texto)) < umbralConectada;
    } catch (_) {
      return false;
    }
  }
}
