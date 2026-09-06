import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import 'configuracion_apartado.dart';
import '../../../../core/utils/formato_moneda.dart';

/// Convierte en apartado un carrito ya armado en Registrar Venta -pedido
/// explícito del dueño: poder apartar sin tener que volver a elegir los
/// productos uno por uno en la pantalla de Apartados-.
///
/// Los productos llegan cerrados (los del carrito, tal cual): acá solo se
/// piden los datos propios del apartado, con la MISMA UI y el MISMO cálculo
/// de cuotas que CrearApartadoScreen (ver ConfiguracionApartadoForm), y se
/// crea con el MISMO repositorio -o sea, la misma función plpgsql
/// `crear_apartado`, que reserva sin descontar existencia física-.
///
/// Devuelve por Navigator.pop el id del apartado creado, o null si se
/// canceló. Es Registrar Venta quien decide qué hacer después (limpiar el
/// carrito, avisar, ofrecer ver el detalle): acá NO se registra ninguna
/// venta, no se consume correlativo ni se imprime nada.
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

  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _config.dispose();
    super.dispose();
  }

  double get _montoTotal => widget.items.fold<double>(0, (s, i) => s + i.subtotal);

  Future<void> _guardar() async {
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
            modalidad: _config.modalidad,
            items: widget.items,
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
            'Se reservan los productos del carrito sin registrar una venta: la existencia se descuenta recién al entregar el apartado.',
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

  /// Solo lectura: los productos ya se eligieron en el carrito -para cambiar
  /// algo se cancela, se ajusta el carrito y se vuelve a apartar-.
  Widget _tarjetaProductos() {
    return tarjetaApartado(
      titulo: 'Productos del carrito',
      child: Column(
        children: [
          for (var i = 0; i < widget.items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
            _filaItem(widget.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _filaItem(NuevoItemApartado item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(item.nombreProducto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(
              'x${item.cantidad.toStringAsFixed(item.cantidad == item.cantidad.roundToDouble() ? 0 : 2)}',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(formatearMoneda(item.precioUnitario), style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(formatearMoneda(item.subtotal), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
