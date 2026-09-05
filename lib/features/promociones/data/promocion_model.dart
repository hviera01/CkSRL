/// Los 5 tipos de promoción que puede armar el usuario:
/// - [porcentaje]: % de descuento sobre uno o varios productos.
/// - [precioFijo]: precio especial (fijo) sobre uno o varios productos.
/// - [comboCantidad]: "llevando [cantidadRequerida] unidades de
///   [idProductoBase], se pagan [precioCombo]" (precio de bulto, MISMO
///   producto en cantidad).
/// - [comboMultiproducto]: "llevando 1 unidad de CADA UNO de los productos
///   en [idsProductosCombo] (2 o más productos DISTINTOS), el paquete
///   completo se paga [precioCombo]". No depende de cantidad por producto,
///   solo de que estén todos presentes en el carrito.
/// - [regalo]: "si lleva [cantidadRequerida] de [idProductoBase], se regalan
///   [cantidadRegalo] unidades de CADA producto en [idsProductosRegalo]".
enum TipoPromocion { porcentaje, precioFijo, comboCantidad, comboMultiproducto, regalo }

TipoPromocion tipoPromocionDesdeTexto(String? texto) {
  return TipoPromocion.values.firstWhere((t) => t.name == texto, orElse: () => TipoPromocion.porcentaje);
}

class PromocionModel {
  final String id;
  final String nombre;
  final TipoPromocion tipo;

  /// porcentaje / precioFijo: se aplica individualmente a cada producto de
  /// esta lista (mismo % o mismo precio especial en cada uno).
  final List<String> idsProductos;
  final List<String> nombresProductos;

  /// porcentaje: 0-100. precioFijo: el precio especial en Lempiras (con ISV,
  /// igual que el precio de venta que ve el cajero).
  final double valor;

  /// comboCantidad / regalo: producto sobre el que se cuenta la cantidad
  /// llevada.
  final String idProductoBase;
  final String nombreProductoBase;
  final int cantidadRequerida;

  /// comboCantidad: precio total (con ISV) a pagar por las
  /// [cantidadRequerida] unidades del producto base.
  /// comboMultiproducto: precio total (con ISV) del paquete completo (1
  /// unidad de cada producto en [idsProductosCombo]).
  final double precioCombo;

  /// comboMultiproducto: 2 o más productos DISTINTOS que arman el paquete,
  /// 1 unidad de cada uno.
  final List<String> idsProductosCombo;
  final List<String> nombresProductosCombo;

  /// regalo: productos que se regalan al completar [cantidadRequerida] del
  /// producto base. [cantidadRegalo] es la cantidad regalada de CADA
  /// producto de la lista (ej. cantidadRegalo=1 con 2 productos regalo =
  /// se regala 1 unidad de cada uno de los 2).
  final List<String> idsProductosRegalo;
  final List<String> nombresProductosRegalo;
  final int cantidadRegalo;

  final DateTime fechaInicio;
  final DateTime? fechaFin;

  /// 'Todos' | 'Contado' | 'Credito' — coincide con el campo `condicion` que
  /// ya usa el resto del sistema (ver CarritoVentaState.condicion). El
  /// nombre "alcancePago" es histórico y en realidad filtra por CONDICIÓN,
  /// no por método de pago (ver [metodosPagoAlcance] para eso) — no se
  /// renombra para no romper promociones ya creadas en producción.
  final String alcancePago;

  /// Vacía = todos los métodos de pago. Si no, uno o más de 'Efectivo' |
  /// 'Tarjeta' | 'Transferencia' (ej. el usuario puede aceptar la promo con
  /// Efectivo Y Transferencia, pero no con Tarjeta). Filtro independiente de
  /// [alcancePago]. 'Mixto' (CarritoVentaState.metodoPago) nunca matchea una
  /// lista restringida, solo vacía — no tendría sentido restringir a
  /// "Tarjeta" y que aplicara en un pago mixto que ni siquiera se sabe
  /// cuánto fue con tarjeta.
  final List<String> metodosPagoAlcance;

  final bool activo;
  final DateTime? creadoEn;
  final String creadoPor;

  PromocionModel({
    required this.id,
    required this.nombre,
    required this.tipo,
    this.idsProductos = const [],
    this.nombresProductos = const [],
    this.valor = 0,
    this.idProductoBase = '',
    this.nombreProductoBase = '',
    this.cantidadRequerida = 1,
    this.precioCombo = 0,
    this.idsProductosCombo = const [],
    this.nombresProductosCombo = const [],
    this.idsProductosRegalo = const [],
    this.nombresProductosRegalo = const [],
    this.cantidadRegalo = 1,
    required this.fechaInicio,
    this.fechaFin,
    this.alcancePago = 'Todos',
    this.metodosPagoAlcance = const [],
    this.activo = true,
    this.creadoEn,
    this.creadoPor = '',
  });

  bool get esIndefinida => fechaFin == null;
  bool get esPorcentajeOFijo => tipo == TipoPromocion.porcentaje || tipo == TipoPromocion.precioFijo;
  bool get esComboORegalo => tipo == TipoPromocion.comboCantidad || tipo == TipoPromocion.regalo;

