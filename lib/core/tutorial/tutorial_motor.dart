import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tutorial_modelos.dart';

const _azulMarca = Color(0xFF0F1B3D);

/// Arranca un recorrido guiado INTERACTIVO de verdad -reemplaza al viejo
/// mecanismo basado en el paquete tutorial_coach_mark-: resalta el widget
/// real de cada [pasos] (con el resto de la pantalla oscurecido) pero SIN
/// bloquear el toque -a diferencia de antes, tocar el campo/botón real
/// resaltado ejecuta la acción de verdad (abre el diálogo, guarda, escribe
/// en el campo, etc.) y ADEMÁS avanza solo al siguiente paso, sin que haga
/// falta apretar "Siguiente"- pedido explícito del dueño: "quiero que el
/// cliente vaya tocando haciendo mientras lo van guiando".
///
/// También arregla el bug real de antes: la pantalla real sigue scrolleando
/// libremente en todo momento (el resaltado no tapa ni bloquea nada), así
/// que un paso que apunta a un campo más abajo del scroll actual ya no
/// puede "quedar pegado" -de todas formas, por comodidad, cada paso se
/// desplaza solo a la vista al empezar-.
///
/// [pasos] ya viene armado (ver TutorialTema.pasos()) y puede tener pasos
/// cuyo widget real no exista ahora mismo (se saltan solos). Llama a
/// [onFinish] cuando se completan todos los pasos disponibles.
void iniciarRecorridoTutorial(
  BuildContext context,
  List<TutorialPaso> pasos, {
  required VoidCallback onFinish,
}) {
  late OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (_) => _TutorialOverlay(
      pasos: pasos,
      onFinish: () {
        entrada.remove();
        onFinish();
      },
      onSalir: () => entrada.remove(),
    ),
  );
  Overlay.of(context).insert(entrada);
}

class _TutorialOverlay extends StatefulWidget {
  final List<TutorialPaso> pasos;
  final VoidCallback onFinish;
  final VoidCallback onSalir;
  const _TutorialOverlay({
    required this.pasos,
    required this.onFinish,
    required this.onSalir,
  });

