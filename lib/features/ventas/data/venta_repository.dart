import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/utils/texto_utils.dart';
import 'venta_model.dart';
import 'venta_en_espera_model.dart';
import 'item_venta_model.dart';
import 'pago_detalle_model.dart';

class VentaRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  String _formatearCorrelativo(String tipoDocumento, int numero) {
    if (tipoDocumento == 'VentaSinFacturar') {
      return numero.toString().padLeft(4, '0');
    }
    return numero.toString().padLeft(8, '0');
  }

  /// Próximo número que le tocaría a la próxima Factura/Boleta. Para uso en
  /// Negocio, donde se puede consultar y fijar manualmente.
  Future<int> obtenerProximoNumeroFactura() {
    return conRed(() async {
      final filas = await _db.from('contadores').select('ultimo').eq('clave', 'venta').limit(1);
      final actual = filas.isEmpty ? 0 : ((filas.first['ultimo'] ?? 0) as num).toInt();
      return actual + 1;
    });
  }

  Future<void> establecerProximoNumeroFactura(int proximoNumero) {
    final nuevoUltimo = proximoNumero - 1;
    return conRed(() => _db.from('contadores').upsert({'clave': 'venta', 'ultimo': nuevoUltimo < 0 ? 0 : nuevoUltimo}));
  }

  /// Reserva (consume) el próximo número de Factura/Boleta de la secuencia
  /// oficial sin crear una venta real — ver incrementar_contador en
  /// supabase/schema.sql (atómico: dos cajeros no pueden sacar el mismo número).
  Future<String> reservarProximoNumeroFactura() {
    return conRed(() async {
      final nuevo = await _db.rpc('incrementar_contador', params: {'p_clave': 'venta'}) as int;
      return _formatearCorrelativo('Factura', nuevo);
    });
  }

  Future<VentaModel> registrarVenta({
    required String tipoDocumento,
    required String condicion,
    required String metodoPago,
    required String documentoCliente,
    required String nombreCliente,
    String? idCliente,
    required DateTime fechaRegistro,
    required DateTime? fechaVencimiento,
    String? telefonoCredito,
    required String oc,
    required String regExonerado,
    required String regSag,
    String observaciones = '',
    double descuentoGlobal = 0,
    required List<ItemVentaModel> items,
    required double montoPago,
    required double montoCambio,
    List<PagoDetalle> pagosMixtos = const [],
    required double subtotal,
    required double impuesto,
    required double totalAPagar,
    required String usuario,
    Set<String> categoriasSinControlStock = const {},
    bool esEnvio = false,
    String envioNombre = '',
    String envioDireccion = '',
    String envioTelefono = '',
  }) {
    return conRed(() async {
      final resultado = await _db.rpc('registrar_venta', params: {
        'payload': {
          'tipoDocumento': tipoDocumento,
          'condicion': condicion,
          'metodoPago': metodoPago,
          'documentoCliente': documentoCliente,
          'nombreCliente': nombreCliente,
          'idCliente': idCliente,
          'nombreClienteNormalizado': normalizarNombreCliente(nombreCliente),
          'fechaRegistro': fechaRegistro.toIso8601String(),
          'fechaVencimiento': fechaVencimiento?.toIso8601String(),
          'telefonoCredito': telefonoCredito,
          'oc': oc,
          'regExonerado': regExonerado,
          'regSag': regSag,
          'observaciones': observaciones,
          'descuentoGlobal': descuentoGlobal,
          'montoPago': montoPago,
          'montoCambio': montoCambio,
          'pagosMixtos': PagoDetalle.listaToMaps(pagosMixtos),
          'subtotal': subtotal,
          'impuesto': impuesto,
          'totalAPagar': totalAPagar,
          'usuario': usuario,
          'esEnvio': esEnvio,
          'envioNombre': envioNombre,
          'envioDireccion': envioDireccion,
          'envioTelefono': envioTelefono,
          'items': items.map((i) => i.toMap()).toList(),
        },
      }) as Map<String, dynamic>;

      final id = resultado['id'] as String;
      final numeroDocumento = resultado['numeroDocumento'] as String;
      final detalleCostos = (resultado['detalleCostos'] as List<dynamic>).map((c) => (c as num).toDouble()).toList();
      final idClienteResuelto = resultado['idCliente'] as String?;

      return VentaModel(
        id: id,
        tipoDocumento: tipoDocumento,
        numeroDocumento: numeroDocumento,
        documentoCliente: documentoCliente,
        nombreCliente: nombreCliente,
        idCliente: idClienteResuelto,
        metodoPago: metodoPago,
        montoPago: montoPago,
        montoCambio: montoCambio,
        pagosMixtos: pagosMixtos,
        subtotal: subtotal,
        impuesto: impuesto,
        totalAPagar: totalAPagar,
        condicion: condicion,
        fechaVencimiento: fechaVencimiento,
        fechaRegistro: fechaRegistro,
        estado: 'Activa',
        usuarioRegistro: usuario,
        cantidadProductos: items.fold<double>(0, (s, i) => s + i.cantidad),
        oc: oc,
        regExonerado: regExonerado,
        regSag: regSag,
        observaciones: observaciones,
        descuentoGlobal: descuentoGlobal,
        detalle: [
          for (var i = 0; i < items.length; i++)
            items[i].copyWith(precioCompraUsado: i < detalleCostos.length ? detalleCostos[i] : items[i].precioCompraUsado),
        ],
        esEnvio: esEnvio,
        envioNombre: envioNombre,
        envioDireccion: envioDireccion,
        envioTelefono: envioTelefono,
      );
    });
  }

  /// Guarda/actualiza los datos de envío de una venta YA hecha.
  Future<void> actualizarDatosEnvio({
    required String id,
    required String envioNombre,
    required String envioDireccion,
    required String envioTelefono,
  }) {
    return conRed(() => _db.from('ventas').update({
          'es_envio': true,
          'envio_nombre': envioNombre,
          'envio_direccion': envioDireccion,
          'envio_telefono': envioTelefono,
        }).eq('id', id));
  }

  // Best-effort: si el documento ya no existe no debe reventar con un error
  // feo en pantalla.
  Future<void> marcarPendienteImpresion(String id, bool valor) async {
    try {
      await _db.from('ventas').update({'pendiente_impresion': valor}).eq('id', id);
    } catch (_) {
      // silencioso a propósito, ver comentario arriba
    }
  }

  Future<void> marcarSolicitudImpresionEnVivo(String id, bool valor, {bool? esCopia}) async {
    try {
      await _db.from('ventas').update({'solicitud_impresion_en_vivo': valor, 'solicitud_impresion_es_copia': esCopia}).eq('id', id);
    } catch (_) {
      // silencioso a propósito
    }
  }

  Stream<List<VentaModel>> obtenerVentasConSolicitudImpresionEnVivo() {
    return conRedStream(() => _db
        .from('ventas')
        .stream(primaryKey: ['id'])
        .eq('solicitud_impresion_en_vivo', true)
        .map((filas) => filas.map((d) => VentaModel.fromMap(d['id'] as String, d, const [])).toList()));
  }

  Future<void> marcarSolicitudImpresionGuiaEnvio(String id, bool valor, {bool grande = false}) async {
    try {
      await _db.from('ventas').update({'solicitud_impresion_guia_envio': valor, 'solicitud_impresion_guia_grande': grande}).eq('id', id);
    } catch (_) {
      // silencioso a propósito
    }
  }

  Stream<List<VentaModel>> obtenerVentasConSolicitudImpresionGuiaEnvio() {
    return conRedStream(() => _db
        .from('ventas')
        .stream(primaryKey: ['id'])
        .eq('solicitud_impresion_guia_envio', true)
        .map((filas) => filas.map((d) => VentaModel.fromMap(d['id'] as String, d, const [])).toList()));
  }

  Future<VentaModel?> obtenerVentaPorId(String id) {
    return conRed(() async {
      final futureVenta = _db.from('ventas').select().eq('id', id).limit(1);
      final futureDetalle = _db.from('venta_items').select().eq('id_venta', id).order('orden');
      final filas = await futureVenta;
      if (filas.isEmpty) return null;
      final detalleFilas = await futureDetalle;
      final items = detalleFilas.map((d) => ItemVentaModel.fromRow(d)).toList();
      return VentaModel.fromMap(id, filas.first, items);
    });
  }

  /// Solo el detalle (items) de una venta, sin volver a leer el documento
  /// principal.
  Future<List<ItemVentaModel>> obtenerDetalleVenta(String id) {
    return conRed(() async {
      final filas = await _db.from('venta_items').select().eq('id_venta', id).order('orden');
      return filas.map((d) => ItemVentaModel.fromRow(d)).toList();
    });
  }

  Future<VentaModel?> obtenerVentaPorNumeroDocumento(String numeroDocumento) {
    return conRed(() async {
      final texto = numeroDocumento.trim();
      if (texto.isEmpty) return null;
      final filas = await _db.from('ventas').select().eq('numero_documento', texto).limit(1);
      if (filas.isEmpty) return null;
      final fila = filas.first;
      final detalleFilas = await _db.from('venta_items').select().eq('id_venta', fila['id']).order('orden');
      final items = detalleFilas.map((d) => ItemVentaModel.fromRow(d)).toList();
      return VentaModel.fromMap(fila['id'] as String, fila, items);
    });
  }

  /// Busca ventas por número de documento sin que el usuario tenga que
  /// escribir los ceros de relleno.
  Future<List<VentaModel>> buscarVentasPorNumeroDocumento(String texto, {String? tipoDocumento}) {
    return conRed(() async {
      final limpio = texto.trim();
      if (limpio.isEmpty) return <VentaModel>[];

      final candidatos = <String>{limpio};
      if (RegExp(r'^\d+$').hasMatch(limpio)) {
        candidatos.add(limpio.padLeft(8, '0'));
        candidatos.add(limpio.padLeft(4, '0'));
      }

      final listasFilas = await Future.wait(candidatos.map((c) => _db.from('ventas').select().eq('numero_documento', c)));
      final filas = listasFilas.expand((f) => f).toList();

      final resultados = <VentaModel>[];
      for (final fila in filas) {
        if (tipoDocumento != null && tipoDocumento.isNotEmpty && fila['tipo_documento'] != tipoDocumento) continue;
        final detalleFilas = await _db.from('venta_items').select().eq('id_venta', fila['id']).order('orden');
        final items = detalleFilas.map((d) => ItemVentaModel.fromRow(d)).toList();
        resultados.add(VentaModel.fromMap(fila['id'] as String, fila, items));
      }
      resultados.sort((a, b) => (b.fechaRegistro ?? DateTime(0)).compareTo(a.fechaRegistro ?? DateTime(0)));
      return resultados;
    });
  }

  /// Anula una venta: la marca como 'Anulada', repone al inventario el stock
  /// (ver `anular_venta` en supabase/schema.sql — hace atómicamente lo que
  /// en Firestore era una Transaction).
  Future<void> anularVenta({
    required String id,
    required String usuario,
    String motivo = '',
  }) {
    return conRed(() async {
      try {
        await _db.rpc('anular_venta', params: {'p_id': id, 'p_usuario': usuario, 'p_motivo': motivo});
      } on PostgrestException catch (e) {
        if (e.code == 'PGRST116' || (e.message.toLowerCase().contains('no se encontró'))) {
          throw Exception('No se pudo anular: la venta ya no existe en el servidor (puede que se haya borrado desde otro dispositivo)');
        }
        throw Exception(e.message);
      }
    });
  }

  /// Crea una venta MARCADA COMO PRUEBA (numeroDocumento 'PRUEBA', tipo
  /// 'VentaSinFacturar') para el botón "Imprimir ticket de prueba" de
  /// Negocio -pedido explícito del dueño para no tener que crear/anular
  /// ventas reales solo para probar que la impresora imprime bien-. Va
  /// DIRECTO a `ventas`/`venta_items` (sin pasar por `registrar_venta`): no
  /// toca contadores/correlativo real, no descuenta stock, `id_producto`
  /// queda null a propósito (no depende de que exista ningún producto real
  /// en el inventario). Se borra apenas termina la prueba, ver
  /// [eliminarVentaPrueba] -no debe quedar nunca en Reportes/Ver Facturas-.
  Future<VentaModel> crearVentaPrueba({required String usuario}) {
    return conRed(() async {
      final fila = await _db.from('ventas').insert({
        'tipo_documento': 'VentaSinFacturar',
        'numero_documento': 'PRUEBA',
        'nombre_cliente': 'PRUEBA DE IMPRESION',
        'metodo_pago': 'Efectivo',
        'monto_pago': 100,
        'monto_cambio': 0,
        'subtotal': 100,
        'impuesto': 0,
        'total_a_pagar': 100,
        'condicion': 'Contado',
        'estado': 'Activa',
        'usuario_registro': usuario,
        'cantidad_productos': 2,
      }).select().single();
      final id = fila['id'] as String;
      await _db.from('venta_items').insert({
        'id_venta': id,
        'nombre_producto': 'PRODUCTO DE PRUEBA',
        'precio_venta': 50,
        'cantidad': 2,
        'subtotal': 100,
        'orden': 0,
      });
      final items = [
        ItemVentaModel(
          idProducto: '',
          idCategoria: '',
          nombreProducto: 'PRODUCTO DE PRUEBA',
          precioVenta: 50,
          cantidad: 2,
          subtotal: 100,
          precioCompraUsado: 0,
        ),
      ];
      return VentaModel.fromMap(id, fila, items);
    });
  }

  /// Borra por completo la venta de prueba creada por [crearVentaPrueba]
  /// (`venta_items` cae con ella por el `on delete cascade`) — se llama
  /// siempre al cerrar el diálogo de prueba, haya salido bien la impresión
  /// o no, para que nunca quede una "PRUEBA" dando vueltas en Reportes.
  Future<void> eliminarVentaPrueba(String id) {
    return conRed(() => _db.from('ventas').delete().eq('id', id));
  }

  /// Ventas guardadas pero sin imprimir.
  Stream<List<VentaModel>> obtenerVentasPendientesImpresion() {
    return conRedStream(() => _db
        .from('ventas')
        .stream(primaryKey: ['id'])
        .eq('pendiente_impresion', true)
        .map((filas) {
      final ventas = filas.map((d) => VentaModel.fromMap(d['id'] as String, d, const [])).toList();
      ventas.sort((a, b) => (b.fechaRegistro ?? DateTime(0)).compareTo(a.fechaRegistro ?? DateTime(0)));
      return ventas;
    }));
  }

  /// Autoguardado silencioso de un carrito en curso. NUNCA toca stock.
  Future<String> guardarVentaEnEsperaAutomatica(VentaEnEsperaModel sesion) {
    return conRed(() async {
      if (sesion.id.isEmpty) {
        final fila = await _db.from('ventas_en_espera').insert({
          ...sesion.toRow(),
          'origen': OrigenVentaEnEspera.automatico,
          'stock_reservado': false,
        }).select('id').single();
        return fila['id'] as String;
      }
      // A propósito NO se tocan origen/stock_reservado/cantidades_reservadas
      // acá -si esta espera ya fue "reclamada" a mano, el autoguardado de
      // fondo no debe bajarla de rango ni tocar su reserva-.
      await _db.from('ventas_en_espera').update(sesion.toRow()).eq('id', sesion.id);
      return sesion.id;
    });
  }

  /// Guarda (crea o actualiza) una venta en espera puesta A MANO por el
  /// cajero — ver `guardar_venta_en_espera_manual` en supabase/schema.sql:
  /// reserva/suelta stock atómicamente, igual que la Transaction de Firestore.
  Future<String> guardarVentaEnEsperaManual(VentaEnEsperaModel sesion, {required String usuario, Set<String> categoriasSinControlStock = const {}}) {
    return conRed(() async {
      final resultado = await _db.rpc('guardar_venta_en_espera_manual', params: {
        'payload': {
          'id': sesion.id,
          ...sesion.toMap(),
          'usuario': usuario,
        },
      }) as String;
      return resultado;
    });
  }

  Stream<List<VentaEnEsperaModel>> _obtenerTodasVentasEnEsperaOPerdidas() {
    return conRedStream(() => _db.from('ventas_en_espera').stream(primaryKey: ['id']).map((filas) {
          final lista = filas.map((d) => VentaEnEsperaModel.fromMap(d['id'] as String, d)).toList();
          lista.sort((a, b) => (b.fecha ?? DateTime(0)).compareTo(a.fecha ?? DateTime(0)));
          return lista;
        }));
  }

  Stream<List<VentaEnEsperaModel>> obtenerVentasEnEspera() {
    return _obtenerTodasVentasEnEsperaOPerdidas().map((lista) => lista.where((v) => v.origen == OrigenVentaEnEspera.manual).toList());
  }

  Stream<List<VentaEnEsperaModel>> obtenerVentasPerdidas() {
    return _obtenerTodasVentasEnEsperaOPerdidas().map((lista) => lista.where((v) => v.origen != OrigenVentaEnEspera.manual).toList());
  }

  /// Elimina una venta en espera (manual o perdida). Si tenía una reserva de
  /// stock activa, la suelta primero — ver `eliminar_venta_en_espera`.
  Future<void> eliminarVentaEnEspera(String id, {String usuario = ''}) {
    return conRed(() => _db.rpc('eliminar_venta_en_espera', params: {'p_id': id, 'p_usuario': usuario}));
  }
}
