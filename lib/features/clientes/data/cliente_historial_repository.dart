import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'cliente_model.dart';
import 'cliente_historial_model.dart';
import 'cliente_repository.dart';
import '../../ventas/data/venta_model.dart';
import '../../ventas/data/item_venta_model.dart';
import '../../ventas_credito/data/venta_credito_model.dart';
import '../../ventas_credito/data/venta_credito_repository.dart';

/// Cuántas ventas recientes se muestran en Detalle de Cliente (no todo el
/// historial: es una lista para escanear de un vistazo, no un reporte).
const _maxVentasRecientes = 10;
const _maxHistorialColores = 20;
const _maxProductosTop = 3;

/// Todas las consultas para "Detalle de Cliente" (ver DetalleClienteScreen),
/// agregadas en un solo objeto inmutable. Mismo patrón de "disparar todo en
/// paralelo, agregar en Dart" que ReporteFinancieroRepository.
///
/// No tiene tabla propia (ver comentario en supabase/schema.sql): es una
/// vista agregada que se arma con consultas SQL sobre las tablas reales
/// (ventas, venta_items, ventas_credito), igual que antes se armaba en
/// memoria sobre las colecciones de Firestore.
class ClienteHistorialRepository with ConRedMixin {
  final _db = Supabase.instance.client;
  final _ventaCreditoRepository = VentaCreditoRepository();
  final _clienteRepository = ClienteRepository();

