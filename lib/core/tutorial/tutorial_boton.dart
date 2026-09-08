import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'tutorial_modelos.dart';

const _azulMarca = Color(0xFF0F1B3D);

/// Ícono chico y discreto de "Tutorial" -pedido explícito del dueño: la
/// persona que va a usar el sistema no es muy ágil con computadoras, necesita
/// una guía paso a paso explicada bien simple en cada pantalla-. Al tocarlo
/// abre un menú con los temas disponibles PARA ESA PANTALLA ([temas]); al
/// elegir uno arranca un recorrido guiado que resalta cada campo/botón REAL
/// de la pantalla (con el resto oscurecido) y lo va explicando de a un paso
/// por vez, con "Atrás"/"Siguiente" y "Salir del tutorial" siempre visible.
///
/// CÓMO USARLO en una pantalla nueva:
/// 1. Envolvé cada widget que quieras poder resaltar con una `GlobalKey`
///    propia (`key: _miClaveDelBoton` en el widget de verdad de esa pantalla,
///    no uno de mentira).
/// 2. Armá una o más `TutorialTema` (una por cada "cómo hacer X" distinto),
///    cada una con su `pasos: () => [TutorialPaso(key: _miClave, ...), ...]`.
/// 3. Metelo en un `Stack` de esa pantalla:
///    `Positioned(right: 16, bottom: 16, child: TutorialBoton(temas: [...]))`.
class TutorialBoton extends StatelessWidget {
  final List<TutorialTema> temas;
  const TutorialBoton({super.key, required this.temas});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => _mostrarMenu(context),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _azulMarca,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  // Antes era un showModalBottomSheet con una Column sin scroll -pedido
  // explícito del dueño tras ver que en pantallas con muchos temas (o poca
  // altura, típico en un celular apaisado) las últimas opciones quedaban
  // recortadas, invisibles e imposibles de alcanzar-. Ahora es un diálogo
  // centrado con una lista que si no cabe entera, se puede desplazar.
  void _mostrarMenu(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (contextMenu) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(contextMenu).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EAF0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: _azulMarca,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '¿Qué querés aprender a hacer?',
                        style: GoogleFonts.poppins(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(contextMenu),
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Elegí una opción y te voy guiando paso a paso.',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: temas
                          .map((tema) => _filaTema(context, contextMenu, tema))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaTema(
    BuildContext contextPantalla,
    BuildContext contextMenu,
    TutorialTema tema,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pop(contextMenu);
        // Un frame de margen para que el bottom sheet termine de cerrarse
        // antes de medir dónde están los widgets reales a resaltar -si se
        // arranca en el mismo instante, la primera posición puede salir mal
        // calculada mientras el sheet todavía se está animando hacia abajo-.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (contextPantalla.mounted) {
            _iniciarTutorial(contextPantalla, tema);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tema.icono, color: _azulMarca, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tema.titulo,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  Text(
                    tema.descripcion,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _iniciarTutorial(BuildContext context, TutorialTema tema) {
    Future<void> arrancarRecorrido() async {
      final pasos = tema.pasos();
      final targets = <TargetFocus>[];
      for (var i = 0; i < pasos.length; i++) {
        final paso = pasos[i];
        // Si el widget de este paso no está visible ahora mismo (por
        // ejemplo, un campo que solo aparece con cierta opción elegida), se
        // salta ese paso en vez de romper el tutorial entero.
        if (paso.key.currentContext == null) continue;
        targets.add(
          TargetFocus(
            identify: 'paso_$i',
            keyTarget: paso.key,
            shape: ShapeLightFocus.RRect,
            radius: 12,
            // La superposición oscura del tutorial se queda encima de TODA
            // la pantalla incluso del campo resaltado -pedido explícito del
            // dueño: antes tocar el campo real "de mentiras" solo avanzaba
            // el tutorial sin hacer la acción real, lo que parecía "solo una
            // explicación sin práctica"-. Se desactiva ese toque fantasma:
            // el usuario avanza siempre con el botón "Siguiente" de la
            // tarjeta, y recién cuando cierra o termina el tutorial puede
            // tocar el campo real para hacer la acción de verdad.
            enableTargetTab: false,
            enableOverlayTab: false,
            contents: [
              TargetContent(
                align: paso.alineacion,
                builder: (context, controller) => _tarjetaExplicacion(
                  pasos,
                  i,
                  controller,
                ),
              ),
            ],
          ),
        );
      }
      if (targets.isEmpty) return;
      // El overlay del tutorial ocupa el tamaño fijo de la pantalla (no
      // scrollea) y ubica cada tarjeta a la altura exacta donde esté su
      // campo real -si ese campo está más abajo de lo que se ve ahora
      // mismo, la tarjeta se dibuja fuera de esa altura fija y queda
      // invisible/inalcanzable, sin forma de bajar a mano porque el overlay
      // no deja pasar el gesto de scroll a la pantalla real de abajo-. Por
      // eso, antes de arrancar, se desplaza la pantalla real para que el
      // primer campo del recorrido ya esté a la vista.
      await _asegurarVisible(pasos[0].key);
      if (!context.mounted) return;
      TutorialCoachMark(
        targets: targets,
        colorShadow: _azulMarca,
        opacityShadow: 0.85,
        textSkip: 'Salir del tutorial',
        paddingFocus: 8,
        onFinish: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '¡Listo! Podés volver a este tutorial cuando quieras tocando el ícono de arriba.',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        },
        onSkip: () => true,
      ).show(context: context);
    }

    final bienvenida = tema.bienvenida;
    if (bienvenida == null || bienvenida.isEmpty) {
      arrancarRecorrido();
      return;
    }
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Row(
          children: [
            const Icon(Icons.school_rounded, color: _azulMarca),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tema.titulo,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          bienvenida,
          style: GoogleFonts.poppins(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _azulMarca),
            onPressed: () {
              Navigator.pop(context);
              arrancarRecorrido();
            },
            child: Text(
              'Empezar',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Desplaza la pantalla real (si está dentro de algo scrolleable) para que
  // [key] quede a la vista, centrado -sin esto el usuario no tiene forma de
  // alcanzar un campo que esté más abajo del scroll actual, ver el
  // comentario grande en arrancarRecorrido-. Si esa pantalla no tiene scroll
  // (o el campo ya está a la vista), no hace nada.
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

  // Busca, a partir de [desde] y moviéndose de a [paso] (1 para adelante, -1
  // para atrás), el próximo TutorialPaso de la lista completa cuyo widget
  // real siga existiendo -puede haber pasos de por medio que se saltaron al
  // armar el recorrido (ver arrancarRecorrido)-.
  GlobalKey? _proximaKeyVisible(List<TutorialPaso> pasos, int desde, int paso) {
    var i = desde;
    while (i >= 0 && i < pasos.length) {
      if (pasos[i].key.currentContext != null) return pasos[i].key;
      i += paso;
    }
    return null;
  }

  Widget _tarjetaExplicacion(
    List<TutorialPaso> pasos,
    int indice,
    TutorialCoachMarkController controller,
  ) {
    final paso = pasos[indice];
    final total = pasos.length;
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _azulMarca,
                  ),
                ),
              ),
              Text(
                '${indice + 1}/$total',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          if (paso.obligatorio != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: paso.obligatorio!
                    ? const Color(0xFFFCE4E4)
                    : const Color(0xFFE1F5EA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                paso.obligatorio!
                    ? 'Este campo es obligatorio'
                    : 'Este campo lo podés dejar vacío',
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: paso.obligatorio!
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF15803D),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            paso.explicacion,
            style: GoogleFonts.poppins(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => controller.skip(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(
                  'Salir del tutorial',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const Spacer(),
              if (indice > 0)
                TextButton(
                  onPressed: () async {
                    // Antes de retroceder, aseguramos que el paso anterior
                    // esté a la vista -mismo motivo que al arrancar el
                    // recorrido: el overlay no deja scrollear a mano.
                    final key = _proximaKeyVisible(pasos, indice - 1, -1);
                    if (key != null) await _asegurarVisible(key);
                    controller.previous();
                  },
                  child: Text('Atrás', style: GoogleFonts.poppins(fontSize: 13)),
                ),
              const SizedBox(width: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _azulMarca,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  // Mismo mecanismo: antes de avanzar, se desplaza la
                  // pantalla real para que el próximo campo del recorrido
                  // ya esté a la vista cuando el tutorial lo resalte.
                  final key = _proximaKeyVisible(pasos, indice + 1, 1);
                  if (key != null) await _asegurarVisible(key);
                  controller.next();
                },
                child: Text(
                  indice + 1 >= total ? 'Terminar' : 'Siguiente',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
