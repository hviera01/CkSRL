import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'reporte_repository.dart';
import 'reporte_financiero_model.dart';
import 'reporte_venta_model.dart';
import 'reporte_compra_model.dart';
import '../../ventas/data/item_venta_model.dart';
import '../../compras/data/item_compra_model.dart';
import '../../productos/data/producto_model.dart';
import '../../egresos/data/egreso_repository.dart';
import '../../egresos/data/egreso_model.dart';
import '../../compras_credito/data/compra_credito_repository.dart';
import '../../compras_credito/data/abono_compra_model.dart';
import '../../ventas_credito/data/venta_credito_repository.dart';
import '../../ventas_credito/data/abono_model.dart';
import '../../caja/data/cierre_caja_repository.dart';
import '../../compras_credito/data/compra_credito_model.dart';
import '../../clientes/data/cliente_model.dart';

/// Cuánto del efectivo estimado se sugiere reservar como colchón de
/// seguridad antes de recomendar pagos a proveedores.
const _colchonSeguridadPorcentaje = 0.20;

/// Porcentaje del efectivo cobrado en el periodo que, como referencia
/// alternativa, se sugiere destinar a pagos a proveedores.
const _porcentajeVentasParaProveedores = 0.35;

const _topN = 10;

/// Días sin comprar a partir de los cuales un cliente activo se considera
/// inactivo (CRM Fase 3). El script de Node que manda el reporte por
/// WhatsApp (tool/reporte_whatsapp/reporte.js) mirra este mismo número a
/// mano -mantenerlos sincronizados si este valor cambia-.
const _diasUmbralClienteInactivo = 90;

class ReporteFinancieroRepository with ConRedMixin {
  final _db = Supabase.instance.client;
  final _reporteRepository = ReporteRepository();
  final _egresoRepository = EgresoRepository();
  final _compraCreditoRepository = CompraCreditoRepository();
  final _ventaCreditoRepository = VentaCreditoRepository();
  final _cierreCajaRepository = CierreCajaRepository();

  // La serie mensual y el efectivo estimado no dependen del rango que el
  // usuario elija en el reporte (son "últimos 6 meses" y "desde el último
  // cierre de caja" respectivamente), así que antes se recalculaban desde
  // cero en cada búsqueda aunque el usuario solo hubiera cambiado el rango
  // principal. Se cachean un rato corto para no repetir esas consultas.
  static const _vigenciaCache = Duration(minutes: 5);
  List<PuntoMensual>? _serieMensualCache;
  DateTime? _serieMensualCacheEn;
  double? _efectivoEstimadoCache;
  DateTime? _efectivoEstimadoCacheEn;

  /// Detalle (venta_items) de todas las ventas ACTUALES (no históricas) cuyo
  /// id está en [idsVenta], agrupado por id de venta en una sola consulta
  /// `IN (...)` -antes era un collectionGroup sobre la subcolección
  /// 'detalle' filtrado por fecha; venta_items no tiene su propia columna de
  /// fecha (no hace falta: ya se sabe qué ventas del rango son, por
  /// [ReporteRepository.obtenerReporteVentas])-.
  Future<Map<String, List<ItemVentaModel>>> _detalleVentasPorIds(
    List<String> idsVenta,
  ) async {
    if (idsVenta.isEmpty) return {};
    final filas = await _db
        .from('venta_items')
        .select()
        .inFilter('id_venta', idsVenta);
    final resultado = <String, List<ItemVentaModel>>{};
    for (final fila in filas) {
      resultado
          .putIfAbsent(fila['id_venta'] as String, () => [])
          .add(ItemVentaModel.fromRow(fila));
    }
    return resultado;
  }

  /// Mismo criterio que [_detalleVentasPorIds], para compra_items.
  Future<Map<String, List<ItemCompraModel>>> _detalleComprasPorIds(
    List<String> idsCompra,
  ) async {
    if (idsCompra.isEmpty) return {};
    final filas = await _db
        .from('compra_items')
        .select()
        .inFilter('id_compra', idsCompra);
    final resultado = <String, List<ItemCompraModel>>{};
    for (final fila in filas) {
      resultado
          .putIfAbsent(fila['id_compra'] as String, () => [])
          .add(ItemCompraModel.fromRow(fila));
    }
    return resultado;
  }

