import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/actualizacion_service.dart';

/// Diálogo central de respaldo para cuando "Buscar actualizaciones" no pudo
/// completar el chequeo automático (sin internet, un problema de
/// certificado SSL específico de ese equipo, etc. -visto en un caso real
/// donde el navegador de esa misma PC sí conectaba bien, solo la app
/// fallaba-). En vez de un SnackBar con un link a la página de releases (que
/// obliga a un clic más para encontrar el .exe), el botón "Actualizar" abre
/// directo la URL `releases/latest/download/CkSRL.exe`: GitHub redirige eso
/// al asset de la versión más nueva sin importar cuál sea, y como es la URL
/// directa del archivo (no la página HTML), el navegador empieza a
/// descargarlo solo, sin ningún clic extra -para que esto funcione, cada
/// release tiene que subir además una copia con este nombre fijo, ver
/// memoria del proyecto-.
Future<void> mostrarDialogoActualizacionRespaldo(BuildContext context, String motivoFallo) {
  return showDialog(
    useRootNavigator: false,
    context: context,
    builder: (context) => _ActualizacionRespaldoDialog(motivoFallo: motivoFallo),
  );
}

class _ActualizacionRespaldoDialog extends StatelessWidget {
  final String motivoFallo;
  const _ActualizacionRespaldoDialog({required this.motivoFallo});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('No se pudo revisar automáticamente', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: const Color(0xFF0F1B3D))),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No se pudo conectar para revisar si hay una versión nueva. Puede que este equipo tenga un problema de red o de certificado de seguridad puntual.',
              style: GoogleFonts.poppins(fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Tocá "Actualizar" para abrir la descarga directamente en el navegador -si ya estás al día, no pasa nada, simplemente reinstala la misma versión-.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Text(motivoFallo, style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade400)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar', style: GoogleFonts.poppins(color: Colors.grey.shade700))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F1B3D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () {
            ActualizacionService.abrirDescargaDirecta();
            Navigator.pop(context);
          },
          child: Text('Actualizar', style: GoogleFonts.poppins(color: Colors.white)),
        ),
      ],
    );
  }
}
