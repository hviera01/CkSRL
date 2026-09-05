import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  final String titulo;
  final IconData icono;

  const PlaceholderScreen({super.key, required this.titulo, required this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F3F7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text('Pantalla en construcción', style: TextStyle(color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}