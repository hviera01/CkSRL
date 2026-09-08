class PermisosEspeciales {
  static const inventarioEditarProducto = 'inventario_editar_producto';
  static const inventarioAjustarStock = 'inventario_ajustar_stock';
  static const ventasCreditoEliminar = 'ventas_credito_eliminar';
  static const ventasCambiarPrecio = 'ventas_cambiar_precio';
  static const ventasEditarDescripcion = 'ventas_editar_descripcion';
  static const ventasVenderSinStock = 'ventas_vender_sin_stock';
  static const apartadosEditarPago = 'apartados_editar_pago';
  static const apartadosEliminarPago = 'apartados_eliminar_pago';

  // Claves nuevas para el rol Encargado: a diferencia de las de arriba,
  // estas no gatillan el diálogo de clave especial compartida, sino que se
  // usan como `accionKey` de `puedeRealizarAccion` (ver
  // core/utils/permisos_usuario.dart) para ocultar botones de crear/editar/
  // eliminar según lo que el Administrador marcó para ese usuario puntual.
  static const comprasCrear = 'compras_crear';
  static const comprasEditar = 'compras_editar';
  static const comprasEliminar = 'compras_eliminar';
  static const inventarioCrearProducto = 'inventario_crear_producto';
  static const inventarioEliminarProducto = 'inventario_eliminar_producto';
  static const clientesCrear = 'clientes_crear';
  static const clientesEditar = 'clientes_editar';
  static const clientesEliminar = 'clientes_eliminar';
  static const ventasEliminar = 'ventas_eliminar';

  static const Map<String, String> etiquetas = {
    inventarioEditarProducto: 'Editar productos en Inventario',
    inventarioAjustarStock: 'Cambiar existencias en Inventario',
    ventasCreditoEliminar: 'Eliminar créditos en Ventas a Crédito',
    ventasCambiarPrecio: 'Cambiar precio de un producto en Ventas',
    ventasEditarDescripcion: 'Editar descripción de un producto en Ventas',
    ventasVenderSinStock: 'Agregar a una venta un producto sin existencia',
    apartadosEditarPago: 'Editar un pago de Apartados ya registrado',
    apartadosEliminarPago: 'Eliminar un pago de Apartados ya registrado',
    comprasCrear: 'Registrar compras',
    comprasEditar: 'Editar compras',
    comprasEliminar: 'Anular compras',
    inventarioCrearProducto: 'Crear productos en Inventario',
    inventarioEliminarProducto: 'Eliminar productos en Inventario',
    clientesCrear: 'Crear clientes',
    clientesEditar: 'Editar clientes',
    clientesEliminar: 'Eliminar clientes',
    ventasEliminar: 'Anular ventas',
  };

  static const Map<String, String> descripciones = {
    inventarioEditarProducto:
        'Pide la clave especial antes de guardar cambios en un producto existente.',
    inventarioAjustarStock:
        'Pide la clave especial antes de confirmar un ajuste de existencia.',
    ventasCreditoEliminar:
        'Pide la clave especial antes de eliminar un crédito.',
    ventasCambiarPrecio:
        'Pide la clave especial antes de modificar el precio unitario de un producto dentro de una venta.',
    ventasEditarDescripcion:
        'Pide la clave especial antes de cambiar la descripción de un producto dentro de una venta.',
    ventasVenderSinStock:
        'Pide la clave especial antes de agregar a una venta (o aumentar la cantidad de) un producto sin existencia disponible, en categorías que sí controlan stock. Si se cancela, se ofrece igual la opción de reembasado.',
    apartadosEditarPago:
        'Pide la clave especial antes de editar un pago ya registrado de un apartado (monto o fecha), sin importar si el apartado sigue activo o ya fue entregado/cancelado.',
    apartadosEliminarPago:
        'Pide la clave especial antes de eliminar por completo un pago ya registrado de un apartado, sin importar si el apartado sigue activo o ya fue entregado/cancelado.',
    comprasCrear: 'Permite registrar una nueva compra.',
    comprasEditar: 'Permite editar una compra ya registrada.',
    comprasEliminar: 'Permite anular una compra ya registrada.',
    inventarioCrearProducto: 'Permite dar de alta un producto nuevo en Inventario.',
    inventarioEliminarProducto: 'Permite eliminar un producto de Inventario.',
    clientesCrear: 'Permite dar de alta un cliente nuevo.',
    clientesEditar: 'Permite editar los datos de un cliente existente.',
    clientesEliminar: 'Permite eliminar un cliente.',
    ventasEliminar: 'Permite anular una venta ya registrada.',
  };
}

