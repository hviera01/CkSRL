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

/// Una opción preestablecida de "cada cuánto" cae la próxima cuota -pedido
/// explícito del dueño: antes había que tipear un número de días a mano
/// (fácil de errar, ej. escribir 30 pensando en "un mes" que en realidad no
/// siempre son 30 días), ahora se elige de una lista corta con las
/// frecuencias reales de un negocio. [dias] se usa tal cual (Diario/
/// Semanal/Quincenal: no varían mes a mes, un `Duration` alcanza); Mensual/
/// Trimestral en cambio usan [meses] -mes de calendario real vía `DateTime`
/// (ver [_sumarMeses] abajo), más preciso que asumir 30/90 días fijos: así
/// una cuota "mensual" que cae el 31 sigue cayendo a fin de mes siguiente en
/// vez de irse corriendo con el tiempo-. Exactamente uno de los dos viene
/// en > 0 para cada opción.
class IntervaloApartado {
  final String id;
  final String etiqueta;
  final int dias;
  final int meses;

  const IntervaloApartado({required this.id, required this.etiqueta, this.dias = 0, this.meses = 0});
}

/// Mismas opciones que usa carrito_provider.dart en Ventas (sin 'Cheque' ni
/// 'Mixto': un pago de apartado es un solo movimiento, no una venta completa).
const List<String> metodosPagoApartado = ['Efectivo', 'Tarjeta', 'Transferencia'];

const List<IntervaloApartado> intervalosApartado = [
  IntervaloApartado(id: 'diario', etiqueta: 'Diario', dias: 1),
  IntervaloApartado(id: 'semanal', etiqueta: 'Semanal', dias: 7),
  IntervaloApartado(id: 'quincenal', etiqueta: 'Quincenal', dias: 15),
  IntervaloApartado(id: 'mensual', etiqueta: 'Mensual', meses: 1),
  IntervaloApartado(id: 'trimestral', etiqueta: 'Trimestral', meses: 3),
];

IntervaloApartado intervaloApartadoPorId(String id) =>
    intervalosApartado.firstWhere((i) => i.id == id, orElse: () => intervalosApartado[2]);

/// Suma [meses] de calendario real a [fecha] -mismo criterio que el resto de
/// la app no necesitaba hasta ahora: si el mes resultante no tiene ese día
/// (ej. 31 de enero + 1 mes), cae al último día de ese mes en vez de
/// "desbordar" a marzo (que es lo que haría sumar treinta y un días fijos).
DateTime _sumarMeses(DateTime fecha, int meses) {
  final anioTotal = fecha.year * 12 + (fecha.month - 1) + meses;
  final anio = anioTotal ~/ 12;
  final mes = anioTotal % 12 + 1;
  final ultimoDiaDelMes = DateTime(anio, mes + 1, 0).day;
  final dia = fecha.day > ultimoDiaDelMes ? ultimoDiaDelMes : fecha.day;
  return DateTime(anio, mes, dia);
}

