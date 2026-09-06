import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../data/apartado_repository.dart';
import '../../../clientes/data/cliente_model.dart';
import '../../../ventas/presentation/widgets/buscar_cliente_dialog.dart';
import '../../../../core/utils/formato_moneda.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';

/// Parte común de "armar un apartado" -cliente, pago inicial (% o monto
/// fijo), modalidad de pago del resto y vista previa de las cuotas-, extraída
/// de CrearApartadoScreen para que la MISMA UI y el MISMO cálculo se usen
/// también al apartar el carrito desde Registrar Venta (ver
/// ApartarCarritoDialog). Lo único que cambia entre los dos lados es de dónde
/// salen los productos: acá no se toca esa parte.

/// Reparte [saldoRestante] en partes iguales entre [numeroCuotas], ajustando
/// el residuo de redondeo en la última cuota (para que la suma exacta de las
/// cuotas cuadre centavo a centavo con el saldo restante). Las fechas salen
/// de [desde] (hoy por defecto) sumando [intervaloDias] por cuota.
List<NuevaCuota> calcularCuotasApartado({
  required double saldoRestante,
  required int numeroCuotas,
  required int intervaloDias,
  DateTime? desde,
}) {
  if (numeroCuotas <= 0 || intervaloDias <= 0) return const [];
  final montoBase = redondearMoneda(saldoRestante / numeroCuotas);
  final base = desde ?? DateTime.now();
  final dia = DateTime(base.year, base.month, base.day);
  final cuotas = <NuevaCuota>[];
  var acumulado = 0.0;
  for (var i = 1; i <= numeroCuotas; i++) {
    final esUltima = i == numeroCuotas;
    final monto = esUltima ? redondearMoneda(saldoRestante - acumulado) : montoBase;
    acumulado = redondearMoneda(acumulado + monto);
    cuotas.add(NuevaCuota(
      numeroCuota: i,
      montoProgramado: monto,
      fechaProgramada: dia.add(Duration(days: intervaloDias * i)),
    ));
  }
  return cuotas;
}

/// Estado editable del apartado que se está armando (todo lo que NO son los
/// productos). Vive en el State de quien lo usa -CrearApartadoScreen o
/// ApartarCarritoDialog-, que además es el que decide cuándo redibujar:
/// ConfiguracionApartadoForm avisa cada cambio por su callback `alCambiar`.
class ConfiguracionApartadoController {
  final TextEditingController clienteController;
  /// Vínculo real al registro de 'clientes' (null si el nombre se tipeó a
  /// mano): se limpia apenas se edita el texto, para no dejar un vínculo
  /// falso -mismo criterio que el carrito de Registrar Venta-.
  String? idCliente;

  // Pago inicial: por porcentaje del total, o un monto fijo tipeado a mano.
  bool inicialPorPorcentaje = true;
  final porcentajeController = TextEditingController(text: '50');
  final montoInicialController = TextEditingController();

  String modalidad = 'abonos_libres';
  final numeroCuotasController = TextEditingController(text: '2');
  final intervaloDiasController = TextEditingController(text: '15');

  ConfiguracionApartadoController({String nombreClienteInicial = '', this.idCliente})
      : clienteController = TextEditingController(text: nombreClienteInicial);

  void dispose() {
    clienteController.dispose();
    porcentajeController.dispose();
    montoInicialController.dispose();
    numeroCuotasController.dispose();
    intervaloDiasController.dispose();
  }

  static double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;
  static int _parseInt(String texto) => int.tryParse(texto.trim()) ?? 0;

  String get nombreCliente => clienteController.text.trim();
  int get numeroCuotas => _parseInt(numeroCuotasController.text);
  int get intervaloDias => _parseInt(intervaloDiasController.text);

  double montoInicialSobre(double montoTotal) {
    if (inicialPorPorcentaje) {
      final porcentaje = _parseDouble(porcentajeController.text).clamp(0, 100);
      return redondearMoneda(montoTotal * porcentaje / 100);
    }
    return redondearMoneda(_parseDouble(montoInicialController.text));
  }