  Future<ClienteHistorialData> obtener(ClienteModel cliente) {
    return conRed(() async {
      final nombre = cliente.nombreCompleto.trim();
      final dni = cliente.dni.trim();
      final idReferidor = cliente.idReferidor;

      // Todo lo que no depende de nada más se dispara junto.
      final ventasPorIdFuture = _db
          .from('ventas')
          .select()
          .eq('id_cliente', cliente.id);
      final ventasPorNombreFuture = nombre.isEmpty
          ? null
          : _db.from('ventas').select().eq('nombre_cliente', nombre);
      // Créditos: por idCliente (confiable, el mismo vínculo real que ventas) +
      // respaldo por DNI para créditos viejos que hayan quedado sin idCliente.
      // Antes esto SOLO buscaba por DNI -si el cliente no tenía DNI cargado
      // (frecuente, es un campo opcional), la pantalla de Detalle de Cliente
      // mostraba "no tiene historial de crédito" aunque sí tuviera, como pasó
      // con un cliente real al probarlo-.
      final creditosPorIdFuture = _db
          .from('ventas_credito')
          .select()
          .eq('id_cliente', cliente.id);
      final creditosPorDniFuture = dni.isEmpty || dni == 'N/A'
          ? null
          : _db.from('ventas_credito').select().eq('documento_cliente', dni);
      // Quién lo refirió: una sola lectura puntual, no un stream -acá solo
      // hace falta el nombre/teléfono en el momento de abrir la pantalla-. Un
      // referidor es ahora un ClienteModel más (con esReferidor == true, ver
      // fusión del módulo 'referidores' dentro de clientes), así que se
      // resuelve con ClienteRepository.obtenerPorId igual que cualquier otro
      // cliente.
      final referidorFuture = (idReferidor == null || idReferidor.isEmpty)
          ? null
          : _clienteRepository.obtenerPorId(idReferidor);

      final ventasPorIdFilas = await ventasPorIdFuture;
      final ventasPorNombreFilas = ventasPorNombreFuture == null
          ? null
          : await ventasPorNombreFuture;
      final creditosPorIdFilas = await creditosPorIdFuture;
      final creditosPorDniFilas = creditosPorDniFuture == null
          ? null
          : await creditosPorDniFuture;
      final referidor = referidorFuture == null ? null : await referidorFuture;

      // ---- Ventas: por idCliente (confiable) + respaldo por nombre (ventas
      // viejas, de antes del vínculo real) de-duplicadas por id.
      final ventasMap = <String, VentaModel>{};
      final emparejadaSoloPorNombre = <String, bool>{};
      for (final fila in ventasPorIdFilas) {
        final id = fila['id'] as String;
        ventasMap[id] = VentaModel.fromMap(id, fila, const []);
        emparejadaSoloPorNombre[id] = false;
      }
      var hayEmparejadasPorNombre = false;
      if (ventasPorNombreFilas != null) {
        for (final fila in ventasPorNombreFilas) {
          final id = fila['id'] as String;
          if (ventasMap.containsKey(id)) continue;
          ventasMap[id] = VentaModel.fromMap(id, fila, const []);
          emparejadaSoloPorNombre[id] = true;
          hayEmparejadasPorNombre = true;
        }
      }

      final ventasValidas =
          ventasMap.values
              .where(
                (v) => v.estado == 'Activa' && v.tipoDocumento != 'Cotizacion',
              )
              .toList()
            ..sort(
              (a, b) => (b.fechaRegistro ?? DateTime(2000)).compareTo(
                a.fechaRegistro ?? DateTime(2000),
              ),
            );

      final creditosMap = <String, VentaCreditoModel>{};
      for (final fila in creditosPorIdFilas) {
        final id = fila['id'] as String;
        creditosMap[id] = VentaCreditoModel.fromMap(id, fila);
      }
      if (creditosPorDniFilas != null) {
        for (final fila in creditosPorDniFilas) {
          final id = fila['id'] as String;
          creditosMap.putIfAbsent(
            id,
            () => VentaCreditoModel.fromMap(id, fila),
          );
        }
      }
      final creditos = creditosMap.values.toList()
        ..sort(
          (a, b) => (b.fechaRegistro ?? DateTime(2000)).compareTo(
            a.fechaRegistro ?? DateTime(2000),
          ),
        );

      // ---- Resumen de compras ----
      final totalComprado = ventasValidas.fold<double>(
        0,
        (s, v) => s + v.totalAPagar,
      );
      final cantidadCompras = ventasValidas.length;
      final ticketPromedio = cantidadCompras == 0
          ? 0.0
          : totalComprado / cantidadCompras;
      final fechas = ventasValidas
          .map((v) => v.fechaRegistro)
          .whereType<DateTime>()
          .toList();
      final primeraCompra = fechas.isEmpty
          ? null
          : fechas.reduce((a, b) => a.isBefore(b) ? a : b);
      final ultimaCompra = fechas.isEmpty
          ? null
          : fechas.reduce((a, b) => a.isAfter(b) ? a : b);

      final ventasRecientes = ventasValidas
          .take(_maxVentasRecientes)
          .map(
            (v) => VentaResumenCliente(
              id: v.id,
              numeroDocumento: v.numeroDocumento,
              fecha: v.fechaRegistro,
              monto: v.totalAPagar,
              metodoPago: v.metodoPago,
              condicion: v.condicion,
              emparejadaPorNombre: emparejadaSoloPorNombre[v.id] ?? false,
            ),
          )
          .toList();

      // ---- Método de pago preferido (mismo idioma que
      // ReporteFinancieroRepository._agruparPorUsuario: contar y quedarse con
      // el de mayor conteo) ----
      final conteoMetodoPago = <String, int>{};
      for (final v in ventasValidas) {
        final metodo = v.metodoPago.isEmpty ? 'N/A' : v.metodoPago;
        conteoMetodoPago[metodo] = (conteoMetodoPago[metodo] ?? 0) + 1;
      }
      String? metodoPagoPreferido;
      var maxConteoMetodo = 0;
      conteoMetodoPago.forEach((metodo, conteo) {
        if (conteo > maxConteoMetodo) {
          maxConteoMetodo = conteo;
          metodoPagoPreferido = metodo;
        }
      });

      // ---- Códigos de color + "qué compra más" (misma consulta, dos usos)
      // ----
      // Antes era un collectionGroup por idCliente sobre la subcolección
      // 'detalle' (cada línea tenía idCliente denormalizado). venta_items no
      // guarda idCliente por línea -no hace falta: se resuelve consultando
      // por id_venta IN (...) sobre las ventas de este cliente ya
      // encontradas arriba (por id o por nombre)-.
      final idsVenta = ventasMap.keys.toList();
      final detalleFilas = idsVenta.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _db
                .from('venta_items')
                .select()
                .inFilter('id_venta', idsVenta);

      final numeroDocumentoPorVenta = {
        for (final v in ventasMap.values) v.id: v.numeroDocumento,
      };
      final lineas = detalleFilas.map((d) {
        final item = ItemVentaModel.fromRow(d);
        final idVenta = d['id_venta'] as String?;
        // No hay un campo 'fecha' propio por línea en venta_items (antes se
        // guardaba una copia denormalizada por línea en Firestore): se usa
        // la fecha de la venta dueña de esa línea, que es lo mismo que se
        // terminaba mostrando.
        final fecha = idVenta != null
            ? ventasMap[idVenta]?.fechaRegistro
            : null;
        return (item: item, fecha: fecha, idVenta: idVenta);
      }).toList();

      final historialColores =
          lineas
              .where((l) => l.item.codigosColor.isNotEmpty)
              .map(
                (l) => ColorHistorialItem(
                  fecha: l.fecha,
                  nombreProducto: l.item.nombreProducto,
                  codigosColor: l.item.codigosColor,
                  numeroDocumento:
                      (l.idVenta != null
                          ? numeroDocumentoPorVenta[l.idVenta]
                          : null) ??
                      '',
                ),
              )
              .toList()
            ..sort(
              (a, b) => (b.fecha ?? DateTime(2000)).compareTo(
                a.fecha ?? DateTime(2000),
              ),
            );

      final cantidadPorProducto = <String, double>{};
      for (final l in lineas) {
        if (l.item.nombreProducto.isEmpty) continue;
        cantidadPorProducto[l.item.nombreProducto] =
            (cantidadPorProducto[l.item.nombreProducto] ?? 0) + l.item.cantidad;
      }
      final productosTop =
          cantidadPorProducto.entries
              .map(
                (e) => ProductoTopCliente(
                  nombreProducto: e.key,
                  cantidad: e.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.cantidad.compareTo(a.cantidad));

      // ---- Puntualidad histórica de crédito: de los abonos de los créditos
      // ya cargados (no dispara una consulta nueva pesada, solo un fetch chico
      // de abonos por cada crédito de este cliente, que normalmente son pocos).
      int? abonosATiempo;
      int? abonosAtrasados;
      if (creditos.isNotEmpty) {
        final abonosPorCredito = await Future.wait(
          creditos.map(
            (c) => _ventaCreditoRepository.obtenerAbonosUnaVez(c.id),
          ),
        );
        var aTiempo = 0;
        var atrasados = 0;
        for (var i = 0; i < creditos.length; i++) {
          final vencimiento = creditos[i].fechaVencimiento;
          if (vencimiento == null) continue;
          for (final abono in abonosPorCredito[i]) {
            if (abono.fecha == null) continue;
            if (abono.fecha!.isAfter(vencimiento)) {
              atrasados++;
            } else {
              aTiempo++;
            }
          }
        }
        if (aTiempo + atrasados > 0) {
          abonosATiempo = aTiempo;
          abonosAtrasados = atrasados;
        }
      }

      return ClienteHistorialData(
        // Historial COMPLETO de créditos (pagados y no pagados) -antes se
        // filtraba acá mismo con `.where((c) => !c.liquidada)`, lo que hacía
        // desaparecer de Detalle de Cliente cualquier crédito ya liquidado
        // (bug reportado por el dueño probando con un cliente real que tenía
        // crédito pagado y no le aparecía nada). Los flags derivados
        // (hayCreditoVencido, etc.) ahora se calculan sobre esta lista
        // completa dentro de ClienteHistorialData.
        creditos: creditos,
        abonosATiempo: abonosATiempo,
        abonosAtrasados: abonosAtrasados,
        totalComprado: totalComprado,
        cantidadCompras: cantidadCompras,
        ticketPromedio: ticketPromedio,
        primeraCompra: primeraCompra,
        ultimaCompra: ultimaCompra,
        ventasRecientes: ventasRecientes,
        metodoPagoPreferido: metodoPagoPreferido,
        productosTop: productosTop.take(_maxProductosTop).toList(),
        historialColores: historialColores.take(_maxHistorialColores).toList(),
        hayVentasEmparejadasPorNombre: hayEmparejadasPorNombre,
        referidor: referidor,
      );
    });
  }
}