/// Reparte [saldoRestante] en partes iguales entre [numeroCuotas], ajustando
/// el residuo de redondeo en la última cuota (para que la suma exacta de las
/// cuotas cuadre centavo a centavo con el saldo restante). Las fechas salen
/// de [desde] (hoy por defecto) sumando [intervaloDias] días o [intervaloMeses]
/// meses de calendario por cuota -exactamente uno de los dos > 0, ver
/// [IntervaloApartado]-.
List<NuevaCuota> calcularCuotasApartado({
  required double saldoRestante,
  required int numeroCuotas,
  int intervaloDias = 0,
  int intervaloMeses = 0,
  DateTime? desde,
}) {
  if (numeroCuotas <= 0 || (intervaloDias <= 0 && intervaloMeses <= 0)) return const [];
  final montoBase = redondearMoneda(saldoRestante / numeroCuotas);
  final base = desde ?? DateTime.now();
  final dia = DateTime(base.year, base.month, base.day);
  final cuotas = <NuevaCuota>[];
  var acumulado = 0.0;
  for (var i = 1; i <= numeroCuotas; i++) {
    final esUltima = i == numeroCuotas;
    final monto = esUltima ? redondearMoneda(saldoRestante - acumulado) : montoBase;
    acumulado = redondearMoneda(acumulado + monto);
    final fechaProgramada = intervaloMeses > 0 ? _sumarMeses(dia, intervaloMeses * i) : dia.add(Duration(days: intervaloDias * i));
    cuotas.add(NuevaCuota(numeroCuota: i, montoProgramado: monto, fechaProgramada: fechaProgramada));
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

  // Pago inicial SUGERIDO/planeado: por porcentaje del total, o un monto fijo
  // tipeado a mano -sirve solo de guía para armar las cuotas (ver
  // cuotasSobre) y queda como referencia histórica en apartados.monto_inicial-.
  bool inicialPorPorcentaje = true;
  final porcentajeController = TextEditingController(text: '50');
  final montoInicialController = TextEditingController();

  // Pago inicial REAL: lo que el cliente da de verdad al armar el apartado
  // -puede diferir del sugerido de arriba-, con su método de pago. Entra
  // como el PRIMER movimiento real de apartado_abonos (ver
  // ApartadoRepository.crearApartado), no como un campo estático. Sigue al
  // sugerido automáticamente hasta que el usuario lo edite a mano -ver
  // [sincronizarMontoInicialReal]-.
  final montoInicialRealController = TextEditingController();
  bool _montoInicialRealTocado = false;
  String metodoPagoInicial = 'Efectivo';

  String modalidad = 'abonos_libres';
  final numeroCuotasController = TextEditingController(text: '2');
  // Frecuencia entre cuotas, elegida de una lista corta (ver
  // [intervalosApartado]) en vez de un número de días libre -pedido
  // explícito del dueño-. 'quincenal' como default: mismo intervalo (15
  // días) que ya traía el campo numérico libre de antes.
  String intervaloPresetId = 'quincenal';

  // Fecha de la Cuota 1 -pedido explícito del dueño: por defecto sigue
  // saliendo automático (hoy + 1 frecuencia, ver calcularCuotasApartado),
  // pero el usuario puede elegir otra fecha a mano si quiere correr el
  // arranque de los pagos -por ejemplo, darle un mes de gracia-. null =
  // automático; las cuotas siguientes SIEMPRE respetan la modalidad/
  // frecuencia elegida a partir de esta fecha, se haya tocado o no.
  DateTime? fechaPrimerPago;

  ConfiguracionApartadoController({String nombreClienteInicial = '', this.idCliente})
      : clienteController = TextEditingController(text: nombreClienteInicial);

  void dispose() {
    clienteController.dispose();
    porcentajeController.dispose();
    montoInicialController.dispose();
    montoInicialRealController.dispose();
    numeroCuotasController.dispose();
  }

  static double _parseDouble(String texto) => double.tryParse(texto.replaceAll(',', '').trim()) ?? 0;
  static int _parseInt(String texto) => int.tryParse(texto.trim()) ?? 0;

  String get nombreCliente => clienteController.text.trim();
  int get numeroCuotas => _parseInt(numeroCuotasController.text);
  IntervaloApartado get intervalo => intervaloApartadoPorId(intervaloPresetId);

  double montoInicialSobre(double montoTotal) {
    if (inicialPorPorcentaje) {
      final porcentaje = _parseDouble(porcentajeController.text).clamp(0, 100);
      return redondearMoneda(montoTotal * porcentaje / 100);
    }
    return redondearMoneda(_parseDouble(montoInicialController.text));
  }

  /// Lo que el usuario tipeó como pago inicial REAL (puede ser 0 si el
  /// cliente no dio nada de entrada).
  double get montoInicialReal => redondearMoneda(_parseDouble(montoInicialRealController.text));

  /// Mantiene [montoInicialRealController] mostrando el sugerido -hasta que
  /// el usuario lo edite a mano, ver [marcarMontoInicialRealTocado]-: se
  /// llama en cada build del formulario (ConfiguracionApartadoForm.build),
  /// es barato. Así el campo arranca mostrando "lo que debería dar" pero
  /// queda libre para tipear "lo que dio de verdad".
  void sincronizarMontoInicialReal(double montoTotal) {
    if (_montoInicialRealTocado) return;
    final texto = montoInicialSobre(montoTotal).toStringAsFixed(2);
    if (montoInicialRealController.text != texto) montoInicialRealController.text = texto;
  }

  void marcarMontoInicialRealTocado() => _montoInicialRealTocado = true;

  double saldoRestanteSobre(double montoTotal) {
    final saldo = montoTotal - montoInicialSobre(montoTotal);
    return saldo < 0 ? 0 : saldo;
  }

  List<NuevaCuota> cuotasSobre(double montoTotal) {
    if (modalidad != 'cuotas_fijas') return const [];
    return calcularCuotasApartado(
      saldoRestante: saldoRestanteSobre(montoTotal),
      numeroCuotas: numeroCuotas,
      intervaloDias: intervalo.dias,
      intervaloMeses: intervalo.meses,
      // calcularCuotasApartado arma la Cuota 1 en `desde + 1 frecuencia`
      // (nunca en `desde` mismo): si el usuario eligió una fecha exacta para
      // la Cuota 1, hay que retroceder una frecuencia para que esa fórmula
      // -sin tocarla, sigue igual para todo el resto que no usa esto- dé
      // justo la fecha que se pidió.
      desde: fechaPrimerPago == null ? null : _restarIntervalo(fechaPrimerPago!, intervalo),
    );
  }

  static DateTime _restarIntervalo(DateTime fecha, IntervaloApartado intervalo) {
    if (intervalo.meses > 0) {
      final mesesTotales = fecha.year * 12 + (fecha.month - 1) - intervalo.meses;
      return DateTime(mesesTotales ~/ 12, mesesTotales % 12 + 1, fecha.day);
    }
    return fecha.subtract(Duration(days: intervalo.dias));
  }

  /// Devuelve el mensaje de error a mostrar, o null si está todo bien (las
  /// mismas validaciones para los dos lados; la existencia real de cada
  /// producto la valida el servidor en `crear_apartado`).
  String? validar(double montoTotal) {
    if (nombreCliente.isEmpty) return 'Elegí (o escribí) el cliente';
    final inicial = montoInicialSobre(montoTotal);
    if (inicial > montoTotal + 0.01) return 'El pago inicial sugerido no puede superar el monto total';
    if (inicial < 0) return 'El pago inicial sugerido no puede ser negativo';
    final inicialReal = montoInicialReal;
    if (inicialReal > montoTotal + 0.01) return 'El pago inicial real no puede superar el monto total';
    if (inicialReal < 0) return 'El pago inicial real no puede ser negativo';
    if (inicialReal > 0.009 && metodoPagoInicial.isEmpty) return 'Elegí el método de pago del pago inicial';
    if (modalidad == 'cuotas_fijas') {
      if (numeroCuotas <= 0) return 'Ingresá un número de cuotas válido';
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
    controller.sincronizarMontoInicialReal(montoTotal);

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
              filaResumenApartado('Pago inicial sugerido', formatearMoneda(montoInicial)),
              filaResumenApartado('Saldo a financiar (para las cuotas)', formatearMoneda(saldoRestante), destacado: true),
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 14),
              Text(
                '¿Cuánto dio de verdad el cliente ahora?',
                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 4),
              Text(
                'Puede ser distinto al sugerido de arriba -las cuotas ya quedaron armadas sobre el sugerido, esto solo registra lo que entró de verdad-.',
                style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 10),
              CampoTecladoCompacto(
                controller: controller.montoInicialRealController,
                numerico: true,
                child: TextField(
                  controller: controller.montoInicialRealController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: decoracionApartado('Pago inicial real'),
                  onChanged: (_) {
                    controller.marcarMontoInicialRealTocado();
                    alCambiar();
                  },
                ),
              ),
              if (controller.montoInicialReal > 0.009) ...[
                const SizedBox(height: 12),
                Text('Método de pago', style: GoogleFonts.poppins(fontSize: 12.5, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final metodo in metodosPagoApartado)
                      ChoiceChip(
                        label: Text(metodo, style: GoogleFonts.poppins(fontSize: 12.5)),
                        selected: controller.metodoPagoInicial == metodo,
                        onSelected: (v) {
                          controller.metodoPagoInicial = metodo;
                          alCambiar();
                        },
                      ),
                  ],
                ),
              ],
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
                      child: DropdownButtonFormField<String>(
                        initialValue: controller.intervaloPresetId,
                        isExpanded: true,
                        style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF1A1A1A)),
                        decoration: decoracionApartado('Frecuencia'),
                        items: [
                          for (final intervalo in intervalosApartado)
                            DropdownMenuItem(value: intervalo.id, child: Text(intervalo.etiqueta)),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          controller.intervaloPresetId = v;
                          alCambiar();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _filaFechaPrimerPago(context, controller, formatoFecha, alCambiar),
                const SizedBox(height: 6),
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

  // Muestra cuándo cae la Cuota 1 -automático (hoy + 1 frecuencia) salvo que
  // el usuario elija otra fecha a mano, ver ConfiguracionApartadoController.
  // fechaPrimerPago-, con un lápiz para cambiarla y una "x" para volver a
  // automático.
  Widget _filaFechaPrimerPago(
    BuildContext context,
    ConfiguracionApartadoController controller,
    DateFormat formatoFecha,
    VoidCallback alCambiar,
  ) {
    final elegida = controller.fechaPrimerPago;
    final automatica = elegida == null;
    final primeraCuota = controller.cuotasSobre(montoTotal).isNotEmpty
        ? controller.cuotasSobre(montoTotal).first.fechaProgramada
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final elegidaAntes = controller.fechaPrimerPago ?? primeraCuota ?? DateTime.now();
        final fecha = await showDatePicker(
          context: context,
          initialDate: elegidaAntes,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          helpText: 'Fecha de la primera cuota',
        );
        if (fecha != null) {
          controller.fechaPrimerPago = fecha;
          alCambiar();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.event_outlined, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                primeraCuota == null
                    ? 'Elegí número de cuotas y frecuencia primero'
                    : 'Primera cuota: ${formatoFecha.format(primeraCuota)}'
                        '${automatica ? ' (automático)' : ''}',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
            if (!automatica)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  controller.fechaPrimerPago = null;
                  alCambiar();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    'Volver a automático',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F1B3D),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              )
            else
              Icon(Icons.edit_outlined, size: 15, color: Colors.grey.shade500),
          ],
        ),
      ),
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
