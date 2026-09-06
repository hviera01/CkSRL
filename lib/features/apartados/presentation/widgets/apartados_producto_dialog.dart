import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/apartados_provider.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../screens/detalle_apartado_screen.dart';

/// Diálogo chico que se abre desde el badge "N apartados" de Inventario
/// (ver InventarioScreen): lista los apartados ACTIVOS que tienen reservado
/// este producto -acceso rápido a cada uno sin tener que ir a buscarlo a
/// mano en el módulo Apartados-.
class ApartadosProductoDialog extends ConsumerWidget {
  final String idProducto;
  final String nombreProducto;

  const ApartadosProductoDialog({super.key, required this.idProducto, required this.nombreProducto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desglose = ref.watch(apartadosActivosPorProductoProvider(idProducto));
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.1), borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF6D28D9)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Apartados de "$nombreProducto"',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: desglose.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text('Sin apartados activos', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: desglose.length,
                      separatorBuilder: (context, i) => Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, i) {
                        final fila = desglose[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(fila.apartado.nombreCliente, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Cantidad apartada: ${fila.cantidad.toStringAsFixed(fila.cantidad == fila.cantidad.roundToDouble() ? 0 : 2)} · ${formatearMoneda(fila.apartado.montoTotal)}',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () {
                            // Se guarda el Navigator ANTES de cerrar el diálogo -su
                            // propio BuildContext (el de este ListTile) deja de ser
                            // válido apenas se cierra, pero el NavigatorState en sí
                            // sigue vivo (es el de la pestaña, no el del diálogo).
                            final navigator = Navigator.of(context);
                            navigator.pop();
                            navigator.push(
                              MaterialPageRoute(fullscreenDialog: true, builder: (context) => DetalleApartadoScreen(idApartado: fila.apartado.id)),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
