import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import '../../../ventas/presentation/widgets/buscar_producto_dialog.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import 'configuracion_apartado.dart' show tarjetaApartado;

/// Lista editable de productos de un apartado -misma libertad que la tabla
/// de Registrar Venta (registrar_venta_screen.dart): cantidad y precio
/// editables en línea, más "Agregar Producto" siempre disponible antes de
/// confirmar-, pedido explícito del dueño tras probar el módulo. Antes cada
/// pantalla (CrearApartadoScreen y ApartarCarritoDialog) tenía su propia
/// lista de solo lectura -con únicamente un botón de quitar-: ahora las dos
/// usan este mismo widget, dueño de su propia lógica de agregar/editar/
/// quitar (el llamador solo guarda la lista vía [alCambiar] y la vuelve a
/// pasar en el próximo build).
///
/// No tiene descuento por línea -a diferencia de ItemVentaModel, un apartado
/// nunca lo tuvo (ver NuevoItemApartado)-, así que acá solo se edita
/// cantidad y precio unitario.
class EditorProductosApartado extends ConsumerStatefulWidget {
  final List<NuevoItemApartado> items;
  final ValueChanged<List<NuevoItemApartado>> alCambiar;
  // Clave opcional del tutorial guiado (ver crear_apartado_screen.dart) para
  // el botón "Agregar producto".
  final GlobalKey? claveAgregarProducto;

  const EditorProductosApartado({super.key, required this.items, required this.alCambiar, this.claveAgregarProducto});

  @override
  ConsumerState<EditorProductosApartado> createState() => _EditorProductosApartadoState();
}

class _EditorProductosApartadoState extends ConsumerState<EditorProductosApartado> {
  // Controladores de los campos inline, por índice -se limpian enteros cada
  // vez que la lista cambia de tamaño (agregar/quitar), para no arrastrar un
  // controlador a un índice que ahora es otro producto; una edición de
  // cantidad/precio en el mismo índice, en cambio, los deja intactos (así el
  // usuario puede seguir tipeando sin que se le reinicie el campo).
  final Map<int, TextEditingController> _ctrlCantidad = {};
  final Map<int, TextEditingController> _ctrlPrecio = {};

  @override
  void dispose() {
    _disposeControladores();
    super.dispose();
  }

  void _disposeControladores() {
    for (final c in _ctrlCantidad.values) {
      c.dispose();
    }
    for (final c in _ctrlPrecio.values) {
      c.dispose();
    }
    _ctrlCantidad.clear();
    _ctrlPrecio.clear();
  }

  String _formatoCantidad(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

  void _actualizarItem(int index, {double? cantidad, double? precioUnitario}) {
    final actual = widget.items[index];
    final nuevo = NuevoItemApartado(
      idProducto: actual.idProducto,
      nombreProducto: actual.nombreProducto,
      cantidad: cantidad ?? actual.cantidad,
      precioUnitario: precioUnitario ?? actual.precioUnitario,
    );
    final lista = [...widget.items];
    lista[index] = nuevo;
    widget.alCambiar(lista);
  }

  void _quitarItem(int index) {
    _disposeControladores();
    final lista = [...widget.items]..removeAt(index);
    widget.alCambiar(lista);
  }

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
    _disposeControladores();
    final lista = [
      ...widget.items,
      NuevoItemApartado(
        idProducto: elegido.producto.id,
        nombreProducto: elegido.producto.nombre,
        cantidad: cantidad,
        precioUnitario: elegido.precio,
      ),
    ];
    widget.alCambiar(lista);
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

  @override
  Widget build(BuildContext context) {
    return tarjetaApartado(
      titulo: 'Productos',
      accion: OutlinedButton.icon(
        key: widget.claveAgregarProducto,
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
      child: widget.items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Todavía no agregaste ningún producto', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Expanded(flex: 3, child: SizedBox()),
                      Expanded(child: Text('CANT.', style: _estiloHeader())),
                      Expanded(child: Text('PRECIO', style: _estiloHeader())),
                      Expanded(child: Text('SUBTOTAL', style: _estiloHeader())),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                for (var i = 0; i < widget.items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                  _filaItem(i, widget.items[i]),
                ],
              ],
            ),
    );
  }

  static TextStyle _estiloHeader() => GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF666A72), letterSpacing: 0.3);

  Widget _filaItem(int index, NuevoItemApartado item) {
    final ctrlCantidad = _ctrlCantidad.putIfAbsent(index, () => TextEditingController(text: _formatoCantidad(item.cantidad)));
    final ctrlPrecio = _ctrlPrecio.putIfAbsent(index, () => TextEditingController(text: item.precioUnitario.toStringAsFixed(2)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CampoTecladoCompacto(
                controller: ctrlCantidad,
                numerico: true,
                titulo: 'Cantidad',
                child: TextField(
                  controller: ctrlCantidad,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.poppins(fontSize: 13),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  onChanged: (v) {
                    final valor = double.tryParse(v.replaceAll(',', '').trim());
                    if (valor != null && valor > 0) _actualizarItem(index, cantidad: valor);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CampoTecladoCompacto(
                controller: ctrlPrecio,
                numerico: true,
                titulo: 'Precio unitario',
                child: TextField(
                  controller: ctrlPrecio,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.poppins(fontSize: 13),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  onChanged: (v) {
                    final valor = double.tryParse(v.replaceAll(',', '').trim());
                    if (valor != null && valor >= 0) _actualizarItem(index, precioUnitario: valor);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(formatearMoneda(item.subtotal), textAlign: TextAlign.right, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB91C1C)),
              onPressed: () => _quitarItem(index),
            ),
          ),
        ],
      ),
    );
  }
}
