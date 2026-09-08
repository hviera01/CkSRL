import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/apartado_repository.dart';
import '../../providers/apartados_provider.dart';
import '../../../../core/tutorial/tutorial_modelos.dart';
import '../../../../core/tutorial/tutorial_boton.dart';
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

  // Claves del tutorial guiado -pedido explícito del dueño: la persona que
  // va a usar el sistema no es muy ágil con computadoras-.
  final _keyCliente = GlobalKey();
  final _keyAgregarProducto = GlobalKey();
  final _keyTogglePagoInicial = GlobalKey();
  final _keyMontoInicialReal = GlobalKey();
  final _keyToggleModalidad = GlobalKey();
  final _keyNumeroCuotas = GlobalKey();
  final _keyFechaPrimerPago = GlobalKey();
  final _keyGuardar = GlobalKey();

  @override
  void dispose() {
    _config.dispose();
    super.dispose();
  }

  /// Pasos comunes a las dos modalidades (cliente, productos, pago inicial),
  /// compartidos por los dos TutorialTema de abajo para no repetir el texto.
  List<TutorialPaso> _pasosComunesApartado() => [
        TutorialPaso(
          key: _keyCliente,
          titulo: 'Elegí el cliente',
          explicacion:
              'Escribí el nombre del cliente, o tocá la lupa para buscar uno '
              'ya registrado. Todo apartado necesita saber a nombre de quién '
              'queda.',
          obligatorio: true,
        ),
        TutorialPaso(
          key: _keyAgregarProducto,
          titulo: 'Agregar productos',
          explicacion:
              'Tocá acá para buscar y agregar cada producto que el cliente '
              'va a apartar. Podés poner varios productos en el mismo '
              'apartado, y ajustar cantidad y precio de cada uno después de '
              'agregarlo.',
        ),
        TutorialPaso(
          key: _keyTogglePagoInicial,
          titulo: '¿Cómo calculamos el pago inicial?',
          explicacion:
              'Elegí "Porcentaje" (por ejemplo, 50% del total) o "Monto '
              'fijo" (un número exacto) para calcular el pago inicial '
              'SUGERIDO. Esto solo arma las cuotas de referencia -lo que el '
              'cliente da de verdad se anota aparte, en el siguiente paso-.',
          obligatorio: false,
        ),
        TutorialPaso(
          key: _keyMontoInicialReal,
          titulo: '¿Cuánto dio de verdad el cliente?',
          explicacion:
              'Acá anotás lo que el cliente REALMENTE entregó ahora -puede '
              'ser distinto al sugerido de arriba, o incluso \$0 si no dio '
              'nada de entrada-, junto con su método de pago. Esto es lo '
              'que de verdad queda registrado como el primer pago.',
          obligatorio: false,
        ),
      ];

  TutorialTema get _temaCuotasFijas => TutorialTema(
        titulo: 'Crear un apartado con cuotas fijas',
        descripcion: 'Monto y fecha programados por cuota',
        icono: Icons.event_repeat_outlined,
        bienvenida:
            'Un Apartado es distinto de una Venta a Crédito: acá el cliente '
            'se lleva el producto SOLO cuando termina de pagar todo -mientras '
            'tanto, el producto queda guardado en el negocio-. "Cuotas '
            'fijas" quiere decir que vos programás de antemano cuánto y '
            'cuándo paga cada cuota (por ejemplo, un monto fijo cada 15 '
            'días). Te muestro cómo armarlo.',
        pasos: () => [
          ..._pasosComunesApartado(),
          TutorialPaso(
            key: _keyToggleModalidad,
            titulo: 'Elegí "Cuotas fijas"',
            explicacion:
                'Hay dos formas de pagar el resto: "Cuotas fijas" (vos '
                'programás monto y fecha de cada cuota, con una frecuencia '
                '-Diario, Semanal, Quincenal, Mensual o Trimestral-) o '
                '"Abonos libres" (el cliente da lo que puede, cuando puede, '
                'sin monto ni fecha fija). Elegí "Cuotas fijas" acá para '
                'seguir con este tutorial.',
          ),
          TutorialPaso(
            key: _keyNumeroCuotas,
            titulo: 'Número de cuotas y frecuencia',
            explicacion:
                'Escribí en cuántas cuotas se va a dividir el saldo, y '
                'elegí cada cuánto cae cada una. Más abajo vas a ver la '
                'vista previa de cada cuota con su monto y fecha.',
            obligatorio: true,
          ),
          TutorialPaso(
            key: _keyFechaPrimerPago,
            titulo: 'Fecha de la primera cuota',
            explicacion:
                'Por defecto la primera cuota cae automáticamente (hoy + '
                'una frecuencia), pero podés tocar acá y elegir otra fecha '
                'a mano -por ejemplo, si querés darle un mes de gracia al '
                'cliente antes de que empiece a pagar-.',
            obligatorio: false,
          ),
          TutorialPaso(
            key: _keyGuardar,
            titulo: 'Guardar Apartado',
            explicacion:
                'Cuando ya agregaste los productos y revisaste todo, tocá '
                'acá para guardar el apartado.',
          ),
        ],
      );

  TutorialTema get _temaAbonosLibres => TutorialTema(
        titulo: 'Crear un apartado con abonos libres',
        descripcion: 'El cliente abona lo que puede, cuando puede',
        icono: Icons.savings_outlined,
        bienvenida:
            'Un Apartado es distinto de una Venta a Crédito: acá el cliente '
            'se lleva el producto SOLO cuando termina de pagar todo -mientras '
            'tanto, el producto queda guardado en el negocio-. "Abonos '
            'libres" quiere decir que el cliente va dando lo que puede, '
            'cuando puede, sin que vos le programes un monto ni una fecha '
            'fija por cuota. Te muestro cómo armarlo.',
        pasos: () => [
          ..._pasosComunesApartado(),
          TutorialPaso(
            key: _keyToggleModalidad,
            titulo: 'Elegí "Abonos libres"',
            explicacion:
                'Hay dos formas de pagar el resto: "Abonos libres" (el '
                'cliente da lo que puede, cuando puede, sin monto ni fecha '
                'fija) o "Cuotas fijas" (vos programás de antemano cuánto y '
                'cuándo paga cada cuota). Elegí "Abonos libres" acá para '
                'seguir con este tutorial.',
          ),
          TutorialPaso(
            key: _keyGuardar,
            titulo: 'Guardar Apartado',
            explicacion:
                'Cuando ya agregaste los productos y revisaste todo, tocá '
                'acá para guardar el apartado. Después, cada vez que el '
                'cliente venga a abonar, lo registrás desde el detalle de '
                'este apartado.',
          ),
        ],
      );

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
      body: Stack(
        children: [
          SafeArea(
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
                            claveCliente: _keyCliente,
                            claveTogglePagoInicial: _keyTogglePagoInicial,
                            claveMontoInicialReal: _keyMontoInicialReal,
                            claveToggleModalidad: _keyToggleModalidad,
                            claveNumeroCuotas: _keyNumeroCuotas,
                            claveFechaPrimerPago: _keyFechaPrimerPago,
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
          Positioned(
            right: 16,
            bottom: 16,
            child: TutorialBoton(temas: [_temaCuotasFijas, _temaAbonosLibres]),
          ),
        ],
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
                key: _keyGuardar,
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
    return EditorProductosApartado(items: _items, alCambiar: _actualizarItems, claveAgregarProducto: _keyAgregarProducto);
  }
}
