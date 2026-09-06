import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import '../widgets/configuracion_apartado.dart';
import '../widgets/editor_productos_apartado.dart';

/// Pantalla completa (push, no diálogo chico) para armar un apartado nuevo:
/// elegir cliente, agregar productos (reusando BuscarProductoDialog, igual
/// que Registrar Venta), definir el pago inicial (% o monto fijo) y la
/// modalidad de pago del resto -cuotas fijas (con vista previa de las
/// cuotas) o abonos libres-.
///
/// Todo lo que no son los productos (cliente / pago inicial / modalidad /
/// cuotas) vive en ConfiguracionApartadoForm, compartido con
/// ApartarCarritoDialog -la otra entrada al mismo flujo, desde Registrar
/// Venta con el carrito ya armado-.
class CrearApartadoScreen extends ConsumerStatefulWidget {
  const CrearApartadoScreen({super.key});

  @override
  ConsumerState<CrearApartadoScreen> createState() => _CrearApartadoScreenState();
}

class _CrearApartadoScreenState extends ConsumerState<CrearApartadoScreen> {
  final _config = ConfiguracionApartadoController();

  final List<NuevoItemApartado> _items = [];

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _config.dispose();
    super.dispose();
  }

  double get _montoTotal => _items.fold<double>(0, (s, i) => s + i.subtotal);

  void _actualizarItems(List<NuevoItemApartado> nuevaLista) {
    setState(() {
      _items
        ..clear()
        ..addAll(nuevaLista);
    });
  }

  Future<void> _guardar() async {
    if (_items.isEmpty) {
      setState(() => _error = 'Agregá al menos un producto');
      return;
    }
    final error = _config.validar(_montoTotal);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apartadoRepositoryProvider).crearApartado(
            idCliente: _config.idCliente,
            nombreCliente: _config.nombreCliente,
            montoInicial: _config.montoInicialSobre(_montoTotal),
            montoInicialReal: _config.montoInicialReal,
            metodoPagoInicial: _config.montoInicialReal > 0.009 ? _config.metodoPagoInicial : null,
            modalidad: _config.modalidad,
            items: _items,
            cuotas: _config.cuotasSobre(_montoTotal),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(esMovil ? 14 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Nuevo Apartado', style: GoogleFonts.poppins(fontSize: esMovil ? 18 : 21, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConfiguracionApartadoForm(
                        controller: _config,
                        montoTotal: _montoTotal,
                        alCambiar: () => setState(() {}),
                        seccionProductos: _tarjetaProductos(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        errorApartado(_error!),
                      ],
                      const SizedBox(height: 90),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Spacer(),
              TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F1B3D),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                    : Text('Guardar Apartado', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaProductos() {
    return EditorProductosApartado(items: _items, alCambiar: _actualizarItems);
  }
}