/// Cómo se maneja la impresión de la factura al confirmar una venta
/// facturable (ver ModoImpresion.preguntar/directo).
class ModoImpresion {
  static const preguntar = 'preguntar';
  static const directo = 'directo';
}

class NegocioModel {
  final String nombre;
  final String correo;
  final String rtn;
  final String cai;
  final String direccion;
  final String telefono;
  final String eslogan;
  final String rangoPrefijo;
  final String rangoDesde;
  final String rangoHasta;
  final DateTime? fechaLimiteEmision;
  final String logoColorBase64;
  final String logoBnBase64;
  final String claveEspecialHash;
  final Map<String, bool> permisos;
  final String impresoraTermicaUrl;
  final String impresoraTermicaNombre;
  final String impresoraEtiquetasUrl;
  final String impresoraEtiquetasNombre;
  // Si es false, el ticket de venta solo imprime la hoja "ORIGINAL" (se
  // salta la "COPIA"), para no gastar papel de más cuando no hace falta.
  final bool facturaImprimirCopia;
  // Si es true, el precio unitario y el importe de cada línea del ticket se
  // muestran con ISV incluido (igual que el recuadro "Con ISV" del carrito
  // en Registrar Venta). Si es false (default, comportamiento de siempre)
  // se muestran sin ISV, con el ISV desglosado aparte en el total.
  final bool facturaPreciosConIsv;
  // ModoImpresion.preguntar (default, comportamiento de siempre) muestra el
  // diálogo de vista previa/descargar/imprimir; ModoImpresion.directo salta
  // ese diálogo e imprime directo en la impresora configurada.
  final String modoImpresion;
  // Impresora térmica de red (ESC/POS por socket TCP): la vía que sí
  // funciona desde el celular, donde no hay forma de listar impresoras del
  // sistema operativo.
  final String impresoraRedIp;
  final int impresoraRedPuerto;
  // Impresora térmica Bluetooth (ESC/POS), Android únicamente: mac (id) y
  // nombre del dispositivo ya emparejado que se eligió en Negocio (ver
  // SelectorImpresoraBluetooth). Vacío = sin impresora Bluetooth elegida
  // -RegistrarVentaScreen sigue con la impresora de red, y si tampoco hay,
  // con el respaldo remoto de siempre (ver _imprimirEscPosRed)-.
  final String impresoraBluetoothId;
  final String impresoraBluetoothNombre;
  // Ancho del rollo térmico -pedido explícito del dueño: "que existan las
  // DOS medidas disponibles, por si acaso"-. 58 = ticket angosto (32
  // columnas ESC/POS, tipo POS de tarjeta), 80 = el de siempre (48 columnas).
  // Afecta tanto la impresión ESC/POS real (ver VentaTicketEscPosService)
  // como su vista previa en pantalla (ver TicketEscPosPreview).
  final int anchoTicketMm;
  // Si es true, en tablet (ancho de pantalla de tablet + dispositivo táctil,
  // ver esTabletTactil en core/utils/tablet_utils.dart) los campos de texto
  // de toda la app abren un teclado propio, chico, en vez del teclado nativo
  // del sistema (que en tablet ocupa media pantalla) -ver CampoTecladoCompacto-.
  // No aplica en celular (el teclado nativo angosto ya funciona bien ahí) ni
  // en escritorio/PC.
  final bool tecladoCompactoTablet;
  // Hostname (ver core/utils/device_id.dart, mismo id que muestra la
  // pantalla de Dispositivos) de la PC que de verdad tiene la impresora
  // térmica conectada. Vacío (default) = comportamiento de siempre:
  // CUALQUIER escritorio (Windows/macOS/Linux) actúa como "PC principal"
  // (manda latido de presencia y procesa impresiones remotas pedidas desde
  // el celular). Si el dueño marca un hostname acá (ver Dispositivos >
  // "Marcar como PC principal" -pedido explícito: tenía otra PC propia,
  // sin impresora, y esa también se comportaba como si lo fuera-), SOLO esa
  // PC manda latido/procesa solicitudes; cualquier otro escritorio deja de
  // considerarse principal y, si no logra imprimir localmente, puede
  // preguntarle de verdad a Firestore si la de verdad está encendida antes
  // de pedirle que imprima ella (ver RegistrarVentaScreen._manejarImpresion).
  final String pcPrincipalHostname;
  // Interruptor MAESTRO de impresión: si es false, al confirmar una venta
  // facturable no se intenta imprimir nada (ni diálogo de vista previa ni
  // impresión directa) sin importar modoImpresion/facturaImprimirCopia. Para
  // negocios que todavía no tienen impresora física conectada. Default true
  // (comportamiento de siempre: sí se imprime).
  final bool imprimirFacturas;

