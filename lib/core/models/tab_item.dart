import 'package:flutter/material.dart';

class TabItem {
  final String id;
  final String titulo;
  final IconData icono;
  final Widget contenido;
  final bool cerrable;

  TabItem({
    required this.id,
    required this.titulo,
    required this.icono,
    required this.contenido,
    this.cerrable = true,
  });
}