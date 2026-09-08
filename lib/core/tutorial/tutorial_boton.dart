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

  void _mostrarMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (contextMenu) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
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
                  Text(
                    '¿Qué querés aprender a hacer?',
                    style: GoogleFonts.poppins(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
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
              const SizedBox(height: 10),
              ...temas.map(
                (tema) => _filaTema(context, contextMenu, tema),
              ),
            ],
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
    void arrancarRecorrido() {
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
            contents: [
              TargetContent(
                align: paso.alineacion,
                builder: (context, controller) => _tarjetaExplicacion(
                  paso,
                  i,
                  pasos.length,
                  controller,
                ),
              ),
            ],
          ),
        );
      }
      if (targets.isEmpty) return;
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

  Widget _tarjetaExplicacion(
    TutorialPaso paso,
    int indice,
    int total,
    TutorialCoachMarkController controller,
  ) {
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
                  onPressed: () => controller.previous(),
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
                onPressed: () => controller.next(),
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
