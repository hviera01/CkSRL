import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import '../../../clientes/data/cliente_model.dart';
import '../../../ventas/presentation/widgets/buscar_cliente_dialog.dart';
import '../../../ventas/presentation/widgets/buscar_producto_dialog.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Pantalla completa (push, no diálogo chico) para armar un apartado nuevo:
/// elegir cliente, agregar productos (reusando BuscarProductoDialog, igual
/// que Registrar Venta), definir el pago inicial (% o monto fijo) y la
/// modalidad de pago del resto -cuotas fijas (con vista previa de las
/// cuotas) o abonos libres-.
class CrearApartadoScreen extends ConsumerStatefulWidget {
  const CrearApartadoScreen({super.key});

  @override
  ConsumerState<CrearApartadoScreen> createState() => _CrearApartadoScreenState();
}

class _CrearApartadoScreenState extends ConsumerState<CrearApartadoScreen> {
  final _clienteController = TextEditingController();
  ClienteModel? _clienteSeleccionado;

  final List<NuevoItemApartado> _items = [];

  // Pago inicial: por porcentaje del total, o un monto fijo tipeado a mano.
  bool _inicialPorPorcentaje = true;
  final _porcentajeController = TextEditingController(text: '50');
  final _montoInicialController = TextEditingController();

  String _modalidad = 'abonos_libres';
  final _numeroCuotasController = TextEditingController(text: '2');
  final _intervaloDiasController = TextEditingController(text: '15');

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _clienteController.dispose();
    _porcentajeController.dispose();
    _montoInicialController.dispose();
    _numeroCuotasController.dispose();
    _intervaloDiasController.dispose();
    super.dispose();
  }

  double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;
  int _parseInt(String texto) => int.tryParse(texto.trim()) ?? 0;

  double get _montoTotal => _items.fold<double>(0, (s, i) => s + i.subtotal);

  double get _montoInicial {
    if (_inicialPorPorcentaje) {
      final porcentaje = _parseDouble(_porcentajeController.text).clamp(0, 100);
      return redondearMoneda(_montoTotal * porcentaje / 100);
    }
    return redondearMoneda(_parseDouble(_montoInicialController.text));
  }

  double get _saldoRestante {
    final saldo = _montoTotal - _montoInicial;
    return saldo < 0 ? 0 : saldo;
  }

  int get _numeroCuotas => _parseInt(_numeroCuotasController.text);
  int get _intervaloDias => _parseInt(_intervaloDiasController.text);

  /// Reparte [_saldoRestante] en partes iguales entre [_numeroCuotas],
  /// ajustando el residuo de redondeo en la última cuota (para que la suma
  /// exacta de las cuotas cuadre centavo a centavo con el saldo restante).
  List<NuevaCuota> _previsualizarCuotas() {
    final n = _numeroCuotas;
    final intervalo = _intervaloDias;
    if (n <= 0 || intervalo <= 0) return [];
    final montoBase = redondearMoneda(_saldoRestante / n);
    final ahora = DateTime.now();
    final cuotas = <NuevaCuota>[];
    var acumulado = 0.0;
    for (var i = 1; i <= n; i++) {
      final esUltima = i == n;
      final monto = esUltima ? redondearMoneda(_saldoRestante - acumulado) : montoBase;
      acumulado = redondearMoneda(acumulado + monto);
      cuotas.add(NuevaCuota(
        numeroCuota: i,
        montoProgramado: monto,
        fechaProgramada: DateTime(ahora.year, ahora.month, ahora.day).add(Duration(days: intervalo * i)),
      ));
    }
    return cuotas;
  }

  Future<void> _buscarCliente() async {
    final cliente = await showDialog<ClienteModel>(
      useRootNavigator: false,
      context: context,
      builder: (context) => const BuscarClienteDialog(),
    );
    if (cliente == null) return;
    setState(() {
      _clienteController.text = cliente.nombreCompleto;
      _clienteSeleccionado = cliente;
    });
  }

  void _limpiarClienteSiEdit() {
    if (_clienteSeleccionado == null) return;
    setState(() => _clienteSeleccionado = null);
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
    final nombreCliente = _clienteController.text.trim();
    if (nombreCliente.isEmpty) {
      setState(() => _error = 'Elegí (o escribí) el cliente');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Agregá al menos un producto');
      return;
    }
    if (_montoInicial > _montoTotal + 0.01) {
      setState(() => _error = 'El pago inicial no puede superar el monto total');
      return;
    }
    if (_montoInicial < 0) {
      setState(() => _error = 'El pago inicial no puede ser negativo');
      return;
    }
    List<NuevaCuota> cuotas = const [];
    if (_modalidad == 'cuotas_fijas') {
      if (_numeroCuotas <= 0) {
        setState(() => _error = 'Ingresá un número de cuotas válido');
        return;
      }
      if (_intervaloDias <= 0) {
        setState(() => _error = 'Ingresá cada cuántos días válido');
        return;
      }
      cuotas = _previsualizarCuotas();
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(apartadoRepositoryProvider).crearApartado(
            idCliente: _clienteSeleccionado?.id,
            nombreCliente: nombreCliente,
            montoInicial: _montoInicial,
            modalidad: _modalidad,
            items: _items,
            cuotas: cuotas,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 720;
    final formatoFecha = DateFormat('dd/MM/yyyy');

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
                      _tarjeta(
                        titulo: 'Cliente',
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CampoTecladoCompacto(
                                controller: _clienteController,
                                numerico: false,
                                child: TextField(
                                  inputFormatters: [mayusculasInputFormatter],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  controller: _clienteController,
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  decoration: _decoracion('Cliente'),
                                  onChanged: (_) => _limpiarClienteSiEdit(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Buscar cliente registrado',
                              onPressed: _buscarCliente,
                              icon: const Icon(Icons.search),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFE8EAF0),
                                padding: const EdgeInsets.all(14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _tarjeta(
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
                      ),
                      const SizedBox(height: 14),
                      _tarjeta(
                        titulo: 'Pago inicial',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ChoiceChip(
                                  label: Text('Porcentaje', style: GoogleFonts.poppins(fontSize: 12.5)),
                                  selected: _inicialPorPorcentaje,
                                  onSelected: (v) => setState(() => _inicialPorPorcentaje = true),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: Text('Monto fijo', style: GoogleFonts.poppins(fontSize: 12.5)),
                                  selected: !_inicialPorPorcentaje,
                                  onSelected: (v) => setState(() => _inicialPorPorcentaje = false),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_inicialPorPorcentaje)
                              CampoTecladoCompacto(
                                controller: _porcentajeController,
                                numerico: true,
                                child: TextField(
                                  controller: _porcentajeController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  decoration: _decoracion('Porcentaje (%)'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              )
                            else
                              CampoTecladoCompacto(
                                controller: _montoInicialController,
                                numerico: true,
                                child: TextField(
                                  controller: _montoInicialController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  decoration: _decoracion('Monto inicial'),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            const SizedBox(height: 12),
                            _filaResumen('Monto total', formatearMoneda(_montoTotal)),
                            _filaResumen('Pago inicial', formatearMoneda(_montoInicial)),
                            _filaResumen('Saldo a financiar', formatearMoneda(_saldoRestante), destacado: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _tarjeta(
                        titulo: 'Modalidad de pago del resto',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ChoiceChip(
                                  label: Text('Abonos libres', style: GoogleFonts.poppins(fontSize: 12.5)),
                                  selected: _modalidad == 'abonos_libres',
                                  onSelected: (v) => setState(() => _modalidad = 'abonos_libres'),
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: Text('Cuotas fijas', style: GoogleFonts.poppins(fontSize: 12.5)),
                                  selected: _modalidad == 'cuotas_fijas',
                                  onSelected: (v) => setState(() => _modalidad = 'cuotas_fijas'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_modalidad == 'abonos_libres')
                              Text(
                                'El cliente abona lo que puede, cuando puede -sin monto ni fecha fija por cuota-.',
                                style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                              )
                            else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: CampoTecladoCompacto(
                                      controller: _numeroCuotasController,
                                      numerico: true,
                                      child: TextField(
                                        controller: _numeroCuotasController,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.poppins(fontSize: 14),
                                        decoration: _decoracion('Número de cuotas'),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: CampoTecladoCompacto(
                                      controller: _intervaloDiasController,
                                      numerico: true,
                                      child: TextField(
                                        controller: _intervaloDiasController,
                                        keyboardType: TextInputType.number,
                                        style: GoogleFonts.poppins(fontSize: 14),
                                        decoration: _decoracion('Cada cuántos días'),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_numeroCuotas > 0 && _intervaloDias > 0)
                                Column(
                                  children: [
                                    for (final cuota in _previsualizarCuotas())
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            Text('Cuota ${cuota.numeroCuota}', style: GoogleFonts.poppins(fontSize: 12.5)),
                                            const Spacer(),
                                            Text(formatearMoneda(cuota.montoProgramado), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 14),
                                            Text(formatoFecha.format(cuota.fechaProgramada), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(_error!, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
                        ),
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

  Widget _tarjeta({required String titulo, required Widget child, Widget? accion}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(titulo, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700))),
              ?accion,
            ],
          ),
          const SizedBox(height: 12),
          child,
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

  Widget _filaResumen(String etiqueta, String valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          Text(
            valor,
            style: GoogleFonts.poppins(
              fontSize: destacado ? 16 : 13.5,
              fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
              color: destacado ? const Color(0xFF0F1B3D) : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}
