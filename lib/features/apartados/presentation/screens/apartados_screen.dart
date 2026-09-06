import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_model.dart';
import '../../providers/apartados_provider.dart';
import '../../../../core/utils/texto_utils.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import 'crear_apartado_screen.dart';
import 'detalle_apartado_screen.dart';

/// Notifiers de búsqueda/vista de este módulo -se scopean por pestaña en
/// pantalla_builder.dart (mismo mecanismo que Ventas a Crédito/Inventario/
/// Clientes/etc.), así que escribir en el buscador de una pestaña no se
/// refleja en otra pestaña de Apartados abierta al mismo tiempo.
class ApartadosBusquedaNotifier extends Notifier<String> {
  @override
  String build() => '';
  void actualizar(String valor) => state = valor;
}

final apartadosBusquedaProvider = NotifierProvider<ApartadosBusquedaNotifier, String>(ApartadosBusquedaNotifier.new);

class ApartadosVistaNotifier extends Notifier<String> {
  @override
  String build() => 'activo';
  void actualizar(String valor) => state = valor;
}

final apartadosVistaProvider = NotifierProvider<ApartadosVistaNotifier, String>(ApartadosVistaNotifier.new);

class ApartadosScreen extends ConsumerStatefulWidget {
  const ApartadosScreen({super.key});

  @override
  ConsumerState<ApartadosScreen> createState() => _ApartadosScreenState();
}

class _ApartadosScreenState extends ConsumerState<ApartadosScreen> {
  final _busquedaController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  void _buscar() {
    ref.read(apartadosBusquedaProvider.notifier).actualizar(_busquedaController.text.trim());
  }

  void _limpiarBusqueda() {
    _busquedaController.clear();
    ref.read(apartadosBusquedaProvider.notifier).actualizar('');
  }