  double saldoRestanteSobre(double montoTotal) {
    final saldo = montoTotal - montoInicialSobre(montoTotal);
    return saldo < 0 ? 0 : saldo;
  }

  List<NuevaCuota> cuotasSobre(double montoTotal) {
    if (modalidad != 'cuotas_fijas') return const [];
    return calcularCuotasApartado(
      saldoRestante: saldoRestanteSobre(montoTotal),
      numeroCuotas: numeroCuotas,
      intervaloDias: intervaloDias,
    );
  }

  /// Devuelve el mensaje de error a mostrar, o null si está todo bien (las
  /// mismas validaciones para los dos lados; la existencia real de cada
  /// producto la valida el servidor en `crear_apartado`).
  String? validar(double montoTotal) {
    if (nombreCliente.isEmpty) return 'Elegí (o escribí) el cliente';
    final inicial = montoInicialSobre(montoTotal);
    if (inicial > montoTotal + 0.01) return 'El pago inicial no puede superar el monto total';
    if (inicial < 0) return 'El pago inicial no puede ser negativo';
    if (modalidad == 'cuotas_fijas') {
      if (numeroCuotas <= 0) return 'Ingresá un número de cuotas válido';
      if (intervaloDias <= 0) return 'Ingresá cada cuántos días válido';
    }
    return null;
  }
}

InputDecoration decoracionApartado(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.poppins(fontSize: 13),
    filled: true,
    fillColor: const Color(0xFFE8EAF0),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );
}

/// Tarjeta blanca con título (y acción opcional a la derecha) usada por todas
/// las secciones del armado de un apartado.
Widget tarjetaApartado({required String titulo, required Widget child, Widget? accion}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7CBD3))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(titulo, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700))),
            ?accion,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

Widget filaResumenApartado(String etiqueta, String valor, {bool destacado = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(etiqueta, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
        Text(
          valor,
          style: GoogleFonts.poppins(
            fontSize: destacado ? 16 : 13.5,
            fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
            color: destacado ? const Color(0xFF0F1B3D) : const Color(0xFF1A1A1A),
          ),
        ),
      ],
    ),
  );
}

/// Las tres tarjetas comunes (Cliente / Pago inicial / Modalidad) sobre un
/// [montoTotal] que calcula quien la usa: la suma de los productos elegidos
/// en CrearApartadoScreen, o la del carrito en Registrar Venta.
///
/// [seccionProductos] se inserta entre Cliente y Pago inicial: cada lado
/// muestra los productos a su manera (editable con "Agregar producto" en
/// CrearApartadoScreen, solo lectura -ya vienen del carrito- en
/// ApartarCarritoDialog), pero el orden de las tarjetas es el mismo.
class ConfiguracionApartadoForm extends StatelessWidget {
  final ConfiguracionApartadoController controller;
  final double montoTotal;
  final VoidCallback alCambiar;
  final Widget? seccionProductos;

  const ConfiguracionApartadoForm({
    super.key,
    required this.controller,
    required this.montoTotal,
    required this.alCambiar,
    this.seccionProductos,
  });

