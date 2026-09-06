import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import '../widgets/configuracion_apartado.dart';
import '../../../ventas/presentation/widgets/buscar_producto_dialog.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

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

  Future<void> _agregarProducto() async {
    final elegido = await showDialog<ProductoConPrecio>(
      useRootNavigator: false,
      context: context,
      builder: (context) => const BuscarProductoDialog(),
    );
    if (elegido == null || !mounted) return;
    final disponible = await ref.read(apartadoRepositoryProvider).obtenerDisponible(elegido.producto.id).catchError((_) => elegido.producto.stock);
    if (!mounted) return;
    final cantidad = await _pedirCantidad(elegido.producto.nombre, disponible);
    if (cantidad == null || cantidad <= 0) return;
    if (cantidad > disponible) {
      final continuar = await _confirmarSobreDisponible(elegido.producto.nombre, disponible, cantidad);
      if (continuar != true || !mounted) return;
    }
    setState(() {
      _items.add(NuevoItemApartado(
        idProducto: elegido.producto.id,
        nombreProducto: elegido.producto.nombre,
        cantidad: cantidad,
        precioUnitario: elegido.precio,
      ));
    });
  }

  Future<double?> _pedirCantidad(String nombreProducto, double disponible) async {
    final controller = TextEditingController(text: '1');
    final resultado = await showDialog<double>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cantidad a apartar', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nombreProducto, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              'Disponible (sin contar lo ya apartado): ${disponible.toStringAsFixed(disponible == disponible.roundToDouble() ? 0 : 2)}',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 14),
            CampoTecladoCompacto(
              controller: controller,
              numerico: true,
              titulo: 'Cantidad',
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  labelStyle: GoogleFonts.poppins(fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFE8EAF0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D)),
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text.replaceAll(',', '').trim())),
            child: Text('Agregar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    controller.dispose();
    return resultado;
  }

  Future<bool?> _confirmarSobreDisponible(String nombreProducto, double disponible, double cantidad) {
    return showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Existencia insuficiente', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          '"$nombreProducto" solo tiene ${disponible.toStringAsFixed(2)} disponible (contando lo que ya está apartado por otros clientes), pero se está pidiendo $cantidad. '
          'Si continuás, el sistema va a rechazar el apartado al guardar si ya no alcanza.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar', style: GoogleFonts.poppins())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D)),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Agregar de todas formas', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _quitarItem(int index) => setState(() => _items.removeAt(index));

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
    return tarjetaApartado(
      titulo: 'Productos',
      accion: OutlinedButton.icon(
        onPressed: _agregarProducto,
        icon: const Icon(Icons.add, size: 18),
        label: Text('Agregar producto', style: GoogleFonts.poppins(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0F1B3D),
          side: const BorderSide(color: Color(0xFF0F1B3D)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      child: _items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Todavía no agregaste ningún producto', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
            )
          : Column(
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  _filaItem(i, _items[i]),
                ],
              ],
            ),
    );
  }

  Widget _filaItem(int index, NuevoItemApartado item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text('x${item.cantidad.toStringAsFixed(item.cantidad == item.cantidad.roundToDouble() ? 0 : 2)}', style: GoogleFonts.poppins(fontSize: 13)),
          ),
          Expanded(
            child: Text(formatearMoneda(item.precioUnitario), style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(formatearMoneda(item.subtotal), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
            onPressed: () => _quitarItem(index),
          ),
        ],
      ),
    );
  }
}
