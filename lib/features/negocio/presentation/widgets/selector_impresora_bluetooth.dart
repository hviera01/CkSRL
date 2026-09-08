import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../../core/services/impresora_bluetooth_service.dart';

/// Impresión térmica Bluetooth: solo tiene sentido en Android (donde a veces
/// se conecta la impresora por cable/Bluetooth en vez de por red WiFi -pedido
/// explícito del dueño-). En Windows/macOS/Linux ya existe el listado de
/// impresoras del sistema (ver SelectorImpresora); en iOS/web no hay una vía
/// Bluetooth que no necesite este mismo plugin nativo, así que se deja fuera
/// por ahora (no pedido).
bool get _bluetoothDisponibleAca => !kIsWeb && Platform.isAndroid;

/// Selector de impresora térmica Bluetooth para Negocio (mismo patrón que
/// SelectorImpresora, pero listando dispositivos YA EMPAREJADOS por Android
/// en vez de impresoras del sistema operativo -ver ImpresoraBluetoothService-).
/// Guarda la dirección mac (id) y el nombre elegidos en NegocioModel
/// (impresoraBluetoothId/impresoraBluetoothNombre); [onSeleccionar] los
/// persiste en Supabase igual que el resto de selectores de esta pantalla.
class SelectorImpresoraBluetooth extends StatefulWidget {
  final String idActual;
  final String nombreActual;
  final void Function(String id, String nombre) onSeleccionar;

  const SelectorImpresoraBluetooth({
    super.key,
    required this.idActual,
    required this.nombreActual,
    required this.onSeleccionar,
  });

  @override
  State<SelectorImpresoraBluetooth> createState() => _SelectorImpresoraBluetoothState();
}

class _SelectorImpresoraBluetoothState extends State<SelectorImpresoraBluetooth> {
  final _servicio = ImpresoraBluetoothService();
  List<BluetoothInfo> _dispositivos = [];
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDispositivos();
  }

  Future<void> _cargarDispositivos() async {
    if (!_bluetoothDisponibleAca) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final encendido = await _servicio.bluetoothEncendido();
      if (!encendido) {
        if (mounted) setState(() => _error = 'El Bluetooth está apagado en este dispositivo');
        return;
      }
      final lista = await _servicio.listarEmparejadas();
      if (mounted) setState(() => _dispositivos = lista);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo obtener la lista de dispositivos Bluetooth');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneActual = widget.idActual.isNotEmpty;

    if (!_bluetoothDisponibleAca) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Impresora térmica Bluetooth', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          Text(
            'Solo disponible desde el celular/tablet con Android (la app de escritorio ya lista las impresoras del sistema arriba, y el navegador no da acceso a Bluetooth).',
            style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
          ),
        ],
      );
    }

    final opciones = [..._dispositivos];
    if (tieneActual && !opciones.any((d) => d.macAdress == widget.idActual)) {
      opciones.insert(0, BluetoothInfo(name: '${widget.nombreActual} (no emparejada)', macAdress: widget.idActual));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Impresora térmica Bluetooth', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A)))),
            IconButton(
              tooltip: 'Actualizar lista',
              onPressed: _cargando ? null : _cargarDispositivos,
              icon: _cargando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Emparejá la impresora desde los ajustes de Bluetooth de Android primero; acá solo se eligen dispositivos ya emparejados.',
          style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              hint: Text('Sin impresora Bluetooth seleccionada', style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
              value: tieneActual ? widget.idActual : null,
              style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
              items: opciones.map((d) => DropdownMenuItem(value: d.macAdress, child: Text(d.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (mac) {
                if (mac == null) return;
                final dispositivo = opciones.firstWhere((d) => d.macAdress == mac);
                widget.onSeleccionar(dispositivo.macAdress, dispositivo.name);
              },
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.red.shade700)),
        ] else if (!_cargando && _dispositivos.isEmpty) ...[
          const SizedBox(height: 4),
          Text('No se detectó ninguna impresora Bluetooth emparejada', style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500)),
        ],
        if (tieneActual) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => widget.onSeleccionar('', ''),
            icon: const Icon(Icons.link_off, size: 16),
            label: Text('Quitar impresora Bluetooth', style: GoogleFonts.poppins(fontSize: 12.5)),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0F1B3D), padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
          ),
        ],
      ],
    );
  }
}
