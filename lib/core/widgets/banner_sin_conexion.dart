import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';

/// Banner global, no invasivo pero imposible de no notar, que aparece en la
/// parte de arriba de la pantalla mientras no hay conexión a internet. Con
/// Supabase esto es más crítico que con Firestore (que tenía caché/
/// persistencia offline nativa): sin este aviso, un cajero sin internet
/// solo se entera de que algo falló cuando intenta guardar y le sale un
/// error -o, peor, ni eso, si ese error queda tragado en un catch
/// silencioso, como pasaba en toda la familia de apps hasta ahora-.
///
/// Se engancha una sola vez en la shell principal de la app (ver
/// AppShell), después del login: se anima entrando/saliendo con altura 0,
/// sin desplazar el resto de la UI de golpe.
class BannerSinConexion extends ConsumerWidget {
  const BannerSinConexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conectividad = ref.watch(conectividadProvider);
    // Mientras no se sepa nada todavía (loading) o si falló la lectura, no se
    // muestra nada -mejor no molestar de más que dar un falso positivo-.
    final hayConexion = conectividad.asData?.value ?? true;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: hayConexion
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              width: double.infinity,
              color: const Color(0xFFB71C1C),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Sin conexión a internet — lo que hagas ahora puede no guardarse',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
