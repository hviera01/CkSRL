import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'apartado_model.dart';
import 'apartado_item_model.dart';
import 'apartado_cuota_model.dart';
import 'apartado_abono_model.dart';

/// Una cuota a crear junto con el apartado (modalidad 'cuotas_fijas'), ya
/// calculada del lado de Dart -ver CrearApartadoScreen-: acá no se hardcodea
/// ningún intervalo de días, la pantalla es la que decide cuántas cuotas y
/// cada cuánto.
class NuevaCuota {
  final int numeroCuota;
  final double montoProgramado;
  final DateTime fechaProgramada;

  NuevaCuota({
    required this.numeroCuota,
    required this.montoProgramado,
    required this.fechaProgramada,
  });

  Map<String, dynamic> toMap() => {
        'numeroCuota': numeroCuota,
        'montoProgramado': montoProgramado,
        // Solo fecha (sin hora): apartado_cuotas.fecha_programada es `date`.
        'fechaProgramada': fechaProgramada.toIso8601String().substring(0, 10),
      };
}

/// Un producto a apartar, con lo que ya se snapshoteó al elegirlo (ver
/// BuscarProductoDialog): mismo espíritu que ItemVentaModel, pero mucho más
/// chico -un apartado no maneja combos ni descuentos por línea-.
class NuevoItemApartado {
  final String? idProducto;
  final String nombreProducto;
  final double cantidad;
  final double precioUnitario;

  NuevoItemApartado({
    required this.idProducto,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
  });

  double get subtotal => cantidad * precioUnitario;

  Map<String, dynamic> toMap() => {
        'idProducto': idProducto,
        'nombreProducto': nombreProducto,
        'cantidad': cantidad,
        'precioUnitario': precioUnitario,
        'subtotal': subtotal,
      };
}

class ApartadoRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<ApartadoModel>> obtenerApartados() {
    return conRedStream(() => _db
        .from('apartados')
        .stream(primaryKey: ['id'])
        .order('fecha_creacion', ascending: false)
        .map((filas) => filas.map((d) => ApartadoModel.fromMap(d['id'] as String, d)).toList()));
  }

  Future<ApartadoModel?> obtenerApartado(String id) {
    return conRed(() async {
      final filas = await _db.from('apartados').select().eq('id', id).limit(1);
      if (filas.isEmpty) return null;
      return ApartadoModel.fromMap(filas.first['id'] as String, filas.first);
    });
  }

  Stream<List<ApartadoItemModel>> obtenerItems(String idApartado) {
    return conRedStream(() => _db
        .from('apartado_items')
        .stream(primaryKey: ['id'])
        .eq('id_apartado', idApartado)
        .map((filas) => filas.map((d) => ApartadoItemModel.fromMap(d['id'] as String, d)).toList()));
  }

  /// Todas las líneas de TODOS los apartados (sin filtrar por id) -para
  /// calcular, en Dart, cuánto hay apartado de cada producto en este momento
  /// (ver cantidadesApartadasProvider): mismo patrón que ya usa el resto de
  /// la app para "joins" en memoria sobre streams (ej. InventarioScreen con
  /// categorías), sin necesitar una vista con Realtime propio.
  Stream<List<ApartadoItemModel>> obtenerTodosLosItems() {
    return conRedStream(() => _db
        .from('apartado_items')
        .stream(primaryKey: ['id'])
        .map((filas) => filas.map((d) => ApartadoItemModel.fromMap(d['id'] as String, d)).toList()));
  }

  Stream<List<ApartadoCuotaModel>> obtenerCuotas(String idApartado) {
    return conRedStream(() => _db
        .from('apartado_cuotas')
        .stream(primaryKey: ['id'])
        .eq('id_apartado', idApartado)
        .order('numero_cuota', ascending: true)
        .map((filas) => filas.map((d) => ApartadoCuotaModel.fromMap(d['id'] as String, d)).toList()));
  }

  Stream<List<ApartadoAbonoModel>> obtenerAbonos(String idApartado) {
    return conRedStream(() => _db
        .from('apartado_abonos')
        .stream(primaryKey: ['id'])
        .eq('id_apartado', idApartado)
        .order('fecha', ascending: false)
        .map((filas) => filas.map((d) => ApartadoAbonoModel.fromMap(d['id'] as String, d)).toList()));
  }

  /// Igual que [obtenerTodosLosItems], pero de abonos/cuotas -para calcular
  /// el saldo pendiente de cada apartado en el LISTADO (ApartadosScreen) sin
  /// tener que abrir el detalle de cada uno.
  Stream<List<ApartadoAbonoModel>> obtenerTodosLosAbonos() {
    return conRedStream(() => _db
        .from('apartado_abonos')
        .stream(primaryKey: ['id'])
        .map((filas) => filas.map((d) => ApartadoAbonoModel.fromMap(d['id'] as String, d)).toList()));
  }

  Stream<List<ApartadoCuotaModel>> obtenerTodasLasCuotas() {
    return conRedStream(() => _db
        .from('apartado_cuotas')
        .stream(primaryKey: ['id'])
        .map((filas) => filas.map((d) => ApartadoCuotaModel.fromMap(d['id'] as String, d)).toList()));
  }

  /// Disponibilidad real de un producto puntual (stock físico menos lo ya
  /// apartado por otros apartados activos) -consulta la vista
  /// `producto_disponibilidad` (ver supabase/schema.sql)-. Se usa como aviso
  /// NO bloqueante al armar un apartado nuevo: el bloqueo de verdad (con
  /// lock, a prueba de carreras) vive en `crear_apartado` del lado del
  /// servidor.
  Future<double> obtenerDisponible(String idProducto) {
    return conRed(() async {
      final filas = await _db.from('producto_disponibilidad').select('disponible').eq('id_producto', idProducto).limit(1);
      if (filas.isEmpty) return 0;
      return (filas.first['disponible'] as num?)?.toDouble() ?? 0;
    });
  }

  /// Crea el apartado completo (cabecera + items + cuotas si aplica) de
  /// forma atómica -ver función `crear_apartado` en supabase/schema.sql-,
  /// que además valida (con lock) que cada producto tenga existencia
  /// disponible de verdad antes de insertar nada.
  Future<String> crearApartado({
    String? idCliente,
    required String nombreCliente,
    required double montoInicial,
    required String modalidad,
    required List<NuevoItemApartado> items,
    List<NuevaCuota> cuotas = const [],
    DateTime? fechaCreacion,
  }) {
    return conRed(() async {
      final montoTotal = items.fold<double>(0, (s, i) => s + i.subtotal);
      try {
        final resultado = await _db.rpc('crear_apartado', params: {
          'payload': {
            'idCliente': idCliente,
            'nombreCliente': nombreCliente,
            'montoTotal': montoTotal,
            'montoInicial': montoInicial,
            'modalidad': modalidad,
            'fechaCreacion': (fechaCreacion ?? DateTime.now()).toIso8601String(),
            'items': items.map((i) => i.toMap()).toList(),
            if (modalidad == 'cuotas_fijas') 'cuotas': cuotas.map((c) => c.toMap()).toList(),
          },
        }) as Map<String, dynamic>;
        return resultado['id'] as String;
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    });
  }

  /// Registra un pago sobre un apartado activo -de CUALQUIER modalidad,
  /// abonos_libres o cuotas_fijas- por el monto que el usuario haya
  /// tipeado (nunca forzado a coincidir con el monto exacto de una cuota):
  /// el saldo anterior se recalcula server-side, ver
  /// `registrar_abono_apartado`, que además -si la modalidad es
  /// cuotas_fijas- aplica el pago contra la(s) cuota(s) pendiente(s) más
  /// antigua(s) hasta agotar el monto, marcando pagada solo la que
  /// efectivamente cubre por completo (ver el comentario grande de esa
  /// función en supabase/schema.sql). [fecha] es la fecha que el usuario
  /// eligió para el registro (hoy por defecto, pero editable), no
  /// necesariamente el instante en que se guardó.
  Future<void> registrarAbono({required String idApartado, required double montoAbonado, DateTime? fecha}) {
    return conRed(() async {
      try {
        await _db.rpc('registrar_abono_apartado', params: {
          'payload': {
            'idApartado': idApartado,
            'montoAbonado': montoAbonado,
            'fecha': (fecha ?? DateTime.now()).toIso8601String(),
          },
        });
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    });
  }

  /// Entrega el apartado: acá se descuenta el stock físico de verdad (motor
  /// FIFO, ver `marcar_apartado_entregado`). Exige saldo pendiente en 0.
  Future<void> marcarEntregado({required String idApartado, required String usuario}) {
    return conRed(() async {
      try {
        await _db.rpc('marcar_apartado_entregado', params: {
          'p_id_apartado': idApartado,
          'p_usuario': usuario,
        });
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    });
  }

  /// Edita un pago ya registrado (monto y/o fecha) -acción sensible pensada
  /// para corregir errores de carga, disponible SIEMPRE (activo, completado o
  /// cancelado, ver DetalleApartadoScreen; del lado de Flutter ya pasó por
  /// verificarAccesoEspecial con PermisosEspeciales.apartadosEditarPago-. Una
  /// sola función atómica en Postgres (`editar_abono_apartado`, ver
  /// supabase/schema.sql) recalcula server-side, bloqueando la fila del
  /// apartado, el saldo_anterior/saldo_pendiente de TODOS los abonos
  /// posteriores y -si la modalidad es cuotas_fijas- vuelve a aplicar el
  /// total abonado contra las cuotas programadas desde cero: no son varios
  /// round-trips desde acá.
  Future<void> editarAbono({required String idAbono, required double montoAbonado, required DateTime fecha}) {
    return conRed(() async {
      try {
        await _db.rpc('editar_abono_apartado', params: {
          'payload': {
            'idAbono': idAbono,
            'montoAbonado': montoAbonado,
            'fecha': fecha.toIso8601String(),
          },
        });
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    });
  }

  /// Elimina por completo un pago ya registrado -mismo criterio que
  /// [editarAbono]: siempre disponible, recalcula toda la cadena de abonos
  /// (y cuotas, si aplica) server-side vía la misma función atómica.
  Future<void> eliminarAbono(String idAbono) {
    return conRed(() async {
      try {
        await _db.rpc('eliminar_abono_apartado', params: {'p_id_abono': idAbono});
      } on PostgrestException catch (e) {
        throw Exception(e.message);
      }
    });
  }

  /// Cancela un apartado activo -no repone nada, el producto nunca salió de
  /// existencia física-. Un solo UPDATE condicionado (estado='activo'), sin
  /// necesidad de función plpgsql.
  Future<void> cancelarApartado(String idApartado) {
    return conRed(() async {
      final actualizados = await _db
          .from('apartados')
          .update({'estado': 'cancelado'})
          .eq('id', idApartado)
          .eq('estado', 'activo')
          .select('id');
      if (actualizados.isEmpty) {
        throw Exception('Este apartado ya no está activo');
      }
    });
  }
}
