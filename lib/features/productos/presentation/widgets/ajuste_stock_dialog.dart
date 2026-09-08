import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/producto_model.dart';
import '../../data/lote_costo_model.dart';
import '../../providers/productos_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../../core/tutorial/tutorial_modelos.dart';
import '../../../../core/tutorial/tutorial_boton.dart';
import '../../../../core/tutorial/tutorial_motor.dart';

enum _ModoAjuste { ingreso, salida }

/// Ajuste manual de existencia, pensado para un negocio que mete stock
/// directo a Inventario en vez de pasar por una Compra formal: cada
/// "Ingreso" queda como su propio lote de costo (igual que si viniera de
/// una compra, ver LoteCostoRepository), y cada "Salida" descuenta de un
/// lote elegido a mano -no FIFO automático, porque es un movimiento manual
/// sin una venta real detrás que determine el orden-.
class AjusteStockDialog extends ConsumerStatefulWidget {
  final ProductoModel producto;
  // Los siguientes tres solo los usa Auditoría de Inventario (ver
  // AuditoriaInventarioScreen): al detectar un descuadre entre el conteo
  // físico y el stock del sistema, abre este mismo diálogo ya precargado
  // (modo, cantidad y motivo) en vez de duplicar todo el flujo de
  // ingreso/salida con lotes de costo.
  final bool? esIngresoInicial;
  final double? cantidadInicial;
  final String? motivoInicial;
  // Bloque informativo opcional que se muestra debajo de "Existencia
  // actual" (ver AuditoriaInventarioScreen: ahí va "Conteo físico: X ·
  // Diferencia: ±Y").
  final Widget? notaSuperior;
  // Si viene en true, apenas se abre este diálogo arranca solo su propio
  // tutorial (_temaAjustarExistencias, más abajo) -pedido explícito del
  // dueño: que el tutorial de "Ajustar Existencias" de Inventario, al
  // llegar acá guiando al usuario, siga de largo explicando Ingreso/Salida,
  // Cantidad, Costo, Lote y Motivo, en vez de cortarse justo cuando se abre
  // este diálogo y dejar que el usuario tenga que buscar el ícono de ayuda
  // de acá adentro por su cuenta-. Ver InventarioScreen._abrirAjusteStock.
  final bool iniciarTutorialAlAbrir;

  const AjusteStockDialog({
    super.key,
    required this.producto,
    this.esIngresoInicial,
    this.cantidadInicial,
    this.motivoInicial,
    this.notaSuperior,
    this.iniciarTutorialAlAbrir = false,
  });

  @override
  ConsumerState<AjusteStockDialog> createState() => _AjusteStockDialogState();
}

class _AjusteStockDialogState extends ConsumerState<AjusteStockDialog> {
  _ModoAjuste _modo = _ModoAjuste.ingreso;
  final _cantidadController = TextEditingController();
  final _costoController = TextEditingController();
  final _motivoController = TextEditingController();
  String? _idLoteSeleccionado;
  bool _salidaSinLote = false;
  bool _guardando = false;
  String? _error;

