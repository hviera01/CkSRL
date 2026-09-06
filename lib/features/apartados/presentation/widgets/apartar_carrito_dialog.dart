import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import 'configuracion_apartado.dart';
import 'editor_productos_apartado.dart';

/// Convierte en apartado un carrito ya armado en Registrar Venta -pedido
/// explícito del dueño: poder apartar sin tener que volver a elegir los
/// productos uno por uno en la pantalla de Apartados-.
///
/// Los productos llegan del carrito como punto de partida ([widget.items]),
/// pero acá adentro siguen siendo tan editables como en CrearApartadoScreen
/// -precio/cantidad inline y "Agregar Producto" siempre disponible, ver
/// EditorProductosApartado-, no una copia de solo lectura: pedido explícito
/// del dueño tras probar el módulo, misma libertad que ya tiene la tabla de
/// Registrar Venta. Se arma con la MISMA UI y el MISMO cálculo de cuotas que
/// CrearApartadoScreen (ver ConfiguracionApartadoForm), y se crea con el
/// MISMO repositorio -o sea, la misma función plpgsql `crear_apartado`, que
/// reserva sin descontar existencia física-.
///
/// Devuelve por Navigator.pop el id del apartado creado, o null si se
/// canceló. Es Registrar Venta quien decide qué hacer después (limpiar el
/// carrito, avisar, ofrecer ver el detalle): acá NO se registra ninguna
/// venta, no se consume correlativo ni se imprime nada -y los cambios acá
/// adentro (editar/agregar productos) tampoco se reflejan de vuelta en el
/// carrito de Registrar Venta, que sigue intacto si el usuario cancela-.
class ApartarCarritoDialog extends ConsumerStatefulWidget {
  final List<NuevoItemApartado> items;
  final String nombreClienteInicial;
  final String? idClienteInicial;

  const ApartarCarritoDialog({
    super.key,
    required this.items,
    this.nombreClienteInicial = '',
    this.idClienteInicial,
  });

  @override
  ConsumerState<ApartarCarritoDialog> createState() => _ApartarCarritoDialogState();
}

class _ApartarCarritoDialogState extends ConsumerState<ApartarCarritoDialog> {
  late final ConfiguracionApartadoController _config = ConfiguracionApartadoController(
    nombreClienteInicial: widget.nombreClienteInicial,
    idCliente: widget.idClienteInicial,
  );

  late final List<NuevoItemApartado> _items = [...widget.items];

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
      final id = await ref.read(apartadoRepositoryProvider).crearApartado(
            idCliente: _config.idCliente,
            nombreCliente: _config.nombreCliente,
            montoInicial: _config.montoInicialSobre(_montoTotal),
            montoInicialReal: _config.montoInicialReal,
            metodoPagoInicial: _config.montoInicialReal > 0.009 ? _config.metodoPagoInicial : null,
            modalidad: _config.modalidad,
            items: _items,
            cuotas: _config.cuotasSobre(_montoTotal),
          );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // La existencia real de cada producto la valida el servidor (con
        // lock) dentro de `crear_apartado`: si algo no alcanza, ese mensaje
        // -que ya dice qué producto y cuánto hay- se muestra tal cual acá.
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 720;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: const Color(0xFFF2F3F7),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Apartar productos', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            'Se reservan los productos del carrito sin registrar una venta -podés seguir editando precio/cantidad o agregar más antes de confirmar-: la existencia se descuenta recién al entregar el apartado.',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      content: SizedBox(
        width: esMovil ? tamano.width : 620,
        child: SingleChildScrollView(
          child: ConfiguracionApartadoForm(
            controller: _config,
            montoTotal: _montoTotal,
            alCambiar: () => setState(() {}),
            seccionProductos: _tarjetaProductos(),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      actions: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: errorApartado(_error!),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _guardando ? null : () => Navigator.pop(context),
              child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700)),
            ),
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
                  : Text('Crear Apartado', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tarjetaProductos() {
    return EditorProductosApartado(items: _items, alCambiar: _actualizarItems);
  }
}