  @override
  State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay> {
  int _indice = 0;
  Rect? _rect;
  Size? _tamano;
  Timer? _sondeo;
  bool _avanzandoPorToque = false;
  bool _terminado = false;

  TutorialPaso get _paso => widget.pasos[_indice];

  @override
  void initState() {
    super.initState();
    // Recalcula la posición real del campo resaltado varias veces por
    // segundo -así el resaltado sigue al campo si la pantalla scrollea
    // (ahora sí se puede, a mano) o si el layout cambia (rotar, teclado)-.
    _sondeo = Timer.periodic(const Duration(milliseconds: 100), (_) => _actualizarRect());
    WidgetsBinding.instance.addPostFrameCallback((_) => _irA(0, direccion: 1, primeraVez: true));
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  void _actualizarRect() {
    if (_terminado || _indice >= widget.pasos.length) return;
    final ctx = _paso.key.currentContext;
    if (ctx == null) return;
    final caja = ctx.findRenderObject();
    if (caja is! RenderBox || !caja.attached) return;
    // Coordenadas relativas al propio RenderBox de este overlay -no a la
    // pantalla completa-: cada pestaña tiene su Navigator/Overlay propio
    // (ver el resto del sistema, useRootNavigator: false) que puede estar
    // desplazado dentro de la ventana (menú lateral, barra superior), así
    // que la posición global del campo no coincide con la posición local
    // dentro de ESTE Stack a menos que se convierta con el mismo ancestro.
    final ancestro = context.findRenderObject();
    if (ancestro is! RenderBox) return;
    final nuevo = caja.localToGlobal(Offset.zero, ancestor: ancestro) & caja.size;
    if (nuevo != _rect || ancestro.size != _tamano) {
      setState(() {
        _rect = nuevo;
        _tamano = ancestro.size;
      });
    }
  }

  Future<void> _asegurarVisible(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );
  }

  // Busca desde [desde], moviéndose de a [direccion] (1 adelante, -1 atrás),
  // el próximo paso cuyo widget real siga existiendo -puede haber pasos que
  // ya no aplican (un campo que solo aparece con cierta opción elegida)-.
  // Si no encuentra ninguno yendo hacia adelante, termina el tutorial.
  Future<void> _irA(int desde, {required int direccion, bool primeraVez = false}) async {
    var i = desde;
    while (i >= 0 && i < widget.pasos.length) {
      final ctx = widget.pasos[i].key.currentContext;
      if (ctx != null) {
        setState(() {
          _indice = i;
          _rect = null;
        });
        await _asegurarVisible(widget.pasos[i].key);
        if (!mounted) return;
        _actualizarRect();
        return;
      }
      i += direccion;
    }
    if (primeraVez) {
      // Ningún paso de este tema tiene su widget real visible ahora mismo:
      // no hay nada que mostrar. Se cierra sin el aviso de "¡Listo!" -no se
      // llegó a mostrar ni un solo paso, no tendría sentido felicitar por
      // terminar algo que nunca arrancó-.
      _salir();
      return;
    }
    if (direccion > 0) _terminar();
    // Yendo hacia atrás y no queda ninguno: no debería pasar (el botón
    // "Atrás" no se muestra en el primer paso), no hace nada.
  }

  void _siguiente() => _irA(_indice + 1, direccion: 1);
  void _atras() => _irA(_indice - 1, direccion: -1);

  void _terminar() {
    if (_terminado) return;
    _terminado = true;
    widget.onFinish();
  }

  void _salir() {
    if (_terminado) return;
    _terminado = true;
    widget.onSalir();
  }

  Offset? _bajadaEn;

  // Se guarda dónde bajó el dedo/mouse -ver onPointerUp más abajo-: hace
  // falta distinguir un toque real de un intento de scroll que empieza
  // justo sobre el campo resaltado (mismo Listener detecta ambos "pointer
  // down"). No usa el sistema de gestos de Flutter (GestureDetector/
  // InkWell) a propósito: eso competiría en la "arena" de gestos contra el
  // botón/campo real de abajo y podría robarle el toque -acá solo se
  // observa el evento, nunca se reclama, así el widget real siempre recibe
  // su toque normal-.
  void _alBajarDedo(Offset posicion) {
    _bajadaEn = posicion;
  }

  // El usuario tocó de verdad el campo/botón real resaltado -el toque ya
  // siguió su curso normal, no se interceptó-. Solo cuenta como toque (no
  // como el arranque de un scroll) si el dedo se levantó cerca de donde
  // bajó. Un pequeño respiro antes de avanzar, para que si esa acción abrió
  // un diálogo o cambió algo en pantalla, se note primero.
  void _alSoltarDedo(Offset posicion) {
    final bajada = _bajadaEn;
    _bajadaEn = null;
    if (bajada == null || (posicion - bajada).distance > 18) return;
    if (_avanzandoPorToque || _paso.avance == TutorialAvance.manual) return;
    _avanzandoPorToque = true;
    Future.delayed(const Duration(milliseconds: 450), () {
      _avanzandoPorToque = false;
      if (mounted && !_terminado) _siguiente();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    // Tamaño del propio overlay (no MediaQuery.of, que da el de TODA la
    // ventana): cada pestaña tiene su Navigator/Overlay propio que puede
    // ocupar menos que la ventana completa -mismo motivo que en
    // _actualizarRect-, y [rect] ya está en esas coordenadas locales.
    final tamano = _tamano ?? MediaQuery.of(context).size;
    return Stack(
      children: [
        // Oscurece toda la pantalla salvo un hueco alrededor del campo
        // resaltado -IgnorePointer a propósito: esta capa NUNCA intercepta
        // toques ni gestos de scroll, la pantalla real sigue 100% usable-.
        IgnorePointer(
          child: SizedBox.expand(
            child: CustomPaint(painter: _PintorFoco(rect: rect)),
          ),
        ),
        // Zona invisible del tamaño exacto del campo resaltado que SÍ ve el
        // toque (para avanzar el tutorial solo) pero sin consumirlo -modo
        // translúcido: el mismo toque sigue de largo hacia el widget real
        // de abajo, que reacciona normal (abre su diálogo, guarda, etc.)-.
        if (rect != null && _paso.avance == TutorialAvance.tocar)
          Positioned.fromRect(
            rect: rect.inflate(8),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _alBajarDedo(e.position),
              onPointerUp: (e) => _alSoltarDedo(e.position),
              child: const SizedBox.expand(),
            ),
          ),
        if (rect != null) _tarjeta(context, rect, tamano),
      ],
    );
  }

  Widget _tarjeta(BuildContext context, Rect rect, Size tamano) {
    const margen = 14.0;
    const separacion = 12.0;
    final espacioAbajo = tamano.height - rect.bottom;
    final espacioArriba = rect.top;
    // Se respeta la alineación pedida (arriba/abajo del campo) salvo que no
    // haya espacio real para la tarjeta de ese lado -ahí se voltea sola
    // hacia el lado con más espacio, para nunca quedar recortada-.
    var abajo = _paso.alineacion != ContentAlign.top;
    if (abajo && espacioAbajo < 140 && espacioArriba > espacioAbajo) abajo = false;
    if (!abajo && espacioArriba < 140 && espacioAbajo > espacioArriba) abajo = true;

    return Positioned(
      left: margen,
      right: margen,
      top: abajo ? rect.bottom + separacion : null,
      bottom: abajo ? null : (tamano.height - rect.top) + separacion,
      child: _TarjetaExplicacion(
        paso: _paso,
        indice: _indice,
        total: widget.pasos.length,
        onAtras: _indice > 0 ? _atras : null,
        onSiguiente: _siguiente,
        onSalir: _salir,
      ),
    );
  }
}

class _PintorFoco extends CustomPainter {
  final Rect? rect;
  const _PintorFoco({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final pantallaCompleta = Path()..addRect(Offset.zero & size);
    final fondo = Paint()..color = _azulMarca.withValues(alpha: 0.85);
    final target = rect;
    if (target == null) {
      canvas.drawPath(pantallaCompleta, fondo);
      return;
    }
    final inflado = target.inflate(8);
    final rrect = RRect.fromRectAndRadius(inflado, const Radius.circular(12));
    final hueco = Path()..addRRect(rrect);
    final combinado = Path.combine(PathOperation.difference, pantallaCompleta, hueco);
    canvas.drawPath(combinado, fondo);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _PintorFoco oldDelegate) => oldDelegate.rect != rect;
}

class _TarjetaExplicacion extends StatelessWidget {
  final TutorialPaso paso;
  final int indice;
  final int total;
  final VoidCallback? onAtras;
  final VoidCallback onSiguiente;
  final VoidCallback onSalir;

  const _TarjetaExplicacion({
    required this.paso,
    required this.indice,
    required this.total,
    required this.onAtras,
    required this.onSiguiente,
    required this.onSalir,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    paso.titulo,
                    style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: _azulMarca),
                  ),
                ),
                Text(
                  '${indice + 1}/$total',
                  style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
            if (paso.obligatorio != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: paso.obligatorio! ? const Color(0xFFFCE4E4) : const Color(0xFFE1F5EA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  paso.obligatorio! ? 'Este campo es obligatorio' : 'Este campo lo podés dejar vacío',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: paso.obligatorio! ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(paso.explicacion, style: GoogleFonts.poppins(fontSize: 13, height: 1.4)),
            if (paso.avance == TutorialAvance.tocar) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.touch_app_rounded, size: 15, color: Colors.grey.shade500),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Podés tocar lo resaltado para hacerlo de verdad y seguir solo.',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: onSalir,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  child: Text('Salir del tutorial', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
                ),
                const Spacer(),
                if (onAtras != null)
                  TextButton(
                    onPressed: onAtras,
                    child: Text('Atrás', style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _azulMarca,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: onSiguiente,
                  child: Text(
                    indice + 1 >= total ? 'Terminar' : 'Siguiente',
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
