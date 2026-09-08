import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Envío de tickets ESC/POS a una impresora térmica conectada por Bluetooth
/// (Android; ver NegocioModel.impresoraBluetoothId/SelectorImpresoraBluetooth).
/// Mismo criterio que ImpresoraRedService: nunca lanza, devuelve `false` ante
/// cualquier error (impresora apagada, fuera de alcance, mac inválida, etc.)
/// para que quien llama decida el siguiente respaldo (impresora de red,
/// impresión remota vía PC principal, o dejarla pendiente) sin que la venta
/// se bloquee -ver RegistrarVentaScreen._imprimirEscPosRed-.
///
/// Solo usa dispositivos YA EMPAREJADOS (ver [listarEmparejadas],
/// `PrintBluetoothThermal.pairedBluetooths`): no escanea dispositivos nuevos
/// alrededor, así que no hace falta permiso de ubicación (ver el comentario
/// en AndroidManifest.xml).
class ImpresoraBluetoothService {
  /// Dispositivos Bluetooth ya emparejados en este equipo (para el selector
  /// en Negocio). Lista vacía si el Bluetooth está apagado, no hay ninguno
  /// emparejado, o falla la consulta -nunca lanza-.
  Future<List<BluetoothInfo>> listarEmparejadas() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return const [];
    }
  }

  /// `true` si el Bluetooth del equipo está encendido. Se usa antes de listar
  /// para mostrar un aviso más claro que "no se encontró ninguna" cuando en
  /// realidad el Bluetooth está apagado.
  Future<bool> bluetoothEncendido() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Se conecta (si hace falta) e imprime [bytes] en la impresora Bluetooth
  /// con dirección [macAddress]. Nunca lanza: cualquier falla (impresora
  /// apagada/fuera de alcance/desemparejada, Bluetooth apagado, permiso no
  /// concedido) devuelve `false`.
  Future<bool> imprimir({required String macAddress, required List<int> bytes}) async {
    if (macAddress.trim().isEmpty) return false;
    try {
      final conectado = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress.trim());
      if (!conectado) return false;
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }
}
