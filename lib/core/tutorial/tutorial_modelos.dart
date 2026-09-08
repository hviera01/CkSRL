import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
export 'package:tutorial_coach_mark/tutorial_coach_mark.dart' show ContentAlign;

/// Un paso de un tutorial guiado: resalta el widget real de [key] (con el
/// resto de la pantalla oscurecido) y explica qué es/para qué sirve en
/// lenguaje bien simple -pedido explícito del dueño: "explicado como si
/// fuera un tonto", pensado para alguien que recién está aprendiendo a usar
/// una computadora, no solo el sistema-.
///
/// [obligatorio] marca en el texto si ese campo es obligatorio o se puede
/// dejar vacío -otro pedido explícito: que el tutorial aclare esto siempre-.
/// Dejalo null cuando el paso no es sobre un campo (ej. un botón, una
/// pestaña, un concepto general).
class TutorialPaso {
  final GlobalKey key;
  final String titulo;
  final String explicacion;
  final bool? obligatorio;
  final ContentAlign alineacion;

  const TutorialPaso({
    required this.key,
    required this.titulo,
    required this.explicacion,
    this.obligatorio,
    this.alineacion = ContentAlign.bottom,
  });
}

/// Un tema completo de tutorial (ej. "Cómo hacer una venta al contado"),
/// una opción del menú que abre TutorialBoton en cada pantalla.
///
/// [pasos] es una función (no una lista fija) a propósito: las GlobalKey de
/// los widgets reales recién tienen una posición válida en pantalla después
/// del primer build, así que arman la lista de TutorialPaso recién cuando el
/// usuario elige este tema, nunca antes.
class TutorialTema {
  final String titulo;
  final String descripcion;
  final IconData icono;
  final List<TutorialPaso> Function() pasos;
  final String? bienvenida;

  const TutorialTema({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.pasos,
    this.bienvenida,
  });
}