  const NegocioModel({
    this.nombre = '',
    this.correo = '',
    this.rtn = '',
    this.cai = '',
    this.direccion = '',
    this.telefono = '',
    this.eslogan = '',
    this.rangoPrefijo = '',
    this.rangoDesde = '',
    this.rangoHasta = '',
    this.fechaLimiteEmision,
    this.logoColorBase64 = '',
    this.logoBnBase64 = '',
    this.claveEspecialHash = '',
    this.permisos = const {},
    this.impresoraTermicaUrl = '',
    this.impresoraTermicaNombre = '',
    this.impresoraEtiquetasUrl = '',
    this.impresoraEtiquetasNombre = '',
    this.facturaImprimirCopia = true,
    this.facturaPreciosConIsv = false,
    this.modoImpresion = ModoImpresion.preguntar,
    this.impresoraRedIp = '',
    this.impresoraRedPuerto = 9100,
    this.impresoraBluetoothId = '',
    this.impresoraBluetoothNombre = '',
    this.anchoTicketMm = 80,
    this.tecladoCompactoTablet = false,
    this.pcPrincipalHostname = '',
    this.imprimirFacturas = true,
  });

  bool get tieneClaveEspecial => claveEspecialHash.isNotEmpty;

  bool tienePermiso(String key) => permisos[key] == true;

  factory NegocioModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const NegocioModel();
    return NegocioModel(
      nombre: data['nombre'] ?? '',
      correo: data['correo'] ?? '',
      rtn: data['rtn'] ?? '',
      cai: data['cai'] ?? '',
      direccion: data['direccion'] ?? '',
      telefono: data['telefono'] ?? '',
      eslogan: data['eslogan'] ?? '',
      rangoPrefijo: data['rango_prefijo'] ?? '',
      rangoDesde: data['rango_desde'] ?? '',
      rangoHasta: data['rango_hasta'] ?? '',
      fechaLimiteEmision: data['fecha_limite_emision'] == null ? null : DateTime.parse(data['fecha_limite_emision'] as String),
      logoColorBase64: data['logo_color_base64'] ?? '',
      logoBnBase64: data['logo_bn_base64'] ?? '',
      claveEspecialHash: data['clave_especial_hash'] ?? '',
      permisos: Map<String, bool>.from(data['permisos'] ?? {}),
      impresoraTermicaUrl: data['impresora_termica_url'] ?? '',
      impresoraTermicaNombre: data['impresora_termica_nombre'] ?? '',
      impresoraEtiquetasUrl: data['impresora_etiquetas_url'] ?? '',
      impresoraEtiquetasNombre: data['impresora_etiquetas_nombre'] ?? '',
      facturaImprimirCopia: data['factura_imprimir_copia'] ?? true,
      facturaPreciosConIsv: data['factura_precios_con_isv'] ?? false,
      modoImpresion: data['modo_impresion'] ?? ModoImpresion.preguntar,
      impresoraRedIp: data['impresora_red_ip'] ?? '',
      impresoraRedPuerto: ((data['impresora_red_puerto'] ?? 9100) as num).toInt(),
      impresoraBluetoothId: data['impresora_bluetooth_id'] ?? '',
      impresoraBluetoothNombre: data['impresora_bluetooth_nombre'] ?? '',
      anchoTicketMm: ((data['ancho_ticket_mm'] ?? 80) as num).toInt(),
      tecladoCompactoTablet: data['teclado_compacto_tablet'] ?? false,
      pcPrincipalHostname: data['pc_principal_hostname'] ?? '',
      imprimirFacturas: data['imprimir_facturas'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'correo': correo,
      'rtn': rtn,
      'cai': cai,
      'direccion': direccion,
      'telefono': telefono,
      'eslogan': eslogan,
      'rango_prefijo': rangoPrefijo,
      'rango_desde': rangoDesde,
      'rango_hasta': rangoHasta,
      'fecha_limite_emision': fechaLimiteEmision?.toIso8601String(),
      'logo_color_base64': logoColorBase64,
      'logo_bn_base64': logoBnBase64,
      'clave_especial_hash': claveEspecialHash,
      'permisos': permisos,
      'impresora_termica_url': impresoraTermicaUrl,
      'impresora_termica_nombre': impresoraTermicaNombre,
      'impresora_etiquetas_url': impresoraEtiquetasUrl,
      'impresora_etiquetas_nombre': impresoraEtiquetasNombre,
      'factura_imprimir_copia': facturaImprimirCopia,
      'factura_precios_con_isv': facturaPreciosConIsv,
      'modo_impresion': modoImpresion,
      'impresora_red_ip': impresoraRedIp,
      'impresora_red_puerto': impresoraRedPuerto,
      'impresora_bluetooth_id': impresoraBluetoothId,
      'impresora_bluetooth_nombre': impresoraBluetoothNombre,
      'ancho_ticket_mm': anchoTicketMm,
      'teclado_compacto_tablet': tecladoCompactoTablet,
      'pc_principal_hostname': pcPrincipalHostname,
      'imprimir_facturas': imprimirFacturas,
    };
  }

