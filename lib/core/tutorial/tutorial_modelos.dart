import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
export 'package:tutorial_coach_mark/tutorial_coach_mark.dart' show ContentAlign;

/// Cómo se avanza al siguiente paso de un tutorial -ver TutorialMotor,
/// pedido explícito del dueño: "quiero que el cliente vaya tocando haciendo
/// mientras lo van guiando", no solo lea texto y apriete "Siguiente"-.
enum TutorialAvance {
  /// El paso avanza solo cuando el usuario toca de verdad el campo/botón
  /// real resaltado -el toque SÍ llega al widget real (abre el diálogo,
  /// guarda, etc.), el tutorial no lo bloquea-. Este es el modo normal:
  /// casi todo paso apunta a algo que se puede tocar. "Siguiente" sigue
  /// disponible igual, por si el usuario prefiere solo leer y avanzar.
  tocar,

  /// No hay ninguna acción real que hacer en este paso (es un dato
  /// informativo, ej. "acá se ve el total" sobre un texto de solo lectura):
  /// se avanza solo con el botón "Siguiente" de la tarjeta.
  manual,
}

/// Un paso de un tutorial guiado: resalta el widget real de [key] (con el
/// resto de la pantalla oscurecido, pero sin bloquear el toque real -ver
/// TutorialMotor-) y explica qué es/para qué sirve en lenguaje bien simple
/// -pedido explícito del dueño: "explicado como si fuera un tonto", pensado
/// para alguien que recién está aprendiendo a usar una computadora, no solo
/// el sistema-.
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
  final TutorialAvance avance;

  const TutorialPaso({
    required this.key,
    required this.titulo,
    required this.explicacion,
    this.obligatorio,
    this.alineacion = ContentAlign.bottom,
    this.avance = TutorialAvance.tocar,
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
  // Se llama justo cuando el recorrido arranca de verdad (después de la
  // bienvenida, si tiene) -pedido explícito del dueño: encadenar el
  // tutorial de una pantalla con el de un diálogo que abre desde ahí (ver
  // AjusteStockDialog/InventarioScreen), para que se sienta un solo
  // recorrido continuo en vez de dos tutoriales separados-.
  final VoidCallback? alEmpezar;

  const TutorialTema({
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.pasos,
    this.bienvenida,
    this.alEmpezar,
  });
}
