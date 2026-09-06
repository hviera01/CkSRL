import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/reporte_financiero_model.dart';
import '../../data/reporte_financiero_export_service.dart';
import '../../providers/reportes_provider.dart';
import '../../../../core/widgets/pdf_preview_dialog.dart';
import '../widgets/reporte_financiero_secciones.dart';

typedef _SeccionBuilder =
    Widget Function(ReporteFinancieroData data, bool esMovil);

const _tabs = <(String, IconData, _SeccionBuilder)>[
  ('Utilidad', Icons.trending_up_outlined, seccionUtilidad),
  (
    'Flujo de Efectivo',
    Icons.account_balance_wallet_outlined,
    seccionFlujoEfectivo,
  ),
  (
    'Comparación Mensual',
    Icons.calendar_month_outlined,
    seccionComparacionMensual,
  ),
  ('Ranking de Productos', Icons.leaderboard_outlined, seccionRankingProductos),
  ('Sin Movimiento', Icons.inventory_2_outlined, seccionProductosSinVenta),
  ('Ventas por Usuario', Icons.people_outline, seccionVentasPorUsuario),
  (
    'Abonos a Proveedores',
    Icons.payments_outlined,
    seccionAbonosComprasCredito,
  ),
  ('Recomendación de Pago', Icons.lightbulb_outline, seccionRecomendacionPago),
  ('Balance General', Icons.account_balance_outlined, seccionBalanceGeneral),
  (
    'Inteligencia de Negocios',
    Icons.psychology_outlined,
    seccionInteligenciaNegocio,
  ),
  ('Clientes', Icons.groups_outlined, seccionClientes),
];

/// Reporte Financiero: un solo módulo del menú, con todas sus secciones
/// como pestañas internas — un único rango de fechas y un único cálculo
/// (`ReporteFinancieroData`) alimenta todas las pestañas, así que cambiar de
/// pestaña no dispara ninguna consulta nueva.
class ReporteFinancieroScreen extends ConsumerStatefulWidget {
  const ReporteFinancieroScreen({super.key});

  @override
  ConsumerState<ReporteFinancieroScreen> createState() =>
      _ReporteFinancieroScreenState();
}