  Future<double> _efectivoEstimado() async {
    final cacheEn = _efectivoEstimadoCacheEn;
    if (_efectivoEstimadoCache != null &&
        cacheEn != null &&
        DateTime.now().difference(cacheEn) < _vigenciaCache) {
      return _efectivoEstimadoCache!;
    }
    final estado = await _cierreCajaRepository.obtenerEstadoCaja();
    final hoy = DateTime.now();
    final finInclusive = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59);
    final totales = await _cierreCajaRepository.calcularTotales(
      estado.fechaDesde,
      finInclusive,
    );
    final resultado =
        estado.montoInicial +
        totales.ingresosEfectivo -
        totales.egresosEfectivo;
    _efectivoEstimadoCache = resultado;
    _efectivoEstimadoCacheEn = DateTime.now();
    return resultado;
  }

  /// Reconstruye el flujo de efectivo con datos que ya se pidieron para el
  /// resto del reporte, en vez de recalcular todo el libro financiero de
  /// nuevo (mismo criterio que `CierreCajaRepository.calcularTotales`).
  FlujoEfectivo _calcularFlujo({
    required List<ReporteVentaModel> ventasContado,
    required List<ReporteCompraModel> comprasContado,
    required List<AbonoModel> abonosVenta,
    required List<AbonoCompraModel> abonosCompra,
    required List<EgresoModel> egresos,
  }) {
    double ingresosEfectivo = 0, ingresosTarjeta = 0, ingresosTransferencia = 0;
    double egresosEfectivo = 0, egresosTransferencia = 0;

    void sumarIngreso(String metodoPago, double monto) {
      switch (metodoPago) {
        case 'Efectivo':
          ingresosEfectivo += monto;
          break;
        case 'Tarjeta':
          ingresosTarjeta += monto;
          break;
        case 'Transferencia':
          ingresosTransferencia += monto;
          break;
      }
    }

    void sumarEgreso(String metodoPago, double monto) {
      switch (metodoPago) {
        case 'Efectivo':
          egresosEfectivo += monto;
          break;
        case 'Transferencia':
          egresosTransferencia += monto;
          break;
      }
    }

    for (final v in ventasContado) {
      if (v.metodoPago == 'Mixto' && v.pagosMixtos.isNotEmpty) {
        for (final pago in v.pagosMixtos) {
          sumarIngreso(pago.metodoPago, pago.monto);
        }
      } else {
        sumarIngreso(v.metodoPago, v.totalAPagar);
      }
    }
    for (final c in comprasContado) {
      sumarEgreso(c.metodoPago, c.montoTotal);
    }
    for (final a in abonosVenta) {
      sumarIngreso(a.metodoPago, a.montoAbonado);
    }
    for (final a in abonosCompra) {
      sumarEgreso(a.metodoPago, a.montoAbonado);
    }
    for (final e in egresos) {
      sumarEgreso(e.metodoPago, e.monto);
    }

    return FlujoEfectivo(
      ingresosEfectivo: ingresosEfectivo,
      ingresosTarjeta: ingresosTarjeta,
      ingresosTransferencia: ingresosTransferencia,
      egresosEfectivo: egresosEfectivo,
      egresosTransferencia: egresosTransferencia,
    );
  }

  Future<ReporteFinancieroData> obtenerReporte(
    DateTime inicio,
    DateTime finInclusive,
  ) {
    return conRed(() async {
      // Todo lo que no depende de nada más se dispara en paralelo de una vez;
      // recién se espera por cada resultado donde hace falta.
      final ventasHeadersFuture = _reporteRepository.obtenerReporteVentas(
        inicio,
        finInclusive,
      );
      final comprasHeadersFuture = _reporteRepository.obtenerReporteCompras(
        inicio,
        finInclusive,
      );
      final egresosPeriodoFuture = _egresoRepository.obtenerEgresosPorRango(
        inicio,
        finInclusive,
      );
      final abonosVentaFuture = _ventaCreditoRepository.obtenerAbonosPorRango(
        inicio,
        finInclusive,
      );
      final abonosCompraFuture = _compraCreditoRepository.obtenerAbonosPorRango(
        inicio,
        finInclusive,
      );
      final productosFuture = _db.from('productos').select();
      // Solo interesan para sumar saldoPendiente (cuentas por cobrar/pagar), así
      // que se filtran del lado del servidor los créditos ya saldados en vez de
      // traer la tabla completa (con historial largo, la mayoría termina
      // pagada) y descartarlos recién en el cliente.
      final ventasCreditoFuture = _db
          .from('ventas_credito')
          .select()
          .gt('saldo_pendiente', 0);
      final comprasCreditoFuture = _db
          .from('compras_credito')
          .select()
          .gt('saldo_pendiente', 0);
      final serieMensualFuture = _obtenerSerieMensual();
      final efectivoEstimadoFuture = _efectivoEstimado();
      final hace3Meses = DateTime(
        DateTime.now().year,
        DateTime.now().month - 2,
        1,
      );
      final egresosUltimos3MesesFuture = _egresoRepository
          .obtenerEgresosPorRango(hace3Meses, DateTime.now());
      // Solo clientes activos: un cliente inactivo (estado=false, ya dado de
      // baja) no tiene sentido incluirlo en "clientes inactivos" -eso es para
      // clientes vigentes que se dejaron de aparecer, no para los ya dados de
      // baja a propósito-. Filtro simple de un solo campo, sin índice extra.
      final clientesActivosFuture = _db
          .from('clientes')
          .select()
          .eq('estado', true);

      final ventasHeaders = await ventasHeadersFuture;
      final comprasHeaders = await comprasHeadersFuture;
      final egresosPeriodo = await egresosPeriodoFuture;
      final abonosVenta = await abonosVentaFuture;
      final abonosCompra = await abonosCompraFuture;
      final productosFilas = await productosFuture;
      final ventasCreditoFilas = await ventasCreditoFuture;
      final comprasCreditoFilas = await comprasCreditoFuture;
      final serieMensual = await serieMensualFuture;
      final efectivoEstimado = await efectivoEstimadoFuture;
      final egresosUltimos3Meses = await egresosUltimos3MesesFuture;
      final clientesActivosFilas = await clientesActivosFuture;

      final ventasValidas = ventasHeaders
          .where((v) => v.esActiva && !v.esCotizacion)
          .toList();
      final comprasValidas = comprasHeaders.where((c) => c.esActiva).toList();

      final detalleVentaPorId = await _detalleVentasPorIds(
        ventasValidas.map((v) => v.id).toList(),
      );
      final detalleCompraPorId = await _detalleComprasPorIds(
        comprasValidas.map((c) => c.id).toList(),
      );

      final detalleVentasPorVenta = [
        for (final v in ventasValidas)
          detalleVentaPorId[v.id] ?? const <ItemVentaModel>[],
      ];
      final detalleComprasPorCompra = [
        for (final c in comprasValidas)
          detalleCompraPorId[c.id] ?? const <ItemCompraModel>[],
      ];
      final itemsVenta = detalleVentasPorVenta
          .expand((items) => items)
          .toList();
      final itemsCompra = detalleComprasPorCompra
          .expand((items) => items)
          .toList();

      final gananciaPorVenta =
          <GananciaPorVenta>[
            for (var i = 0; i < ventasValidas.length; i++)
              GananciaPorVenta(
                idVenta: ventasValidas[i].id,
                numeroDocumento: ventasValidas[i].numeroDocumento,
                fecha: ventasValidas[i].fechaRegistro,
                cliente: ventasValidas[i].nombreCliente.isEmpty
                    ? 'CONSUMIDOR FINAL'
                    : ventasValidas[i].nombreCliente,
                ventas: ventasValidas[i].totalAPagar,
                costo: detalleVentasPorVenta[i].fold<double>(
                  0,
                  (s, item) => s + item.precioCompraUsado * item.cantidad,
                ),
              ),
          ]..sort(
            (a, b) => (b.fecha ?? DateTime(2000)).compareTo(
              a.fecha ?? DateTime(2000),
            ),
          );

      final ventasPeriodo = ventasValidas.fold<double>(
        0,
        (s, v) => s + v.totalAPagar,
      );
      final comprasPeriodo = comprasValidas.fold<double>(
        0,
        (s, c) => s + c.montoTotal,
      );
      final costoVentas = itemsVenta.fold<double>(
        0,
        (s, i) => s + i.precioCompraUsado * i.cantidad,
      );
      final utilidadBruta = ventasPeriodo - costoVentas;

      final gastosPeriodo = egresosPeriodo.fold<double>(
        0,
        (s, e) => s + e.monto,
      );
      final utilidadNeta = utilidadBruta - gastosPeriodo;

      final flujoEfectivo = _calcularFlujo(
        ventasContado: ventasValidas
            .where((v) => v.condicion == 'Contado')
            .toList(),
        comprasContado: comprasValidas
            .where((c) => c.condicion != 'Credito')
            .toList(),
        abonosVenta: abonosVenta,
        abonosCompra: abonosCompra,
        egresos: egresosPeriodo,
      );

      final topVendidosPorCantidad = _rankearPorCantidad(
        itemsVenta.map((i) => (i.idProducto, i.nombreProducto, i.cantidad)),
      );
      final topCompradosPorCantidad = _rankearPorCantidad(
        itemsCompra.map((i) => (i.idProducto, i.nombreProducto, i.cantidad)),
      );
      final topGananciaPorProducto = _rankearGanancia(itemsVenta);

      final productos = productosFilas
          .map((d) => ProductoModel.fromMap(d['id'] as String, d))
          .toList();
      final idsConVenta = itemsVenta.map((i) => i.idProducto).toSet();
      final productosSinVenta =
          productos
              .where((p) => p.estado && !idsConVenta.contains(p.id))
              .map(
                (p) => ProductoSinVenta(
                  idProducto: p.id,
                  nombreProducto: p.nombre,
                  stock: p.stock,
                  valorInventario: p.stock * p.precioCompra,
                ),
              )
              .toList()
            ..sort((a, b) => b.valorInventario.compareTo(a.valorInventario));
      final inventarioACosto = productos
          .where((p) => p.estado)
          .fold<double>(0, (s, p) => s + p.stock * p.precioCompra);

      final ventasPorUsuario = _agruparPorUsuario(ventasValidas);

      final totalAbonosComprasCredito = abonosCompra.fold<double>(
        0,
        (s, a) => s + a.montoAbonado,
      );
      final abonosPorProveedor = _agruparAbonosPorProveedor(abonosCompra);

      final reservaGastosFijos =
          egresosUltimos3Meses.fold<double>(0, (s, e) => s + e.monto) / 3;
      final colchon = efectivoEstimado * _colchonSeguridadPorcentaje;
      final sugeridoPorCaja = (efectivoEstimado - reservaGastosFijos - colchon)
          .clamp(0, double.infinity)
          .toDouble();
      final sugeridoPorVentas =
          flujoEfectivo.ingresosEfectivo * _porcentajeVentasParaProveedores;

      final recomendacionPago = RecomendacionPago(
        efectivoEstimado: efectivoEstimado,
        reservaGastosFijos: reservaGastosFijos,
        sugeridoPorCaja: sugeridoPorCaja,
        ingresoEfectivoCobrado: flujoEfectivo.ingresosEfectivo,
        sugeridoPorVentas: sugeridoPorVentas,
      );

      final cuentasPorCobrar = ventasCreditoFilas.fold<double>(
        0,
        (s, d) =>
            s +
            ((d['saldo_pendiente'] ?? 0) as num).toDouble().clamp(
              0,
              double.infinity,
            ),
      );
      final cuentasPorPagar = comprasCreditoFilas.fold<double>(
        0,
        (s, d) =>
            s +
            ((d['saldo_pendiente'] ?? 0) as num).toDouble().clamp(
              0,
              double.infinity,
            ),
      );

      final balanceGeneral = BalanceGeneral(
        inventarioACosto: inventarioACosto,
        cuentasPorCobrar: cuentasPorCobrar,
        efectivoEstimado: efectivoEstimado,
        cuentasPorPagar: cuentasPorPagar,
      );

      final diasPeriodo = (finInclusive.difference(inicio).inHours / 24)
          .ceil()
          .clamp(1, 100000);
      final inteligenciaNegocio = InteligenciaNegocioData(
        pronosticoVentas: _calcularPronostico(serieMensual),
        sugerenciasCompra: _calcularSugerenciasCompra(
          productos: productos,
          itemsVenta: itemsVenta,
          comprasValidas: comprasValidas,
          detalleComprasPorCompra: detalleComprasPorCompra,
          comprasCreditoFilas: comprasCreditoFilas,
          diasPeriodo: diasPeriodo,
        ),
        rotacionInventario: inventarioACosto <= 0
            ? 0
            : costoVentas / inventarioACosto,
        clientesTop: _agruparClientesTop(ventasValidas),
        ticketPromedio: ventasValidas.isEmpty
            ? 0
            : ventasPeriodo / ventasValidas.length,
        valorStockMuerto: productosSinVenta.fold<double>(
          0,
          (s, p) => s + p.valorInventario,
        ),
        ventasNoRegistradas: _agruparVentasSinCliente(ventasValidas),
        clientesInactivos: _calcularClientesInactivos(
          clientesActivosFilas
              .map((d) => ClienteModel.fromMap(d['id'] as String, d))
              .toList(),
        ),
      );

      return ReporteFinancieroData(
        inicio: inicio,
        fin: finInclusive,
        ventasPeriodo: ventasPeriodo,
        comprasPeriodo: comprasPeriodo,
        costoVentas: costoVentas,
        utilidadBruta: utilidadBruta,
        gastosPeriodo: gastosPeriodo,
        utilidadNeta: utilidadNeta,
        flujoEfectivo: flujoEfectivo,
        serieMensual: serieMensual,
        gananciaPorVenta: gananciaPorVenta,
        topVendidosPorCantidad: topVendidosPorCantidad,
        topCompradosPorCantidad: topCompradosPorCantidad,
        topGananciaPorProducto: topGananciaPorProducto,
        productosSinVenta: productosSinVenta,
        ventasPorUsuario: ventasPorUsuario,
        totalAbonosComprasCredito: totalAbonosComprasCredito,
        abonosPorProveedor: abonosPorProveedor,
        recomendacionPago: recomendacionPago,
        balanceGeneral: balanceGeneral,
        inteligenciaNegocio: inteligenciaNegocio,
      );
    });
  }

  /// Regresión lineal simple (mínimos cuadrados) sobre la serie mensual ya
  /// calculada para "Comparación Mensual", proyectando un mes más. Con
  /// menos de 3 puntos la pendiente no es confiable, así que se usa
  /// directamente el promedio como estimado.
  PronosticoVentas _calcularPronostico(List<PuntoMensual> serie) {
    final montos = serie.map((p) => p.totalVentas).toList();
    final promedio = montos.isEmpty
        ? 0.0
        : montos.reduce((a, b) => a + b) / montos.length;
    if (montos.length < 3) {
      return PronosticoVentas(
        montoEstimado: promedio,
        promedioUltimosMeses: promedio,
        tendenciaMensual: 0,
        metodo: 'Promedio simple',
      );
    }
    final n = montos.length;
    final xs = List<int>.generate(n, (i) => i);
    final mediaX = xs.reduce((a, b) => a + b) / n;
    final mediaY = promedio;
    var numerador = 0.0;
    var denominador = 0.0;
    for (var i = 0; i < n; i++) {
      numerador += (xs[i] - mediaX) * (montos[i] - mediaY);
      denominador += (xs[i] - mediaX) * (xs[i] - mediaX);
    }
    final pendiente = denominador == 0 ? 0.0 : numerador / denominador;
    final interseccion = mediaY - pendiente * mediaX;
    final estimado = (pendiente * n + interseccion)
        .clamp(0, double.infinity)
        .toDouble();
    return PronosticoVentas(
      montoEstimado: estimado,
      promedioUltimosMeses: promedio,
      tendenciaMensual: pendiente,
      metodo: 'Regresión lineal (últimos $n meses)',
    );
  }

  /// Cuánta deuda vencida (y total) tiene cada proveedor ahora mismo, para
  /// no sugerir comprarle más a uno que ya está muy atrasado. Reusa las
  /// mismas filas de `compras_credito` con saldo pendiente que ya se
  /// pidieron para el Balance General — no dispara consultas nuevas.
  Map<String, ({double vencida, double total})> _estadoCuentaPorProveedor(
    List<Map<String, dynamic>> filas,
  ) {
    final resultado = <String, ({double vencida, double total})>{};
    for (final fila in filas) {
      final credito = CompraCreditoModel.fromMap(fila['id'] as String, fila);
      if (credito.idProveedor.isEmpty) continue;
      final actual =
          resultado[credito.idProveedor] ?? (vencida: 0.0, total: 0.0);
      resultado[credito.idProveedor] = (
        vencida:
            actual.vencida + (credito.vencida ? credito.saldoPendiente : 0),
        total: actual.total + credito.saldoPendiente,
      );
    }
    return resultado;
  }

  /// Productos activos cuyo stock, a la velocidad de venta que tuvieron en
  /// el rango del reporte, se agotaría pronto (menos de [_diasUmbralReposicion]
  /// días). Se pondera con el estado de cuenta del proveedor más reciente
  /// conocido para cada producto (la compra más nueva del rango que lo
  /// incluya). Todo con datos ya pedidos para el resto del reporte.
  static const _diasUmbralReposicion = 14;

  List<SugerenciaCompra> _calcularSugerenciasCompra({
    required List<ProductoModel> productos,
    required List<ItemVentaModel> itemsVenta,
    required List<ReporteCompraModel> comprasValidas,
    required List<List<ItemCompraModel>> detalleComprasPorCompra,
    required List<Map<String, dynamic>> comprasCreditoFilas,
    required int diasPeriodo,
  }) {
    // Proveedor más reciente conocido por producto: comprasValidas ya viene
    // ordenado de más nueva a más vieja (ver ReporteRepository.obtenerReporteCompras),
    // así que la primera compra que mencione un producto es la más reciente.
    final proveedorPorProducto =
        <String, (String idProveedor, String nombre)>{};
    for (
      var i = 0;
      i < comprasValidas.length && i < detalleComprasPorCompra.length;
      i++
    ) {
      final compra = comprasValidas[i];
      if (compra.idProveedor.isEmpty) continue;
      for (final item in detalleComprasPorCompra[i]) {
        proveedorPorProducto.putIfAbsent(
          item.idProducto,
          () => (compra.idProveedor, compra.razonSocial),
        );
      }
    }

    final estadoProveedores = _estadoCuentaPorProveedor(comprasCreditoFilas);

    final cantidadVendidaPorProducto = <String, double>{};
    for (final item in itemsVenta) {
      cantidadVendidaPorProducto[item.idProducto] =
          (cantidadVendidaPorProducto[item.idProducto] ?? 0) + item.cantidad;
    }

    final sugerencias = <SugerenciaCompra>[];
    for (final producto in productos) {
      if (!producto.estado) continue;
      final vendida = cantidadVendidaPorProducto[producto.id];
      if (vendida == null || vendida <= 0) continue;
      final ventaDiaria = vendida / diasPeriodo;
      if (ventaDiaria <= 0) continue;
      final diasParaAgotarse = producto.stock / ventaDiaria;
      if (diasParaAgotarse >= _diasUmbralReposicion) continue;

      final proveedorInfo = proveedorPorProducto[producto.id];
      final estado = proveedorInfo == null
          ? null
          : estadoProveedores[proveedorInfo.$1];

      sugerencias.add(
        SugerenciaCompra(
          idProducto: producto.id,
          nombreProducto: producto.nombre,
          stockActual: producto.stock,
          ventaDiariaPromedio: ventaDiaria,
          diasParaAgotarse: diasParaAgotarse,
          proveedor: proveedorInfo?.$2,
          deudaVencidaProveedor: estado?.vencida ?? 0,
          proveedorAlDia: (estado?.vencida ?? 0) <= 0,
        ),
      );
    }
    sugerencias.sort(
      (a, b) => a.diasParaAgotarse.compareTo(b.diasParaAgotarse),
    );
    return sugerencias.take(_topN).toList();
  }

  /// Agrupa por [ReporteVentaModel.idCliente] (vínculo real, CRM Fase 1)
  /// cuando la venta lo trae; si no -ventas de antes de ese vínculo, o hechas
  /// sin cliente elegido-, cae al agrupamiento anterior por el texto de
  /// nombreCliente (normalizado a mayúsculas/sin espacios de sobra, para no
  /// separar "Juan Perez" de "juan perez " en dos filas distintas). El
  /// nombre que se muestra es el de la primera venta de cada grupo -no hace
  /// falta releer el registro de Clientes solo para esto-.
  List<ClienteTop> _agruparClientesTop(List<ReporteVentaModel> ventas) {
    final totalPorClave = <String, double>{};
    final conteoPorClave = <String, int>{};
    final nombrePorClave = <String, String>{};
    for (final v in ventas) {
      final nombre = v.nombreCliente.isEmpty
          ? 'CONSUMIDOR FINAL'
          : v.nombreCliente;
      if (nombre.toUpperCase() == 'CONSUMIDOR FINAL') continue;
      final idCliente = v.idCliente;
      final clave = (idCliente != null && idCliente.isNotEmpty)
          ? 'id:$idCliente'
          : 'nombre:${nombre.trim().toUpperCase()}';
      totalPorClave[clave] = (totalPorClave[clave] ?? 0) + v.totalAPagar;
      conteoPorClave[clave] = (conteoPorClave[clave] ?? 0) + 1;
      nombrePorClave.putIfAbsent(clave, () => nombre);
    }
    final lista =
        totalPorClave.keys
            .map(
              (clave) => ClienteTop(
                cliente: nombrePorClave[clave] ?? '',
                totalComprado: totalPorClave[clave] ?? 0,
                cantidadCompras: conteoPorClave[clave] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.totalComprado.compareTo(a.totalComprado));
    return lista.take(_topN).toList();
  }

  /// Ventas con un nombre tipeado que no quedó vinculado a un cliente real
  /// (sin idCliente) — agrupadas por nombre normalizado, ordenadas por
  /// frecuencia (no por monto): el objetivo es detectar compradores
  /// frecuentes sin registrar, no a quién más le vendieron una sola vez.
  List<VentaSinCliente> _agruparVentasSinCliente(
    List<ReporteVentaModel> ventas,
  ) {
    final totalPorClave = <String, double>{};
    final conteoPorClave = <String, int>{};
    final nombrePorClave = <String, String>{};
    for (final v in ventas) {
      final idCliente = v.idCliente;
      if (idCliente != null && idCliente.isNotEmpty) continue;
      final nombre = v.nombreCliente.trim();
      if (nombre.isEmpty || nombre.toUpperCase() == 'CONSUMIDOR FINAL')
        continue;
      final clave = nombre.toUpperCase();
      totalPorClave[clave] = (totalPorClave[clave] ?? 0) + v.totalAPagar;
      conteoPorClave[clave] = (conteoPorClave[clave] ?? 0) + 1;
      nombrePorClave.putIfAbsent(clave, () => nombre);
    }
    final lista =
        totalPorClave.keys
            .map(
              (clave) => VentaSinCliente(
                nombre: nombrePorClave[clave] ?? clave,
                cantidadVentas: conteoPorClave[clave] ?? 0,
                totalComprado: totalPorClave[clave] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.cantidadVentas.compareTo(a.cantidadVentas));
    return lista.take(_topN).toList();
  }

  /// Clientes activos (ya filtrados por estado=true en la consulta) con más
  /// de [_diasUmbralClienteInactivo] días desde su última compra -o que
  /// nunca han comprado (fechaUltimaCompra null), que también cuentan como
  /// inactivos-. Todo en memoria, sin consulta ni índice adicional (la fecha
  /// de última compra ya viene denormalizada en cada ClienteModel desde CRM
  /// Fase 1 — ver VentaRepository.registrarVenta).
  List<ClienteInactivo> _calcularClientesInactivos(
    List<ClienteModel> clientesActivos,
  ) {
    final ahora = DateTime.now();
    final inactivos = <ClienteInactivo>[];
    for (final c in clientesActivos) {
      final ultimaCompra = c.fechaUltimaCompra;
      if (ultimaCompra == null) {
        inactivos.add(
          ClienteInactivo(
            nombreCompleto: c.nombreCompleto,
            ultimaCompra: null,
            diasSinComprar: null,
          ),
        );
        continue;
      }
      final dias = ahora.difference(ultimaCompra).inDays;
      if (dias > _diasUmbralClienteInactivo) {
        inactivos.add(
          ClienteInactivo(
            nombreCompleto: c.nombreCompleto,
            ultimaCompra: ultimaCompra,
            diasSinComprar: dias,
          ),
        );
      }
    }
    // Los que nunca han comprado van al final: no hay "hace cuántos días" que
    // ordenar ahí, y los más urgentes de recuperar son los que sí compraron
    // pero hace más tiempo.
    inactivos.sort((a, b) {
      if (a.diasSinComprar == null && b.diasSinComprar == null) return 0;
      if (a.diasSinComprar == null) return 1;
      if (b.diasSinComprar == null) return -1;
      return b.diasSinComprar!.compareTo(a.diasSinComprar!);
    });
    return inactivos;
  }

  List<RankingProducto> _rankearPorCantidad(
    Iterable<(String, String, double)> lineas,
  ) {
    final porProducto = <String, RankingProducto>{};
    for (final (idProducto, nombre, cantidad) in lineas) {
      final actual = porProducto[idProducto];
      porProducto[idProducto] = RankingProducto(
        idProducto: idProducto,
        nombreProducto: nombre,
        cantidad: (actual?.cantidad ?? 0) + cantidad,
        monto: 0,
      );
    }
    final lista = porProducto.values.toList()
      ..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    return lista.take(_topN).toList();
  }

  List<RankingProducto> _rankearGanancia(List<ItemVentaModel> items) {
    final ingresoPorProducto = <String, double>{};
    final costoPorProducto = <String, double>{};
    final cantidadPorProducto = <String, double>{};
    final nombrePorProducto = <String, String>{};
    for (final item in items) {
      ingresoPorProducto[item.idProducto] =
          (ingresoPorProducto[item.idProducto] ?? 0) + item.subtotal;
      costoPorProducto[item.idProducto] =
          (costoPorProducto[item.idProducto] ?? 0) +
          item.precioCompraUsado * item.cantidad;
      cantidadPorProducto[item.idProducto] =
          (cantidadPorProducto[item.idProducto] ?? 0) + item.cantidad;
      nombrePorProducto[item.idProducto] = item.nombreProducto;
    }
    final lista =
        ingresoPorProducto.keys
            .map(
              (id) => RankingProducto(
                idProducto: id,
                nombreProducto: nombrePorProducto[id] ?? '',
                cantidad: cantidadPorProducto[id] ?? 0,
                monto:
                    (ingresoPorProducto[id] ?? 0) - (costoPorProducto[id] ?? 0),
              ),
            )
            .toList()
          ..sort((a, b) => b.monto.compareTo(a.monto));
    return lista.take(_topN).toList();
  }

  List<VentasPorUsuario> _agruparPorUsuario(List<ReporteVentaModel> ventas) {
    final totalPorUsuario = <String, double>{};
    final conteoPorUsuario = <String, int>{};
    for (final v in ventas) {
      final usuario = v.usuarioRegistro.isEmpty
          ? 'Sin usuario'
          : v.usuarioRegistro;
      totalPorUsuario[usuario] =
          (totalPorUsuario[usuario] ?? 0) + v.totalAPagar;
      conteoPorUsuario[usuario] = (conteoPorUsuario[usuario] ?? 0) + 1;
    }
    final lista =
        totalPorUsuario.keys
            .map(
              (u) => VentasPorUsuario(
                usuario: u,
                totalVentas: totalPorUsuario[u] ?? 0,
                cantidadTransacciones: conteoPorUsuario[u] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.totalVentas.compareTo(a.totalVentas));
    return lista;
  }

  List<AbonoPorProveedor> _agruparAbonosPorProveedor(
    List<AbonoCompraModel> abonos,
  ) {
    final totalPorProveedor = <String, double>{};
    for (final a in abonos) {
      final proveedor = a.nombreProveedor.isEmpty ? 'N/A' : a.nombreProveedor;
      totalPorProveedor[proveedor] =
          (totalPorProveedor[proveedor] ?? 0) + a.montoAbonado;
    }
    final lista =
        totalPorProveedor.entries
            .map((e) => AbonoPorProveedor(proveedor: e.key, total: e.value))
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return lista;
  }

  Future<List<PuntoMensual>> _obtenerSerieMensual() async {
    final cacheEn = _serieMensualCacheEn;
    if (_serieMensualCache != null &&
        cacheEn != null &&
        DateTime.now().difference(cacheEn) < _vigenciaCache) {
      return _serieMensualCache!;
    }
    final resultado = await _calcularSerieMensual();
    _serieMensualCache = resultado;
    _serieMensualCacheEn = DateTime.now();
    return resultado;
  }

  Future<List<PuntoMensual>> _calcularSerieMensual() async {
    final hoy = DateTime.now();
    final primerMesDeLaSerie = DateTime(hoy.year, hoy.month - 5, 1);
    final finRango = DateTime(
      hoy.year,
      hoy.month + 1,
      1,
    ).subtract(const Duration(seconds: 1));

    final ventas = await _reporteRepository.obtenerReporteVentas(
      primerMesDeLaSerie,
      finRango,
    );
    final compras = await _reporteRepository.obtenerReporteCompras(
      primerMesDeLaSerie,
      finRango,
    );
    final ventasValidas = ventas.where((v) => v.esActiva && !v.esCotizacion);
    final comprasValidas = compras.where((c) => c.esActiva);

    final ventasPorMes = <String, double>{};
    for (final v in ventasValidas) {
      final fecha = v.fechaRegistro;
      if (fecha == null) continue;
      final clave = '${fecha.year}-${fecha.month}';
      ventasPorMes[clave] = (ventasPorMes[clave] ?? 0) + v.totalAPagar;
    }
    final comprasPorMes = <String, double>{};
    for (final c in comprasValidas) {
      final fecha = c.fechaRegistro;
      if (fecha == null) continue;
      final clave = '${fecha.year}-${fecha.month}';
      comprasPorMes[clave] = (comprasPorMes[clave] ?? 0) + c.montoTotal;
    }

    final serie = <PuntoMensual>[];
    for (var i = 0; i < 6; i++) {
      final mes = DateTime(
        primerMesDeLaSerie.year,
        primerMesDeLaSerie.month + i,
        1,
      );
      final clave = '${mes.year}-${mes.month}';
      serie.add(
        PuntoMensual(
          mes: mes,
          totalVentas: ventasPorMes[clave] ?? 0,
          totalCompras: comprasPorMes[clave] ?? 0,
        ),
      );
    }
    return serie;
  }
}
