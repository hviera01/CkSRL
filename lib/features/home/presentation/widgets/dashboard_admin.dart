import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../providers/dashboard_admin_provider.dart';

const _azulMarca = Color(0xFF0F1B3D);

/// Dashboard de un vistazo que SOLO ve el Administrador en Inicio -pedido
/// explícito del dueño-: ventas de la semana + un par de métricas más para
/// no tener que entrar a Reportes solo para ver cómo va el negocio hoy.
/// Los demás roles no ven nada de esto (ver HomeScreen, que decide con
/// `usuario.rol == Roles.administrador` si monta este widget).
class DashboardAdmin extends ConsumerWidget {
  const DashboardAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(dashboardAdminHomeProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _azulMarca,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _azulMarca.withOpacity(0.20),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.insights_rounded, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'Panel del dueño',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          estado.when(
            data: (d) => _contenido(context, d),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
            error: (_, __) => Text(
              'No se pudo cargar el resumen',
              style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.white.withOpacity(0.75)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido(BuildContext context, DashboardAdminData d) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final apilado = constraints.maxWidth < 620;
        final tarjetas = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _kpi(
              ancho: constraints.maxWidth,
              apilado: apilado,
              icono: Icons.calendar_view_week_rounded,
              etiqueta: 'Ventas de la semana',
              valor: formatearMoneda(d.totalSemana),
              subtitulo: '${d.cantidadVentasSemana} ${d.cantidadVentasSemana == 1 ? 'venta' : 'ventas'}',
            ),
            _kpi(
              ancho: constraints.maxWidth,
              apilado: apilado,
              icono: Icons.receipt_long_rounded,
              etiqueta: 'Ticket promedio',
              valor: formatearMoneda(d.ticketPromedioSemana),
              subtitulo: 'esta semana',
            ),
            _kpi(
              ancho: constraints.maxWidth,
              apilado: apilado,
              icono: Icons.event_available_rounded,
              etiqueta: 'Apartados activos',
              valor: formatearMoneda(d.saldoApartadosActivos),
              subtitulo: 'saldo pendiente',
            ),
          ],
        );

        final grafico = _graficoUltimos7Dias(d.serieUltimos7Dias);

        if (apilado) {
          return Column(
            children: [tarjetas, const SizedBox(height: 10), grafico],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: tarjetas),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: grafico),
          ],
        );
      },
    );
  }

  Widget _kpi({
    required double ancho,
    required bool apilado,
    required IconData icono,
    required String etiqueta,
    required String valor,
    required String subtitulo,
  }) {
    // 3 tarjetas por fila cuando hay espacio (escritorio), 1 por fila en
    // celular/tablet angosto (apilado, ver _contenido).
    final anchoTarjeta = apilado ? ancho : (ancho - 16) / 3;
    return Container(
      width: anchoTarjeta.clamp(120, 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: Colors.white.withOpacity(0.85), size: 14),
          const SizedBox(height: 6),
          Text(
            valor,
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          Text(
            etiqueta,
            style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85)),
          ),
          Text(
            subtitulo,
            style: GoogleFonts.poppins(fontSize: 9, color: Colors.white.withOpacity(0.60)),
          ),
        ],
      ),
    );
  }

  Widget _graficoUltimos7Dias(List<SerieDiaVenta> serie) {
    final maximo = serie.fold<double>(0, (m, s) => s.total > m ? s.total : m);
    final techo = maximo <= 0 ? 1.0 : maximo * 1.2;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Últimos 7 días',
            style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85)),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: BarChart(
              BarChartData(
                maxY: techo,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= serie.length) return const SizedBox.shrink();
                        final esHoy = i == serie.length - 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            serie[i].etiqueta,
                            style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              fontWeight: esHoy ? FontWeight.w700 : FontWeight.w400,
                              color: Colors.white.withOpacity(esHoy ? 0.95 : 0.55),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => Colors.white,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                      formatearMoneda(rod.toY),
                      GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: _azulMarca),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < serie.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: serie[i].total,
                          width: 16,
                          borderRadius: BorderRadius.circular(4),
                          color: i == serie.length - 1 ? Colors.white : Colors.white.withOpacity(0.45),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
