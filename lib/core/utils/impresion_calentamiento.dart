import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';

/// Se llama justo ANTES de cada `Printing.directPrintPdf` real (ticket por
/// el driver oficial de Windows, ver ImpresionEnVivoService/
/// ImpresionPendienteService/PdfPreviewDialog/RegistrarVentaScreen) -no solo
/// una vez al abrir la app (ver AppShell._calentarImpresion, que cubre el
/// arranque, pero no un equipo que estuvo horas inactivo, salió de
/// suspensión, o cualquier otro motivo por el que el driver quede
/// "desincronizado" otra vez-.
///
/// Reportado por el dueño: la impresión remota (celular -> PC principal)
/// salió con el ticket bien pero con un tramo largo de papel en blanco antes
/// de cortar; reimprimir local ahí mismo después salió perfecto. Mismo
/// mecanismo en ambos casos -Printing.directPrintPdf con un PdfPageFormat
/// propio, no el que reporte el driver, ver venta_export_service.dart-, así
/// que la diferencia no está en qué se le pide al driver sino en si el
/// plugin de impresión de Windows ya negoció el tamaño de página real con
/// el driver antes de ese trabajo puntual. Esta consulta (no imprime nada,
/// solo lista impresoras) fuerza esa negociación de nuevo cada vez, para no
/// depender de que haya "calentado" antes por otro motivo.
///
/// Devuelve `true` si se pudo consultar la lista de impresoras de Windows
/// (o si no aplica, ver [kIsWeb]/[Platform.isWindows]) y ENCONTRAR el nombre
/// configurado en ella -si no responde a tiempo, tira un error, o la
/// impresora configurada ya no aparece en la lista (apagada, desconectada,
/// nombre cambiado), devuelve `false`-.
///
/// Pedido explícito del dueño tras el problema real: "si lo va a tirar mal
/// mejor que no tire nada". No hay forma de que la app sepa cuánto papel
/// salió de verdad -Windows no le devuelve ese dato-, así que esto no
/// garantiza que el resultado salga perfecto, pero si ni siquiera esta
/// consulta liviana (no imprime nada) responde bien, hay bajísima confianza
/// de que el trabajo real vaya a salir bien: mejor no intentarlo y dejarlo
/// pendiente (ver los `if (!await calentarImpresionWindows()) return false;`
/// antes de cada Printing.directPrintPdf real) que arriesgarse a gastar
/// papel sin necesidad.
Future<bool> calentarImpresionWindows({String? nombreImpresora}) async {
  if (kIsWeb || !Platform.isWindows) return true;
  try {
    final impresoras = await Printing.listPrinters().timeout(const Duration(seconds: 3));
    if (nombreImpresora == null || nombreImpresora.isEmpty) return true;
    return impresoras.any((p) => p.name == nombreImpresora);
  } catch (_) {
    return false;
  }
}
