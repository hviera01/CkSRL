import 'package:supabase_flutter/supabase_flutter.dart';

/// Igual que PresenciaImpresionRepository, pero para saber si la tarea
/// programada `tool/aviso_creditos_whatsapp/escuchar.js` sigue corriendo en
/// la PC principal -es quien de verdad manda el WhatsApp cuando se toca
/// "Enviar estado de cuenta por WhatsApp"; la app Flutter solo deja marcado
/// el pedido en el crédito (ver VentaCreditoRepository.solicitarAvisoWhatsApp).
/// Sin esta señal, si la tarea programada se desactivó o dejó de correr, el
/// botón "funciona" (no tira error) pero no manda nada y no hay forma de
/// saber por qué.
///
/// A diferencia de PresenciaImpresionRepository (la PC manda un latido cada
/// 25s MIENTRAS la app está abierta), acá `escuchar.js` NO se queda
/// corriendo: el Programador de Tareas de Windows lo dispara, manda su
/// latido, y termina -pensado para correr cada 2 minutos (ver README de esa
/// carpeta)-, así que el umbral tiene que ser bastante mayor a ese intervalo
/// para no marcar "desconectado" solo porque todavía no le tocó la próxima
/// corrida.
///
/// Comparte la tabla `presencia` con PresenciaImpresionRepository (ver
/// comentario en supabase/schema.sql): esta fila usa el id
/// 'aviso_whatsapp_escuchador', distinto del 'pc_principal' de la otra, así
/// que un latido no pisa al otro.
///
/// OJO: `tool/aviso_creditos_whatsapp` (el `escuchar.js` que mandaba el
/// latido de verdad) ya NO existe en este repo -se quitó por completo junto
/// con el resto de automatizaciones de WhatsApp específicas de Super Color
/// (cuentas bancarias/teléfonos reales, ver commit "Quita las
/// automatizaciones de WhatsApp de Super Color..."). Nada va a escribir
/// nunca en esta fila para Ck, así que `estaConectado()` siempre va a dar
/// `false` y el botón "Enviar estado de cuenta por WhatsApp" en
/// VentasCreditoScreen va a mostrar siempre el aviso de "no se pudo
/// confirmar" -queda pendiente decidir si esa función se reconstruye para
/// Ck con datos propios, o si se quita del todo el botón (ver reporte de la
/// tarea)-.
class PresenciaAvisoWhatsappRepository {
  static const umbralConectada = Duration(minutes: 4);
  static const _id = 'aviso_whatsapp_escuchador';

  final _db = Supabase.instance.client;

  Future<bool> estaConectado() async {
    try {
      final filas = await _db
          .from('presencia')
          .select('ultimo_latido')
          .eq('id', _id)
          .limit(1);
      if (filas.isEmpty) return false;
      final texto = filas.first['ultimo_latido'] as String?;
      if (texto == null) return false;
      return DateTime.now().difference(DateTime.parse(texto)) < umbralConectada;
    } catch (_) {
      return false;
    }
  }
}