  // --- GlobalKeys para el tutorial guiado (ver lib/core/tutorial/) ---
  // Este diálogo solo se abre UNA vez a la vez (no vive dentro de una
  // lista), así que no hay riesgo de que dos widgets compartan la misma key
  // al mismo tiempo. _keyLote envuelve todo _selectorLote() con un
  // KeyedSubtree porque esa función devuelve distintos widgets según el
  // estado (cargando/error/datos), y solo existe cuando el modo es Salida.
  final _keySelectorModo = GlobalKey();
  final _keyCantidad = GlobalKey();
  final _keyCosto = GlobalKey();
  final _keyLote = GlobalKey();
  final _keyMotivo = GlobalKey();
  final _keyGuardarAjuste = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.esIngresoInicial != null) _modo = widget.esIngresoInicial! ? _ModoAjuste.ingreso : _ModoAjuste.salida;
    if (widget.cantidadInicial != null && widget.cantidadInicial! > 0) {
      _cantidadController.text = _formatoCantidad(widget.cantidadInicial!);
    }
    if (widget.motivoInicial != null) _motivoController.text = widget.motivoInicial!;
    // Precarga el costo con el precioCompra vigente del producto: para un
    // reajuste de auditoría casi siempre es ese el costo real, y así el
    // usuario no tiene que volver a escribirlo -puede editarlo si de verdad
    // fue distinto (por ejemplo, encontró más de un lote viejo a otro costo).
    if (_modo == _ModoAjuste.ingreso && widget.producto.precioCompra > 0) {
      _costoController.text = _formatoCantidad(widget.producto.precioCompra);
    }
    if (widget.iniciarTutorialAlAbrir) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          iniciarRecorridoTutorial(context, _temaAjustarExistencias.pasos(), onFinish: () {});
        }
      });
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _costoController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _cambiarModo(_ModoAjuste modo) {
    setState(() {
      _modo = modo;
      _error = null;
    });
  }

  // Se llama apenas llegan los lotes (ver build): preselecciona el más
  // antiguo con existencia -el que saldría primero por FIFO normal-, sin
  // pisar una elección que el usuario ya haya hecho a mano.
  void _preseleccionarLote(List<LoteCostoModel> lotesConExistencia) {
    if (_idLoteSeleccionado != null || _salidaSinLote) return;
    if (lotesConExistencia.isEmpty) {
      _salidaSinLote = true;
    } else {
      _idLoteSeleccionado = lotesConExistencia.first.id;
    }
  }

  Future<void> _guardar() async {
    final cantidad = double.tryParse(_cantidadController.text.replaceAll(',', '').trim());
    if (cantidad == null || cantidad <= 0) {
      setState(() => _error = 'Ingresá una cantidad válida');
      return;
    }
    if (_modo == _ModoAjuste.ingreso) {
      final costo = double.tryParse(_costoController.text.replaceAll(',', '').trim());
      if (costo == null || costo < 0) {
        setState(() => _error = 'Ingresá el costo unitario de este ingreso');
        return;
      }
    } else if (!_salidaSinLote && _idLoteSeleccionado == null) {
      setState(() => _error = 'Elegí de qué lote sale');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final usuario = ref.read(authProvider).usuario;
      final repo = ref.read(productoRepositoryProvider);
      if (_modo == _ModoAjuste.ingreso) {
        final costo = double.parse(_costoController.text.replaceAll(',', '').trim());
        await repo.registrarIngreso(
          id: widget.producto.id,
          cantidad: cantidad,
          costoUnitario: costo,
          usuario: usuario?.nombreCompleto ?? 'Sistema',
          motivo: _motivoController.text.trim(),
        );
      } else {
        await repo.registrarSalida(
          id: widget.producto.id,
          cantidad: cantidad,
          idLote: _salidaSinLote ? null : _idLoteSeleccionado,
          usuario: usuario?.nombreCompleto ?? 'Sistema',
          motivo: _motivoController.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  String _formatoCantidad(double cantidad) {
    if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
    return cantidad.toStringAsFixed(2);
  }

  TutorialTema get _temaAjustarExistencias => TutorialTema(
    titulo: 'Editar/Ajustar Existencias (stock)',
    descripcion: 'Sumar o restar unidades y por qué',
    icono: Icons.tune,
    bienvenida:
        'Te voy a explicar cada campo de este ajuste: cuándo usar Ingreso o Salida, qué es el costo, de qué lote sale una salida, y para qué sirve el motivo.',
    pasos: () => [
      TutorialPaso(
        key: _keySelectorModo,
        titulo: 'Ingreso / Salida',
        explicacion:
            '"Ingreso" SUMA unidades -por ejemplo, llegó mercadería nueva sin pasar por una Compra formal, o encontraste unidades que no estaban contadas-. "Salida" RESTA unidades -por ejemplo, se dañó algo, se perdió, o el conteo físico dio menos de lo que decía el sistema-.',
      ),
      TutorialPaso(
        key: _keyCantidad,
        titulo: 'Cantidad',
        explicacion:
            _modo == _ModoAjuste.ingreso
                ? 'Cuántas unidades están ENTRANDO. Este campo es obligatorio y tiene que ser mayor a 0.'
                : 'Cuántas unidades están SALIENDO. Este campo es obligatorio y tiene que ser mayor a 0.',
        obligatorio: true,
      ),
      if (_modo == _ModoAjuste.ingreso)
        TutorialPaso(
          key: _keyCosto,
          titulo: 'Costo unitario de este ingreso',
          explicacion:
              'Cuánto costó cada unidad que está entrando. Es obligatorio -podés poner 0 si te la regalaron o no tuvo costo-, y sirve para que el costo del producto y las ganancias de las ventas queden bien calculados.',
          obligatorio: true,
        ),
      if (_modo == _ModoAjuste.salida)
        TutorialPaso(
          key: _keyLote,
          titulo: '¿De qué costo sale?',
          explicacion:
              'El stock de un producto se guarda internamente en "lotes" según lo que costó cada compra o ingreso. Acá elegís de cuál lote sale esta salida -por defecto ya viene marcado el que dice "Sale primero" (el más antiguo con existencia), que es el orden normal-. Si el producto no tiene lotes con existencia, la salida se descuenta del stock general sin asociarse a ningún costo en particular.',
        ),
      TutorialPaso(
        key: _keyMotivo,
        titulo: 'Motivo',
        explicacion:
            'Un texto libre y opcional para dejar anotado por qué se hizo este ajuste -por ejemplo "Conteo físico", "Producto dañado" o "Se venció"-. No es obligatorio, pero ayuda a entender después por qué cambió el número.',
        obligatorio: false,
      ),
      TutorialPaso(
        key: _keyGuardarAjuste,
        titulo: 'Guardar',
        explicacion:
            'Tocá acá para aplicar el ajuste. La existencia del producto se actualiza al instante, ya no hace falta ningún paso más.',
        obligatorio: true,
      ),
    ],
  );

  InputDecoration _decoracion(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 480;
    final anchoDialog = esMovil ? tamano.width - 48 : 420.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: anchoDialog,
        constraints: BoxConstraints(maxHeight: tamano.height - 80),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Ajustar Existencia', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                  ),
                  TutorialBoton(temas: [_temaAjustarExistencias]),
                ],
              ),
              const SizedBox(height: 6),
              Text('Existencia actual: ${_formatoCantidad(widget.producto.stock)}', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
              if (widget.notaSuperior != null) ...[
                const SizedBox(height: 10),
                widget.notaSuperior!,
              ],
              const SizedBox(height: 18),
              KeyedSubtree(key: _keySelectorModo, child: _selectorModo()),
              const SizedBox(height: 18),
              CampoTecladoCompacto(
                key: _keyCantidad,
                controller: _cantidadController,
                numerico: true,
                child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _cantidadController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _decoracion(_modo == _ModoAjuste.ingreso ? 'Cantidad que ingresa' : 'Cantidad que sale'),
              ),
              ),
              if (_modo == _ModoAjuste.ingreso) ...[
                const SizedBox(height: 14),
                CampoTecladoCompacto(
                  key: _keyCosto,
                  controller: _costoController,
                  numerico: true,
                  child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _costoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Costo unitario de este ingreso', hint: 'Ej: 0 si te lo regalaron'),
                ),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Text('¿De qué costo sale?', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A1A))),
                const SizedBox(height: 8),
                KeyedSubtree(key: _keyLote, child: _selectorLote()),
              ],
              const SizedBox(height: 14),
              CampoTecladoCompacto(
                key: _keyMotivo,
                controller: _motivoController,
                numerico: false,
                child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _motivoController,
                maxLines: 2,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _decoracion('Motivo (opcional)'),
              ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: GoogleFonts.poppins(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  const Spacer(),
                  TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: _keyGuardarAjuste,
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                        : Text('Guardar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorModo() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _botonModo(_ModoAjuste.ingreso, 'Ingreso', Icons.add_circle_outline)),
          Expanded(child: _botonModo(_ModoAjuste.salida, 'Salida', Icons.remove_circle_outline)),
        ],
      ),
    );
  }

  Widget _botonModo(_ModoAjuste modo, String texto, IconData icono) {
    final activo = _modo == modo;
    return InkWell(
      onTap: () => _cambiarModo(modo),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: activo ? const Color(0xFF0F1B3D) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 17, color: activo ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(texto, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: activo ? Colors.white : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _selectorLote() {
    final async = ref.watch(lotesProductoProvider(widget.producto.id));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: Color(0xFF0F1B3D)))),
      error: (e, st) => Text('No se pudieron cargar los lotes: $e', style: GoogleFonts.poppins(fontSize: 12, color: Colors.red)),
      data: (lotes) {
        final conExistencia = lotes.where((l) => l.cantidadRestante > 0).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _preseleccionarLote(conExistencia));
        });
        if (conExistencia.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Este producto no tiene lotes de costo con existencia -la salida se va a descontar del stock general, sin asociarse a un costo en particular.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
            ),
          );
        }
        return Column(
          children: [
            for (final lote in conExistencia) _filaLote(lote, esProximo: lote.id == conExistencia.first.id),
            _filaSinLote(),
          ],
        );
      },
    );
  }

  Widget _filaLote(LoteCostoModel lote, {required bool esProximo}) {
    final seleccionado = !_salidaSinLote && _idLoteSeleccionado == lote.id;
    return InkWell(
      onTap: () => setState(() {
        _idLoteSeleccionado = lote.id;
        _salidaSinLote = false;
      }),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado ? const Color(0xFFFCE4E4) : const Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: seleccionado ? const Color(0xFF0F1B3D) : Colors.transparent, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(seleccionado ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: seleccionado ? const Color(0xFF0F1B3D) : Colors.grey.shade400),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatearMoneda(lote.costoUnitario), style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('${_formatoCantidad(lote.cantidadRestante)} disponibles', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (esProximo)
              Text('Sale primero', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F1B3D))),
          ],
        ),
      ),
    );
  }

  Widget _filaSinLote() {
    final seleccionado = _salidaSinLote;
    return InkWell(
      onTap: () => setState(() {
        _salidaSinLote = true;
        _idLoteSeleccionado = null;
      }),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado ? const Color(0xFFFCE4E4) : const Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: seleccionado ? const Color(0xFF0F1B3D) : Colors.transparent, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(seleccionado ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: seleccionado ? const Color(0xFF0F1B3D) : Colors.grey.shade400),
            const SizedBox(width: 10),
            Expanded(child: Text('Sin lote específico', style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A)))),
          ],
        ),
      ),
    );
  }
}