class _ReporteFinancieroScreenState
    extends ConsumerState<ReporteFinancieroScreen> {
  final _servicioExport = ReporteFinancieroExportService();
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  bool _cargando = false;
  String? _error;
  ReporteFinancieroData? _data;

  // Tablas cuyo primer evento de Realtime (el snapshot inicial de la
  // suscripción, no un cambio real) ya se descartó -ver _escucharCambios-.
  final _tablasConSnapshotInicialListo = <String>{};

  // Tablas que alimentan el reporte financiero y, al cambiar, deben
  // re-disparar _generar() -mismo rango de fecha ya elegido, sin resetear
  // nada- para que el reporte no quede desactualizado si el dueño lo deja
  // abierto en una pestaña y sigue vendiendo/comprando en otra.
  static const _tablasQueAfectanReporte = [
    'ventas',
    'compras',
    'egresos',
    'venta_credito_abonos',
    'compra_credito_abonos',
  ];

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaInicio = DateTime(ahora.year, ahora.month, ahora.day);
    _fechaFin = DateTime(ahora.year, ahora.month, ahora.day);
    _generar();
  }

  // Atajos de rango rápido: tocar uno aplica el rango y dispara la
  // generación del reporte de una vez, sin tener que abrir el selector de
  // fecha dos veces.
  void _aplicarRango(DateTime inicio, DateTime fin) {
    setState(() {
      _fechaInicio = inicio;
      _fechaFin = fin;
    });
    _generar();
  }

  List<(String, DateTime, DateTime)> get _rangosRapidos {
    final hoy = DateTime.now();
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final ayer = hoyDia.subtract(const Duration(days: 1));
    final inicioSemana = hoyDia.subtract(const Duration(days: 6));
    final inicioMes = DateTime(hoy.year, hoy.month, 1);
    final mesTrimestre = ((hoy.month - 1) ~/ 3) * 3 + 1;
    final inicioTrimestre = DateTime(hoy.year, mesTrimestre, 1);
    return [
      ('Hoy', hoyDia, hoyDia),
      ('Ayer', ayer, ayer),
      ('Semana', inicioSemana, hoyDia),
      ('Mes', inicioMes, hoyDia),
      ('Trimestre', inicioTrimestre, hoyDia),
    ];
  }

  bool _esRangoActivo(DateTime inicio, DateTime fin) {
    return _fechaInicio.year == inicio.year &&
        _fechaInicio.month == inicio.month &&
        _fechaInicio.day == inicio.day &&
        _fechaFin.year == fin.year &&
        _fechaFin.month == fin.month &&
        _fechaFin.day == fin.day;
  }

  Widget _chipsRangoRapido() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in _rangosRapidos)
          ChoiceChip(
            label: Text(r.$1, style: GoogleFonts.poppins(fontSize: 12.5)),
            selected: _esRangoActivo(r.$2, r.$3),
            onSelected: (_) => _aplicarRango(r.$2, r.$3),
            selectedColor: const Color(0xFF0F1B3D),
            labelStyle: GoogleFonts.poppins(
              fontSize: 12.5,
              color: _esRangoActivo(r.$2, r.$3)
                  ? Colors.white
                  : const Color(0xFF1A1A1A),
            ),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFB6BCC7)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
      ],
    );
  }

  Future<void> _generar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final finInclusive = DateTime(
        _fechaFin.year,
        _fechaFin.month,
        _fechaFin.day,
        23,
        59,
        59,
      );
      final data = await ref
          .read(reporteFinancieroRepositoryProvider)
          .obtenerReporte(_fechaInicio, finInclusive);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo generar el reporte: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Re-dispara _generar() (mismo rango de fecha ya elegido, sin resetear
  // nada) cuando algo cambia en [tabla] -mismo mecanismo que
  // ReporteVentasScreen/ReporteComprasScreen, ver ese comentario para el
  // detalle-.
  void _escucharCambios(String tabla) {
    ref.listen<AsyncValue<void>>(cambiosEnTablaProvider(tabla), (
      previous,
      next,
    ) {
      if (!next.hasValue || !mounted) return;
      if (_tablasConSnapshotInicialListo.add(tabla)) return;
      if (!_cargando) _generar();
    });
  }

  Future<void> _seleccionarFecha(bool esInicio) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: esInicio ? _fechaInicio : _fechaFin,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (fecha == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = fecha;
      } else {
        _fechaFin = fecha;
      }
    });
  }

  void _descargarPdf() {
    final data = _data;
    if (data == null) return;
    showDialog(
      useRootNavigator: false,
      context: context,
      builder: (context) => PdfPreviewDialog(
        titulo: 'Vista previa · Reporte Financiero',
        nombreArchivo: 'reporte_financiero.pdf',
        generarPdf: () => _servicioExport.generarPdf(data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    for (final tabla in _tablasQueAfectanReporte) {
      _escucharCambios(tabla);
    }
    return Container(
      color: const Color(0xFFF2F3F7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(esMovil ? 14 : 24),
                child: _encabezado(esMovil),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  esMovil ? 14 : 24,
                  0,
                  esMovil ? 14 : 24,
                  esMovil ? 14 : 24,
                ),
                child: _chipsRangoRapido(),
              ),
              if (_cargando)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF0F1B3D)),
                  ),
                ),
              if (_error != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _error!,
                        style: GoogleFonts.poppins(color: Colors.red),
                      ),
                    ),
                  ),
                ),
              if (!_cargando && _error == null && _data != null)
                Expanded(child: _tabsYContenido(_data!, esMovil)),
            ],
          );
        },
      ),
    );
  }

  Widget _tabsYContenido(ReporteFinancieroData data, bool esMovil) {
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: Builder(
              builder: (context) {
                // Con tantas pestañas (llegó "Clientes" al final) no entran
                // todas de una en pantallas normales: isScrollable ya
                // permite arrastrar/hacer scroll horizontal, pero eso no se
                // nota a simple vista con mouse -acá se agregan flechitas
                // que mueven la selección una pestaña a la vez y de paso la
                // traen a la vista (TabBar ya hace scroll automático hasta
                // la pestaña seleccionada).
                final controlador = DefaultTabController.of(context);
                return Row(
                  children: [
                    IconButton(
                      tooltip: 'Pestaña anterior',
                      icon: const Icon(Icons.chevron_left, size: 20),
                      color: Colors.grey.shade500,
                      onPressed: () {
                        final i = controlador.index;
                        if (i > 0) controlador.animateTo(i - 1);
                      },
                    ),
                    Expanded(
                      child: TabBar(
                        isScrollable: true,
                        labelColor: const Color(0xFF0F1B3D),
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: const Color(0xFF0F1B3D),
                        labelStyle: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                        tabs: [
                          for (final t in _tabs)
                            Tab(icon: Icon(t.$2, size: 18), text: t.$1),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Siguiente pestaña',
                      icon: const Icon(Icons.chevron_right, size: 20),
                      color: Colors.grey.shade500,
                      onPressed: () {
                        final i = controlador.index;
                        if (i < _tabs.length - 1) controlador.animateTo(i + 1);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final t in _tabs)
                  SingleChildScrollView(
                    padding: EdgeInsets.all(esMovil ? 14 : 24),
                    child: t.$3(data, esMovil),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado(bool esMovil) {
    final formato = DateFormat('dd/MM/yyyy');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Text(
          'Reporte Financiero',
          style: GoogleFonts.poppins(
            fontSize: esMovil ? 19 : 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        _campoFecha(
          'Desde',
          _fechaInicio,
          () => _seleccionarFecha(true),
          formato,
        ),
        _campoFecha(
          'Hasta',
          _fechaFin,
          () => _seleccionarFecha(false),
          formato,
        ),
        OutlinedButton.icon(
          onPressed: _cargando ? null : _generar,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text('Generar', style: GoogleFonts.poppins(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1A1A1A),
            side: const BorderSide(color: Color(0xFFB6BCC7)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _data == null ? null : _descargarPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(
            'Descargar PDF completo',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F1B3D),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _campoFecha(
    String label,
    DateTime fecha,
    VoidCallback onTap,
    DateFormat formato,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFB6BCC7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Text(
              '$label: ${formato.format(fecha)}',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