  Future<void> _abrirCrear() async {
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => const CrearApartadoScreen()),
    );
  }

  Future<void> _abrirDetalle(ApartadoModel apartado) async {
    await Navigator.of(context).push(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => DetalleApartadoScreen(idApartado: apartado.id)),
    );
  }

  Widget _chipEstado(ApartadoModel a) {
    final (color, texto) = switch (a.estado) {
      'completado' => (const Color(0xFF16A34A), 'Entregado'),
      'cancelado' => (Colors.grey.shade600, 'Cancelado'),
      _ => (const Color(0xFF3B82F6), 'Activo'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(texto, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _chipModalidad(ApartadoModel a) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(8)),
      child: Text(
        a.esCuotasFijas ? 'Cuotas fijas' : 'Abonos libres',
        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF3F434A)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apartadosAsync = ref.watch(apartadosStreamProvider);
    final busqueda = ref.watch(apartadosBusquedaProvider);
    final vista = ref.watch(apartadosVistaProvider);
    final saldos = ref.watch(saldosApartadosProvider);

    List<ApartadoModel>? listaFiltrada;
    if (apartadosAsync.hasValue) {
      var lista = apartadosAsync.value!;
      if (vista != 'todos') {
        lista = lista.where((a) => a.estado == vista).toList();
      }
      if (busqueda.isNotEmpty) {
        lista = lista.where((a) => coincideFuzzy(a.textoBusqueda, busqueda)).toList();
      }
      listaFiltrada = lista;
    }

    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 760;
          return Padding(
            padding: EdgeInsets.all(esMovil ? 14 : 26),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: Text(
                    'Apartados',
                    style: GoogleFonts.poppins(fontSize: esMovil ? 19 : 22, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(width: esMovil ? constraints.maxWidth : 200, child: _selectorVista(vista)),
                      SizedBox(width: esMovil ? constraints.maxWidth : 300, child: _buscador(busqueda)),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(apartadosStreamProvider),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text('Refrescar', style: GoogleFonts.poppins(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFB6BCC7)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _abrirCrear,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text('Nuevo Apartado', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F1B3D),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 18)),
              ],
              body: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFAEB4C0), width: 1.3),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 26, offset: const Offset(0, 12))],
                ),
                child: apartadosAsync.when(
                  data: (_) {
                    final lista = listaFiltrada!;
                    if (lista.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_bag_outlined, size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No hay apartados para mostrar', style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    }
                    return esMovil ? _tarjetas(lista, saldos) : _tabla(lista, saldos);
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF0F1B3D))),
                  error: (e, st) => Center(child: Text('Error: $e', style: GoogleFonts.poppins(color: Colors.red))),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _selectorVista(String vista) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: vista,
          isExpanded: true,
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF1A1A1A)),
          items: const [
            DropdownMenuItem(value: 'activo', child: Text('Activos')),
            DropdownMenuItem(value: 'completado', child: Text('Entregados')),
            DropdownMenuItem(value: 'cancelado', child: Text('Cancelados')),
            DropdownMenuItem(value: 'todos', child: Text('Todos')),
          ],
          onChanged: (v) {
            if (v == null) return;
            ref.read(apartadosVistaProvider.notifier).actualizar(v);
          },
        ),
      ),
    );
  }

  Widget _buscador(String busqueda) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB6BCC7))),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: CampoTecladoCompacto(
              controller: _busquedaController,
              numerico: false,
              onSubmitted: (_) => _buscar(),
              titulo: 'Buscar por cliente...',
              child: TextField(
                inputFormatters: [mayusculasInputFormatter],
                autocorrect: false,
                enableSuggestions: false,
                controller: _busquedaController,
                style: GoogleFonts.poppins(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por cliente...',
                  hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _buscar(),
              ),
            ),
          ),
          if (busqueda.isNotEmpty) IconButton(tooltip: 'Limpiar', icon: const Icon(Icons.close, size: 18), onPressed: _limpiarBusqueda),
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _buscar),
        ],
      ),
    );
  }

  Widget _tabla(List<ApartadoModel> lista, Map<String, double> saldos) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return ListView.builder(
      itemCount: lista.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFECEEF3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                _celdaHeader('FECHA', 2),
                _celdaHeader('CLIENTE', 3),
                _celdaHeader('MODALIDAD', 2),
                _celdaHeader('MONTO TOTAL', 2),
                _celdaHeader('SALDO PENDIENTE', 2),
                _celdaHeader('ESTADO', 2),
              ],
            ),
          );
        }
        final a = lista[index - 1];
        final saldo = saldos[a.id] ?? (a.montoTotal - a.montoInicial);
        return Column(
          children: [
            if (index > 1) Divider(height: 1, color: Colors.grey.shade200),
            InkWell(
              onTap: () => _abrirDetalle(a),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _celda(2, a.fechaCreacion != null ? formatoFecha.format(a.fechaCreacion!) : '-', gris: true),
                    _celda(3, a.nombreCliente, peso: FontWeight.w600),
                    Expanded(flex: 2, child: _chipModalidad(a)),
                    _celda(2, formatearMoneda(a.montoTotal), gris: true),
                    _celda(2, formatearMoneda(saldo), peso: FontWeight.w700),
                    Expanded(flex: 2, child: _chipEstado(a)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _celdaHeader(String texto, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF666A72), letterSpacing: 0.3),
      ),
    );
  }

  Widget _celda(int flex, String texto, {bool gris = false, FontWeight peso = FontWeight.w400}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: peso, color: gris ? Colors.grey.shade600 : const Color(0xFF1A1A1A)),
        ),
      ),
    );
  }

  Widget _tarjetas(List<ApartadoModel> lista, Map<String, double> saldos) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: lista.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final a = lista[index];
        final saldo = saldos[a.id] ?? (a.montoTotal - a.montoInicial);
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _abrirDetalle(a),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.nombreCliente, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                          Text(
                            a.fechaCreacion != null ? formatoFecha.format(a.fechaCreacion!) : '-',
                            style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    _chipEstado(a),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipModalidad(a),
                    _chipInfo('Monto total', formatearMoneda(a.montoTotal)),
                    _chipInfo('Saldo pendiente', formatearMoneda(saldo)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chipInfo(String label, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF0), borderRadius: BorderRadius.circular(8)),
      child: Text('$label: $valor', style: GoogleFonts.poppins(fontSize: 11.5, color: const Color(0xFF3F434A))),
    );
  }
}