  /// Si esta promoción está dentro de su vigencia (fecha y activa) en el
  /// momento [ahora]. No mira método de pago ni condición, ver
  /// [aplicaCondicion] y [aplicaMetodoPago].
  bool vigente(DateTime ahora) {
    if (!activo) return false;
    final inicio = DateTime(fechaInicio.year, fechaInicio.month, fechaInicio.day);
    if (ahora.isBefore(inicio)) return false;
    final fin = fechaFin;
    if (fin != null) {
      final finInclusive = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
      if (ahora.isAfter(finInclusive)) return false;
    }
    return true;
  }

  bool aplicaCondicion(String condicion) {
    if (alcancePago == 'Todos') return true;
    return alcancePago == condicion;
  }

  /// [metodoPago]: 'Efectivo' | 'Tarjeta' | 'Transferencia' | 'Mixto' (ver
  /// CarritoVentaState.metodoPago). 'Mixto' nunca matchea una lista
  /// restringida, solo vacía (todos) — no tendría sentido restringir un
  /// combo a "Tarjeta" y que aplicara en un pago mixto que ni siquiera se
  /// sabe cuánto fue con tarjeta.
  bool aplicaMetodoPago(String metodoPago) {
    if (metodosPagoAlcance.isEmpty) return true;
    return metodosPagoAlcance.contains(metodoPago);
  }

  bool aplicaAlProducto(String idProducto) {
    if (tipo == TipoPromocion.comboMultiproducto) return idsProductosCombo.contains(idProducto);
    if (esComboORegalo) return idProductoBase == idProducto;
    return idsProductos.contains(idProducto);
  }

  /// Texto corto para el badge/chip del buscador de productos.
  String get etiquetaCorta {
    switch (tipo) {
      case TipoPromocion.porcentaje:
        return '-${valor.toStringAsFixed(valor == valor.roundToDouble() ? 0 : 1)}%';
      case TipoPromocion.precioFijo:
        return 'Precio especial';
      case TipoPromocion.comboCantidad:
        return 'Combo x$cantidadRequerida';
      case TipoPromocion.comboMultiproducto:
        return 'Combo x${idsProductosCombo.length}';
      case TipoPromocion.regalo:
        return 'Lleva $cantidadRequerida y te regalamos $cantidadRegalo';
    }
  }

  /// [data] es la fila de `promociones` (columnas snake_case); las 3 listas
  /// de productos ya NO viven ahí (ver comentario en supabase/schema.sql:
  /// se normalizaron en la tabla puente `promocion_productos`, un catálogo
  /// VIVO en vez de un snapshot) — el repositorio las resuelve aparte
  /// (join contra `productos` para el nombre actual) y las pasa acá ya
  /// armadas, agrupadas por rol.
  factory PromocionModel.fromMap(
    String id,
    Map<String, dynamic> data, {
    List<String> idsProductos = const [],
    List<String> nombresProductos = const [],
    List<String> idsProductosCombo = const [],
    List<String> nombresProductosCombo = const [],
    List<String> idsProductosRegalo = const [],
    List<String> nombresProductosRegalo = const [],
  }) {
    return PromocionModel(
      id: id,
      nombre: data['nombre'] ?? '',
      tipo: tipoPromocionDesdeTexto(data['tipo'] as String?),
      idsProductos: idsProductos,
      nombresProductos: nombresProductos,
      valor: (data['valor'] ?? 0).toDouble(),
      idProductoBase: data['id_producto_base'] ?? '',
      nombreProductoBase: data['nombre_producto_base'] ?? '',
      cantidadRequerida: (data['cantidad_requerida'] ?? 1).toInt(),
      precioCombo: (data['precio_combo'] ?? 0).toDouble(),
      idsProductosCombo: idsProductosCombo,
      nombresProductosCombo: nombresProductosCombo,
      idsProductosRegalo: idsProductosRegalo,
      nombresProductosRegalo: nombresProductosRegalo,
      cantidadRegalo: (data['cantidad_regalo'] ?? 1).toInt(),
      fechaInicio: data['fecha_inicio'] == null ? DateTime.now() : DateTime.parse(data['fecha_inicio'] as String),
      fechaFin: data['fecha_fin'] == null ? null : DateTime.parse(data['fecha_fin'] as String),
      alcancePago: data['alcance_pago'] ?? 'Todos',
      metodosPagoAlcance: List<String>.from(data['metodos_pago_alcance'] ?? const []),
      activo: data['activo'] ?? true,
      creadoEn: data['creado_en'] == null ? null : DateTime.parse(data['creado_en'] as String),
      creadoPor: data['creado_por'] ?? '',
    );
  }

  /// Solo los campos propios de `promociones` -las listas de productos las
  /// escribe el repositorio aparte, en `promocion_productos`.
  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'tipo': tipo.name,
      'valor': valor,
      'id_producto_base': idProductoBase.isEmpty ? null : idProductoBase,
      'nombre_producto_base': nombreProductoBase,
      'cantidad_requerida': cantidadRequerida,
      'precio_combo': precioCombo,
      'cantidad_regalo': cantidadRegalo,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin?.toIso8601String(),
      'alcance_pago': alcancePago,
      'metodos_pago_alcance': metodosPagoAlcance,
      'activo': activo,
      'creado_por': creadoPor,
    };
  }

  String get textoBusqueda =>
      '$nombre ${nombresProductos.join(' ')} $nombreProductoBase ${nombresProductosCombo.join(' ')} ${nombresProductosRegalo.join(' ')}';
}