  NegocioModel copyWith({
    String? nombre,
    String? correo,
    String? rtn,
    String? cai,
    String? direccion,
    String? telefono,
    String? eslogan,
    String? rangoPrefijo,
    String? rangoDesde,
    String? rangoHasta,
    DateTime? fechaLimiteEmision,
    String? logoColorBase64,
    String? logoBnBase64,
    String? claveEspecialHash,
    Map<String, bool>? permisos,
    String? impresoraTermicaUrl,
    String? impresoraTermicaNombre,
    String? impresoraEtiquetasUrl,
    String? impresoraEtiquetasNombre,
    bool? facturaImprimirCopia,
    bool? facturaPreciosConIsv,
    String? modoImpresion,
    String? impresoraRedIp,
    int? impresoraRedPuerto,
    String? impresoraBluetoothId,
    String? impresoraBluetoothNombre,
    int? anchoTicketMm,
    bool? tecladoCompactoTablet,
    String? pcPrincipalHostname,
    bool? imprimirFacturas,
  }) {
    return NegocioModel(
      nombre: nombre ?? this.nombre,
      correo: correo ?? this.correo,
      rtn: rtn ?? this.rtn,
      cai: cai ?? this.cai,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      eslogan: eslogan ?? this.eslogan,
      rangoPrefijo: rangoPrefijo ?? this.rangoPrefijo,
      rangoDesde: rangoDesde ?? this.rangoDesde,
      rangoHasta: rangoHasta ?? this.rangoHasta,
      fechaLimiteEmision: fechaLimiteEmision ?? this.fechaLimiteEmision,
      logoColorBase64: logoColorBase64 ?? this.logoColorBase64,
      logoBnBase64: logoBnBase64 ?? this.logoBnBase64,
      claveEspecialHash: claveEspecialHash ?? this.claveEspecialHash,
      permisos: permisos ?? this.permisos,
      impresoraTermicaUrl: impresoraTermicaUrl ?? this.impresoraTermicaUrl,
      impresoraTermicaNombre:
          impresoraTermicaNombre ?? this.impresoraTermicaNombre,
      impresoraEtiquetasUrl:
          impresoraEtiquetasUrl ?? this.impresoraEtiquetasUrl,
      impresoraEtiquetasNombre:
          impresoraEtiquetasNombre ?? this.impresoraEtiquetasNombre,
      facturaImprimirCopia: facturaImprimirCopia ?? this.facturaImprimirCopia,
      facturaPreciosConIsv: facturaPreciosConIsv ?? this.facturaPreciosConIsv,
      modoImpresion: modoImpresion ?? this.modoImpresion,
      impresoraRedIp: impresoraRedIp ?? this.impresoraRedIp,
      impresoraRedPuerto: impresoraRedPuerto ?? this.impresoraRedPuerto,
      impresoraBluetoothId: impresoraBluetoothId ?? this.impresoraBluetoothId,
      impresoraBluetoothNombre:
          impresoraBluetoothNombre ?? this.impresoraBluetoothNombre,
      anchoTicketMm: anchoTicketMm ?? this.anchoTicketMm,
      tecladoCompactoTablet:
          tecladoCompactoTablet ?? this.tecladoCompactoTablet,
      pcPrincipalHostname: pcPrincipalHostname ?? this.pcPrincipalHostname,
      imprimirFacturas: imprimirFacturas ?? this.imprimirFacturas,
    );
  }
}