  Future<void> _buscarCliente(BuildContext context) async {
    final cliente = await showDialog<ClienteModel>(
      useRootNavigator: false,
      context: context,
      builder: (context) => const BuscarClienteDialog(),
    );
    if (cliente == null) return;
    controller.clienteController.text = cliente.nombreCompleto;
    controller.idCliente = cliente.id;
    alCambiar();
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy');
    final montoInicial = controller.montoInicialSobre(montoTotal);
    final saldoRestante = controller.saldoRestanteSobre(montoTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tarjetaApartado(
          titulo: 'Cliente',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CampoTecladoCompacto(
                  controller: controller.clienteController,
                  numerico: false,
                  child: TextField(
                    inputFormatters: [mayusculasInputFormatter],
                    autocorrect: false,
                    enableSuggestions: false,
                    controller: controller.clienteController,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: decoracionApartado('Cliente'),
                    onChanged: (_) {
                      // Tipeó a mano: el vínculo al cliente elegido antes ya
                      // no es confiable.
                      if (controller.idCliente == null) return;
                      controller.idCliente = null;
                      alCambiar();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Buscar cliente registrado',
                onPressed: () => _buscarCliente(context),
                icon: const Icon(Icons.search),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE8EAF0),
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (seccionProductos != null) ...[
          seccionProductos!,
          const SizedBox(height: 14),
        ],
        tarjetaApartado(
          titulo: 'Pago inicial',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: Text('Porcentaje', style: GoogleFonts.poppins(fontSize: 12.5)),
                    selected: controller.inicialPorPorcentaje,
                    onSelected: (v) {
                      controller.inicialPorPorcentaje = true;
                      alCambiar();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Monto fijo', style: GoogleFonts.poppins(fontSize: 12.5)),
                    selected: !controller.inicialPorPorcentaje,
                    onSelected: (v) {
                      controller.inicialPorPorcentaje = false;
                      alCambiar();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (controller.inicialPorPorcentaje)
                CampoTecladoCompacto(
                  controller: controller.porcentajeController,
                  numerico: true,
                  child: TextField(
                    controller: controller.porcentajeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: decoracionApartado('Porcentaje (%)'),
                    onChanged: (_) => alCambiar(),
                  ),
                )
              else
                CampoTecladoCompacto(
                  controller: controller.montoInicialController,
                  numerico: true,
                  child: TextField(
                    controller: controller.montoInicialController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: decoracionApartado('Monto inicial'),
                    onChanged: (_) => alCambiar(),
                  ),
                ),
              const SizedBox(height: 12),
              filaResumenApartado('Monto total', formatearMoneda(montoTotal)),
              filaResumenApartado('Pago inicial', formatearMoneda(montoInicial)),
              filaResumenApartado('Saldo a financiar', formatearMoneda(saldoRestante), destacado: true),
            ],
          ),
        ),
        const SizedBox(height: 14),
        tarjetaApartado(
          titulo: 'Modalidad de pago del resto',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: Text('Abonos libres', style: GoogleFonts.poppins(fontSize: 12.5)),
                    selected: controller.modalidad == 'abonos_libres',
                    onSelected: (v) {
                      controller.modalidad = 'abonos_libres';
                      alCambiar();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Cuotas fijas', style: GoogleFonts.poppins(fontSize: 12.5)),
                    selected: controller.modalidad == 'cuotas_fijas',
                    onSelected: (v) {
                      controller.modalidad = 'cuotas_fijas';
                      alCambiar();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (controller.modalidad == 'abonos_libres')
                Text(
                  'El cliente abona lo que puede, cuando puede -sin monto ni fecha fija por cuota-.',
                  style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: CampoTecladoCompacto(
                        controller: controller.numeroCuotasController,
                        numerico: true,
                        child: TextField(
                          controller: controller.numeroCuotasController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: decoracionApartado('Número de cuotas'),
                          onChanged: (_) => alCambiar(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CampoTecladoCompacto(
                        controller: controller.intervaloDiasController,
                        numerico: true,
                        child: TextField(
                          controller: controller.intervaloDiasController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: decoracionApartado('Cada cuántos días'),
                          onChanged: (_) => alCambiar(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final cuota in controller.cuotasSobre(montoTotal))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('Cuota ${cuota.numeroCuota}', style: GoogleFonts.poppins(fontSize: 12.5)),
                        const Spacer(),
                        Text(formatearMoneda(cuota.montoProgramado), style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 14),
                        Text(formatoFecha.format(cuota.fechaProgramada), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Recuadro rojo de error, igual en las dos pantallas.
Widget errorApartado(String mensaje) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Text(mensaje, style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 12)),
  );
}
