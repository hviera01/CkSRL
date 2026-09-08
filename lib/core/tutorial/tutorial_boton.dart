import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tutorial_modelos.dart';
import 'tutorial_motor.dart';

const _azulMarca = Color(0xFF0F1B3D);

/// Ícono chico y discreto de "Tutorial" -pedido explícito del dueño: la
/// persona que va a usar el sistema no es muy ágil con computadoras, necesita
/// una guía paso a paso explicada bien simple en cada pantalla-. Al tocarlo
/// abre un menú con los temas disponibles PARA ESA PANTALLA ([temas]); al
/// elegir uno arranca un recorrido guiado que resalta cada campo/botón REAL
/// de la pantalla (con el resto oscurecido, sin bloquear el toque real, ver
/// tutorial_motor.dart) y lo va explicando de a un paso por vez, con
/// "Atrás"/"Siguiente" y "Salir del tutorial" siempre visible.
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
    void arrancarRecorrido() {
      final pasos = tema.pasos();
      // Ver tutorial_motor.dart: el recorrido en sí (resaltar cada paso sin
      // bloquear el toque real, seguir al campo si la pantalla scrollea,
      // avanzar solo cuando el usuario toca de verdad lo resaltado) vive
      // ahí, no acá -este botón solo decide CUÁNDO arrancarlo (el menú de
      // temas, la bienvenida opcional).
      iniciarRecorridoTutorial(
        context,
        pasos,
        onFinish: () {
          if (!context.mounted) return;
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
      );
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
}
