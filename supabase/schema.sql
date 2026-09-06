-- ============================================================================
-- Ck S de R.L. de C.V. — esquema Postgres (Supabase)
-- Migración desde Firestore. Ver lib/features/**/data/*_model.dart y
-- *_repository.dart para el origen de cada tabla (comentado abajo, tabla por
-- tabla). Nombres en snake_case por convención de Postgres, aunque el
-- código Dart siga en camelCase -el mapeo lo hace la capa de datos Dart en
-- una fase posterior, este archivo no la toca-.
--
-- No se migran 'colores' ni 'formulas' (módulos ya eliminados del código: el
-- negocio de pinturas de la app original no aplica a Ck S de R.L. de C.V.).
--
-- No se migran 'roles' (lib/features/roles/data está vacío: los roles son
-- solo dos constantes de texto -Roles.administrador/Roles.empleado en
-- core/constants/roles.dart-, guardadas tal cual como texto en
-- usuarios.rol; no hay una colección/tabla de catálogo real detrás).
--
-- No se migra cliente_historial_model.dart ni MovimientoFinanciero
-- (egreso_model.dart): son vistas agregadas que hoy se arman en memoria
-- (Future.wait sobre ventas/créditos/abonos), no datos guardados aparte.
-- Se pueden seguir armando igual con consultas SQL sobre las tablas reales.
--
-- No se migra item_pedido_model.dart (compras): es una lista que solo vive
-- en memoria mientras se arma el PDF del pedido al proveedor, nunca se
-- guarda en Firestore.
--
-- No se migra escaneosRemotos (ventas/data/escaneo_remoto_repository.dart):
-- son sesiones de emparejamiento celular-PC de segundos de vida (código de
-- 6 caracteres + eventos), pensadas para borrarse solas al terminar. Encajan
-- mejor como un canal de Supabase Realtime (broadcast/presence) que como
-- filas de Postgres -no hay nada de eso que valga la pena conservar
-- históricamente-. Se deja fuera de este esquema a propósito; si hace falta
-- persistencia real más adelante, se agrega aparte.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extensión para poder usar gen_random_uuid() como default de las PK uuid.
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ============================================================================
-- CONFIGURACIÓN / INFRAESTRUCTURA (sin *_model.dart propio: viven como un
-- solo documento en Firestore, o son soporte interno de otros repositorios)
-- ============================================================================

-- 'configuracion/negocio' (negocio_model.dart / negocio_repository.dart).
-- Fila única de configuración del negocio -RTN, CAI, permisos especiales,
-- impresión, etc-. Igual que en Firestore, se fuerza a una sola fila con el
-- check (id = 1).
create table negocio_config (
  id smallint primary key default 1 check (id = 1),
  nombre text not null default '',
  correo text not null default '',
  rtn text not null default '',
  cai text not null default '',
  direccion text not null default '',
  telefono text not null default '',
  eslogan text not null default '',
  rango_prefijo text not null default '',
  rango_desde text not null default '',
  rango_hasta text not null default '',
  fecha_limite_emision timestamptz,
  logo_color_base64 text not null default '',
  logo_bn_base64 text not null default '',
  clave_especial_hash text not null default '',
  -- Map<String,bool> de PermisosEspeciales (negocio_model.dart): qué acción
  -- pide la clave especial. Estructura libre, no se consulta por SQL -jsonb-.
  permisos jsonb not null default '{}'::jsonb,
  impresora_termica_url text not null default '',
  impresora_termica_nombre text not null default '',
  impresora_etiquetas_url text not null default '',
  impresora_etiquetas_nombre text not null default '',
  factura_imprimir_copia boolean not null default true,
  factura_precios_con_isv boolean not null default false,
  modo_impresion text not null default 'preguntar' check (modo_impresion in ('preguntar', 'directo')),
  impresora_red_ip text not null default '',
  impresora_red_puerto integer not null default 9100,
  teclado_compacto_tablet boolean not null default false,
  pc_principal_hostname text not null default '',
  imprimir_facturas boolean not null default true
);
comment on table negocio_config is 'Fila única (id=1) — reemplaza el doc configuracion/negocio de Firestore.';

-- 'contadores/{clave}' (ver VentaRepository/CompraRepository._claveContador):
-- correlativo compartido de numeroDocumento por tipo de documento ('venta',
-- 'cotizacion', 'ventaSinFacturar', 'compra', ...).
create table contadores (
  clave text primary key,
  ultimo integer not null default 0
);
comment on table contadores is 'Correlativo del próximo numeroDocumento por tipo (reemplaza contadores/{clave}).';

-- 'presenciaImpresion/pcPrincipal' + 'presenciaAvisoWhatsapp/escuchador'
-- (PresenciaImpresionRepository / PresenciaAvisoWhatsappRepository): latido
-- periódico de "sigo viva" de la PC principal / de la tarea programada de
-- WhatsApp. Ambos documentos tenían la MISMA forma (solo un timestamp), así
-- que se consolidan en una sola tabla de 2 filas en vez de 2 tablas de 1
-- fila cada una.
create table presencia (
  id text primary key, -- 'pc_principal' | 'aviso_whatsapp_escuchador'
  ultimo_latido timestamptz
);
comment on table presencia is 'Latido de presencia (reemplaza presenciaImpresion/pcPrincipal y presenciaAvisoWhatsapp/escuchador).';

-- ============================================================================
-- CATÁLOGOS
-- ============================================================================

-- categoria_model.dart / categoria_repository.dart ('categorias')
create table categorias (
  id uuid primary key default gen_random_uuid(),
  descripcion text not null,
  estado boolean not null default true,
  controla_stock boolean not null default true
);
create index idx_categorias_descripcion on categorias (descripcion);
comment on table categorias is 'Reemplaza la colección categorias.';

-- cliente_model.dart / cliente_repository.dart ('clientes')
create table clientes (
  id uuid primary key default gen_random_uuid(),
  dni text not null default '',
  nombre_completo text not null,
  direccion text not null default '',
  telefono text not null default '',
  estado boolean not null default true,
  -- Denormalizado, se actualiza solo al registrar una venta real (ver
  -- VentaRepository.registrarVenta) — detecta clientes inactivos sin
  -- recorrer todas sus ventas.
  fecha_ultima_compra timestamptz,
  -- Quién trajo a este cliente (apunta a OTRO cliente con es_referidor=true).
  id_referidor uuid references clientes (id) on delete set null,
  es_referidor boolean not null default false,
  -- Campo interno (no viene de ClienteModel.toMap()): nombre normalizado
  -- (mayúsculas/tildes/espacios colapsados) para que VentaRepository pueda
  -- encontrar un cliente por nombre sin exigir igualdad exacta de string.
  nombre_normalizado text not null default '',
  fecha_registro timestamptz not null default now()
);
-- El DNI puede repetirse vacío (ClienteRepository solo valida duplicado
-- cuando dni.isNotEmpty), así que la unicidad es parcial.
create unique index uq_clientes_dni on clientes (dni) where dni <> '';
create index idx_clientes_nombre_completo on clientes (nombre_completo);
create index idx_clientes_nombre_normalizado on clientes (nombre_normalizado);
create index idx_clientes_id_referidor on clientes (id_referidor);
comment on table clientes is 'Reemplaza la colección clientes. Un "referidor" es solo un cliente con es_referidor=true (el módulo referidores aparte ya se eliminó en el código origen).';

-- proveedor_model.dart / proveedor_repository.dart ('proveedores')
create table proveedores (
  id uuid primary key default gen_random_uuid(),
  rtn text not null default '',
  razon_social text not null,
  correo text not null default '',
  telefono text not null default '',
  estado boolean not null default true
);
create index idx_proveedores_razon_social on proveedores (razon_social);
comment on table proveedores is 'Reemplaza la colección proveedores.';

-- usuario_model.dart (auth/ y usuarios/) + auth_repository.dart +
-- usuario_repository.dart ('usuarios'). Login CUSTOM (no Supabase Auth):
-- hash+sal propios (ver core/utils/clave_hash.dart) y bloqueo temporal por
-- intentos fallidos.
create table usuarios (
  id uuid primary key default gen_random_uuid(),
  documento text not null,
  nombre_completo text not null,
  correo text not null default '',
  rol text not null,
  estado boolean not null default true,
  clave text not null, -- hash (con sal, o legado sin sal — ver ClaveHash)
  sal text not null default '',
  intentos_fallidos integer not null default 0,
  bloqueado_hasta timestamptz,
  fecha_registro timestamptz not null default now()
);
create unique index uq_usuarios_documento on usuarios (documento);
comment on table usuarios is 'Reemplaza la colección usuarios. Login propio (código de acceso = documento + clave), NO usa Supabase Auth.';

-- producto_model.dart / producto_repository.dart ('productos')
create table productos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  codigo_barras text not null default '',
  nombre text not null,
  descripcion text not null default '',
  id_categoria uuid references categorias (id) on delete restrict,
  -- Cantidades en numeric(14,3) (no (12,2)): a diferencia de los montos en
  -- Lempiras, una existencia puede necesitar más de 2 decimales (galones,
  -- litros, fracciones de unidad).
  stock numeric(14, 3) not null default 0,
  precio_compra numeric(12, 2) not null default 0,
  precio_venta numeric(12, 2) not null default 0,
  precio_venta2 numeric(12, 2) not null default 0,
  precio_venta3 numeric(12, 2) not null default 0,
  estado boolean not null default true,
  imagen_url text not null default '',
  es_combo boolean not null default false,
  -- Receta de un combo/kit: [{idProducto, cantidad}] (ComponenteProductoModel).
  -- jsonb a propósito -estructura anidada que no hace falta consultar por
  -- SQL, mismo criterio que el resto de "snapshots"-.
  componentes jsonb not null default '[]'::jsonb,
  fecha_registro timestamptz not null default now()
);
create unique index uq_productos_codigo on productos (codigo);
create index idx_productos_id_categoria on productos (id_categoria);
create index idx_productos_codigo_barras on productos (codigo_barras);
create index idx_productos_nombre on productos (nombre);
comment on table productos is 'Reemplaza la colección productos.';

-- ============================================================================
-- COMPRAS (necesarias antes de los hijos de productos que referencian
-- compras: lotes de costo e historial de precios de compra)
-- ============================================================================

-- compra_model.dart / compra_repository.dart ('compras')
create table compras (
  id uuid primary key default gen_random_uuid(),
  tipo_documento text not null default 'Factura',
  numero_documento text not null,
  no_factura text not null default '',
  id_proveedor uuid references proveedores (id) on delete restrict,
  documento_proveedor text not null default '',
  razon_social text not null default '',
  condicion text not null default 'Contado',
  metodo_pago text not null default '',
  subtotal numeric(12, 2) not null default 0,
  descuento_global_porcentaje numeric(6, 2) not null default 0,
  descuento_total_monto numeric(12, 2) not null default 0,
  isv_porcentaje numeric(6, 2) not null default 15,
  impuesto numeric(12, 2) not null default 0,
  ajuste_manual numeric(12, 2) not null default 0,
  total_a_pagar numeric(12, 2) not null default 0,
  fecha_registro timestamptz not null default now(),
  fecha_vencimiento timestamptz,
  estado text not null default 'Activa',
  usuario_registro text not null default '',
  cantidad_productos numeric(14, 3) not null default 0,
  usuario_anulacion text not null default '',
  motivo_anulacion text not null default '',
  fecha_anulacion timestamptz
);
create index idx_compras_numero_documento on compras (numero_documento);
create index idx_compras_id_proveedor on compras (id_proveedor);
create index idx_compras_estado on compras (estado);
create index idx_compras_fecha_registro on compras (fecha_registro);
comment on table compras is 'Reemplaza la colección compras (cabecera; ver compra_items para el detalle, antes un array embebido/subcolección detalle).';

-- item_compra_model.dart — subcolección 'detalle' de cada compra.
create table compra_items (
  id uuid primary key default gen_random_uuid(),
  id_compra uuid not null references compras (id) on delete cascade,
  id_producto uuid references productos (id) on delete restrict,
  id_categoria uuid references categorias (id) on delete restrict,
  nombre_producto text not null,
  precio_compra numeric(12, 2) not null default 0,
  cantidad numeric(14, 3) not null,
  subtotal numeric(12, 2) not null default 0,
  descuento_porcentaje numeric(6, 2) not null default 0,
  -- Nuevo precio de venta a aplicar al producto al registrar la compra (null
  -- = no cambiar).
  precio_venta_nuevo numeric(12, 2),
  -- Vínculo manual a una venta anticipada de OTRO producto de catálogo (ver
  -- PendienteReposicionModel) — la FK real se agrega más abajo con ALTER
  -- TABLE porque pendientes_reposicion se crea después (depende, a su vez,
  -- de ventas/venta_items).
  id_pendiente_reposicion_vinculado uuid,
  numero_documento_venta_vinculada text,
  nombre_producto_venta_vinculada text
);
create index idx_compra_items_id_compra on compra_items (id_compra);
create index idx_compra_items_id_producto on compra_items (id_producto);
comment on table compra_items is 'Detalle de compras (antes subcolección compras/{id}/detalle).';

-- compra_en_espera_model.dart ('comprasEnEspera'). Igual que en Firestore,
-- [items] queda embebido tal cual (jsonb) -ahí NO era una subcolección real,
-- a diferencia de compras/detalle-.
create table compras_en_espera (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  id_proveedor uuid references proveedores (id) on delete set null,
  documento_proveedor text not null default '',
  razon_social text not null default '',
  no_factura text not null default '',
  condicion text not null default 'Contado',
  metodo_pago text not null default 'Efectivo',
  fecha_registro timestamptz,
  fecha_vencimiento timestamptz,
  descuento_global_porcentaje numeric(6, 2) not null default 0,
  isv_porcentaje numeric(6, 2) not null default 15,
  ajuste_manual numeric(12, 2) not null default 0,
  items jsonb not null default '[]'::jsonb -- ItemCompraModel[] embebido
);
create index idx_compras_en_espera_fecha on compras_en_espera (fecha);
comment on table compras_en_espera is 'Reemplaza comprasEnEspera (borradores de compra guardados).';

-- compra_credito_model.dart ('comprasCredito'). OJO: en Firestore este doc
-- se crea con el MISMO id que la compra origen cuando viene de una compra
-- real (ver CompraRepository). Acá no se fuerza esa igualdad con una FK
-- (rompería para créditos manuales sin compra real) — la app la respeta al
-- insertar (usa el mismo uuid en compras.id y compras_credito.id cuando
-- corresponde).
create table compras_credito (
  id uuid primary key default gen_random_uuid(),
  id_proveedor uuid references proveedores (id) on delete restrict,
  documento_proveedor text not null default '',
  nombre_proveedor text not null default '',
  numero_documento text not null,
  no_factura text not null default '',
  monto_total numeric(12, 2) not null,
  saldo_pendiente numeric(12, 2) not null,
  fecha_registro timestamptz not null default now(),
  fecha_vencimiento timestamptz,
  manual boolean not null default true
);
create index idx_compras_credito_numero_documento on compras_credito (numero_documento);
create index idx_compras_credito_id_proveedor on compras_credito (id_proveedor);
create index idx_compras_credito_fecha_vencimiento on compras_credito (fecha_vencimiento);
comment on table compras_credito is 'Reemplaza comprasCredito.';

-- abono_compra_model.dart — subcolección 'abonosCompra' de cada crédito de compra.
create table compra_credito_abonos (
  id uuid primary key default gen_random_uuid(),
  id_compra_credito uuid not null references compras_credito (id) on delete cascade,
  id_proveedor uuid references proveedores (id) on delete restrict,
  nombre_proveedor text not null default '',
  fecha timestamptz not null,
  monto_abonado numeric(12, 2) not null,
  saldo_anterior numeric(12, 2) not null,
  interes numeric(12, 2) not null default 0,
  saldo_pendiente numeric(12, 2) not null,
  metodo_pago text not null default '',
  numero_recibo text not null default '',
  usuario text not null default ''
);
create index idx_compra_credito_abonos_id_compra_credito on compra_credito_abonos (id_compra_credito);
create index idx_compra_credito_abonos_fecha on compra_credito_abonos (fecha);
comment on table compra_credito_abonos is 'Reemplaza comprasCredito/{id}/abonosCompra.';

-- ============================================================================
-- PRODUCTOS: hijos que referencian compras (lotes de costo FIFO e historial
-- de precio de compra)
-- ============================================================================

-- lote_costo_model.dart / lote_costo_repository.dart — subcolección 'lotes'
-- de cada producto. Motor de costeo FIFO real (no un historial de solo
-- lectura): se consume/actualiza en cada venta, compra y ajuste de stock.
create table producto_lotes_costo (
  id uuid primary key default gen_random_uuid(),
  id_producto uuid not null references productos (id) on delete cascade,
  cantidad_original numeric(14, 3) not null,
  cantidad_restante numeric(14, 3) not null,
  costo_unitario numeric(12, 2) not null,
  fecha timestamptz not null,
  origen text not null default 'compra', -- 'compra' | 'ajuste' | 'inicial'
  id_compra uuid references compras (id) on delete set null,
  -- Orden manual (0 = sale primero). Null = FIFO por fecha (comportamiento
  -- de siempre) — ver LoteCostoRepository.reordenarLotes.
  prioridad integer
);
create index idx_producto_lotes_costo_id_producto on producto_lotes_costo (id_producto);
create index idx_producto_lotes_costo_id_compra on producto_lotes_costo (id_compra);
create index idx_producto_lotes_costo_fecha on producto_lotes_costo (fecha);
comment on table producto_lotes_costo is 'Reemplaza productos/{id}/lotes (costeo FIFO real, no solo historial).';

-- historial_precio_compra_model.dart — subcolección 'historialPreciosCompra'.
create table producto_historial_precios_compra (
  id uuid primary key default gen_random_uuid(),
  id_producto uuid not null references productos (id) on delete cascade,
  id_compra uuid not null references compras (id) on delete cascade,
  precio_compra numeric(12, 2) not null,
  precio_unitario numeric(12, 2) not null,
  descuento_porcentaje numeric(6, 2) not null default 0,
  isv_porcentaje numeric(6, 2) not null default 0,
  cantidad numeric(14, 3) not null,
  fecha timestamptz,
  numero_documento text not null default '',
  no_factura text not null default '',
  proveedor text not null default '',
  usuario text not null default ''
);
create index idx_producto_hist_precios_compra_id_producto on producto_historial_precios_compra (id_producto);
create index idx_producto_hist_precios_compra_id_compra on producto_historial_precios_compra (id_compra);
create index idx_producto_hist_precios_compra_fecha on producto_historial_precios_compra (fecha);
comment on table producto_historial_precios_compra is 'Reemplaza productos/{id}/historialPreciosCompra.';

-- historial_stock_model.dart — subcolección 'historial' (todo movimiento de
-- stock: venta, compra, ajuste manual, anulaciones, reembasado).
create table producto_historial_stock (
  id uuid primary key default gen_random_uuid(),
  id_producto uuid not null references productos (id) on delete cascade,
  stock_anterior numeric(14, 3) not null,
  stock_nuevo numeric(14, 3) not null,
  fecha timestamptz not null default now(),
  usuario text not null default '',
  motivo text not null default ''
);
create index idx_producto_historial_stock_id_producto on producto_historial_stock (id_producto);
create index idx_producto_historial_stock_fecha on producto_historial_stock (fecha);
comment on table producto_historial_stock is 'Reemplaza productos/{id}/historial. El tipo de movimiento (venta/compra/ajuste/...) se sigue infiriendo del texto de motivo, igual que HistorialStockModel.tipo en Dart.';

-- ============================================================================
-- VENTAS
-- ============================================================================

-- venta_model.dart / venta_repository.dart ('ventas')
create table ventas (
  id uuid primary key default gen_random_uuid(),
  tipo_documento text not null default 'Factura',
  numero_documento text not null,
  documento_cliente text not null default '',
  nombre_cliente text not null default '',
  id_cliente uuid references clientes (id) on delete set null,
  metodo_pago text not null default '',
  monto_pago numeric(12, 2) not null default 0,
  monto_cambio numeric(12, 2) not null default 0,
  subtotal numeric(12, 2) not null default 0,
  impuesto numeric(12, 2) not null default 0,
  total_a_pagar numeric(12, 2) not null default 0,
  condicion text not null default 'Contado',
  fecha_vencimiento timestamptz,
  fecha_registro timestamptz not null default now(),
  estado text not null default 'Activa',
  usuario_registro text not null default '',
  cantidad_productos numeric(14, 3) not null default 0,
  oc text not null default '',
  reg_exonerado text not null default '',
  reg_sag text not null default '',
  descuento_global numeric(6, 2) not null default 0,
  observaciones text not null default '',
  -- Desglose cuando metodo_pago == 'Mixto': [{metodoPago, monto}]. Vacío en
  -- cualquier otro caso (PagoDetalle.listaToMaps).
  pagos_mixtos jsonb not null default '[]'::jsonb,
  usuario_anulacion text not null default '',
  motivo_anulacion text not null default '',
  fecha_anulacion timestamptz,
  pendiente_impresion boolean not null default false,
  solicitud_impresion_en_vivo boolean not null default false,
  -- null = no es un reimprimir con elección explícita (venta recién
  -- confirmada); true/false si es reimpresión de copia/original.
  solicitud_impresion_es_copia boolean,
  es_envio boolean not null default false,
  envio_nombre text not null default '',
  envio_direccion text not null default '',
  envio_telefono text not null default '',
  solicitud_impresion_guia_envio boolean not null default false,
  solicitud_impresion_guia_grande boolean not null default false
);
-- El dueño puede reservar/consultar el próximo numeroDocumento (ver
-- reservarProximoNumeroFactura), así que se busca seguido por este campo.
create index idx_ventas_numero_documento on ventas (numero_documento);
create index idx_ventas_id_cliente on ventas (id_cliente);
create index idx_ventas_estado on ventas (estado);
create index idx_ventas_fecha_registro on ventas (fecha_registro);
-- Índices parciales: estos 3 flags se consultan con streams filtrados
-- (where ==true) para impresión/guía remota, exactamente igual que hoy.
create index idx_ventas_solicitud_impresion_en_vivo on ventas (id) where solicitud_impresion_en_vivo;
create index idx_ventas_pendiente_impresion on ventas (id) where pendiente_impresion;
create index idx_ventas_solicitud_impresion_guia_envio on ventas (id) where solicitud_impresion_guia_envio;
comment on table ventas is 'Reemplaza la colección ventas (cabecera; ver venta_items para el detalle, antes subcolección detalle).';

-- item_venta_model.dart — subcolección 'detalle' de cada venta (YA era una
-- subcolección real en Firestore, no un array embebido: acá se normaliza
-- igual, como tabla hija con FK).
create table venta_items (
  id uuid primary key default gen_random_uuid(),
  id_venta uuid not null references ventas (id) on delete cascade,
  id_producto uuid references productos (id) on delete restrict,
  id_categoria uuid references categorias (id) on delete restrict,
  nombre_producto text not null,
  precio_venta numeric(12, 2) not null,
  cantidad numeric(14, 3) not null,
  subtotal numeric(12, 2) not null,
  precio_compra_usado numeric(12, 2) not null default 0,
  reembasado boolean not null default false,
  descuento_porcentaje numeric(6, 2) not null default 0,
  -- Receta congelada de combo al momento de vender (ComponenteComboSnapshot[]).
  componentes jsonb not null default '[]'::jsonb,
  -- "Venta anticipada": costo provisional hasta que la reponga una compra real.
  pendiente_compra boolean not null default false,
  -- Códigos de color usados en la línea (texto libre; el catálogo de
  -- colores/fórmulas del negocio de pinturas original no aplica acá).
  codigos_color text[] not null default '{}'
);
create index idx_venta_items_id_venta on venta_items (id_venta);
create index idx_venta_items_id_producto on venta_items (id_producto);
comment on table venta_items is 'Detalle de ventas (antes subcolección ventas/{id}/detalle).';

-- historial_venta_producto_model.dart — subcolección 'historialVentas'.
create table producto_historial_ventas (
  id uuid primary key default gen_random_uuid(),
  id_producto uuid not null references productos (id) on delete cascade,
  id_venta uuid not null references ventas (id) on delete cascade,
  precio_venta numeric(12, 2) not null,
  precio_unitario numeric(12, 2) not null,
  descuento_porcentaje numeric(6, 2) not null default 0,
  cantidad numeric(14, 3) not null,
  fecha timestamptz,
  tipo_documento text not null default '',
  numero_documento text not null default '',
  cliente text not null default '',
  usuario text not null default ''
);
create index idx_producto_hist_ventas_id_producto on producto_historial_ventas (id_producto);
create index idx_producto_hist_ventas_id_venta on producto_historial_ventas (id_venta);
create index idx_producto_hist_ventas_fecha on producto_historial_ventas (fecha);
comment on table producto_historial_ventas is 'Reemplaza productos/{id}/historialVentas.';

-- venta_en_espera_model.dart ('ventasEnEspera'). [items] queda embebido tal
-- cual (jsonb) -en Firestore tampoco era subcolección real-.
create table ventas_en_espera (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null default now(),
  tipo_documento text not null default 'Factura',
  condicion text not null default 'Contado',
  metodo_pago text not null default 'Efectivo',
  documento_cliente text not null default '',
  nombre_cliente text not null default '',
  id_cliente uuid references clientes (id) on delete set null,
  fecha_vencimiento timestamptz,
  oc text not null default '',
  reg_exonerado text not null default '',
  reg_sag text not null default '',
  observaciones text not null default '',
  descuento_global numeric(6, 2) not null default 0,
  items jsonb not null default '[]'::jsonb, -- ItemVentaModel[] embebido
  -- 'manual' (Guardar en Espera real, reserva stock) | 'automatico'
  -- (autoguardado silencioso, nunca reserva stock — ver OrigenVentaEnEspera).
  origen text not null default 'automatico',
  stock_reservado boolean not null default false,
  -- Foto INMUTABLE de lo reservado (idProducto -> cantidad) — no se
  -- recalcula de items al leer, ver comentario grande en VentaEnEsperaModel.
  cantidades_reservadas jsonb not null default '{}'::jsonb
);
create index idx_ventas_en_espera_fecha on ventas_en_espera (fecha);
create index idx_ventas_en_espera_origen on ventas_en_espera (origen);
comment on table ventas_en_espera is 'Reemplaza ventasEnEspera (borradores de venta, con o sin reserva real de stock).';

-- venta_credito_model.dart ('ventasCredito'). Igual que compras_credito: en
-- Firestore comparte id con la venta origen cuando aplica; acá tampoco se
-- fuerza con FK (créditos manuales/importados/fusionados no tienen venta
-- real detrás — ver sin_venta_origen).
create table ventas_credito (
  id uuid primary key default gen_random_uuid(),
  documento_cliente text not null default '',
  nombre_cliente text not null default '',
  id_cliente uuid references clientes (id) on delete set null,
  numero_documento text not null,
  monto_total numeric(12, 2) not null,
  saldo_pendiente numeric(12, 2) not null,
  fecha_registro timestamptz not null default now(),
  fecha_vencimiento timestamptz,
  fusionada boolean not null default false,
  -- Teléfono de contacto de ESTE crédito puntual — independiente del
  -- teléfono del cliente (editable acá sin pisar el del cliente).
  telefono text not null default '',
  solicitud_aviso_whatsapp boolean not null default false,
  error_aviso_whatsapp text,
  -- true si este crédito no tiene un documento de venta real asociado
  -- (manual, importado, o nacido de "Unir Facturas").
  sin_venta_origen boolean not null default false,
  -- Facturas que se combinaron para formar este crédito (solo "Unir
  -- Facturas"): [{id, numeroDocumento, saldoPendiente}]. jsonb porque son
  -- ids que pueden apuntar a créditos que ya no son consultables como fila
  -- real (encadenamiento de fusiones) — snapshot histórico, no catálogo vivo.
  facturas_origen jsonb not null default '[]'::jsonb
);
create index idx_ventas_credito_numero_documento on ventas_credito (numero_documento);
create index idx_ventas_credito_id_cliente on ventas_credito (id_cliente);
create index idx_ventas_credito_documento_cliente on ventas_credito (documento_cliente);
create index idx_ventas_credito_fecha_vencimiento on ventas_credito (fecha_vencimiento);
create index idx_ventas_credito_solicitud_aviso_whatsapp on ventas_credito (id) where solicitud_aviso_whatsapp;
comment on table ventas_credito is 'Reemplaza ventasCredito.';

-- abono_model.dart — subcolección 'abonos' de cada crédito de venta.
create table venta_credito_abonos (
  id uuid primary key default gen_random_uuid(),
  id_venta_credito uuid not null references ventas_credito (id) on delete cascade,
  fecha timestamptz not null,
  monto_abonado numeric(12, 2) not null,
  saldo_anterior numeric(12, 2) not null,
  interes numeric(12, 2) not null default 0,
  saldo_pendiente numeric(12, 2) not null,
  metodo_pago text not null default '',
  numero_recibo text not null default '',
  usuario text not null default ''
);
create index idx_venta_credito_abonos_id_venta_credito on venta_credito_abonos (id_venta_credito);
create index idx_venta_credito_abonos_fecha on venta_credito_abonos (fecha);
comment on table venta_credito_abonos is 'Reemplaza ventasCredito/{id}/abonos.';

-- ============================================================================
-- pendientes_reposicion: depende de ventas + venta_items + productos +
-- categorias, así que se crea después de todos esos.
-- ============================================================================

-- pendiente_reposicion_model.dart ('pendientesReposicion'). Rastrea una
-- línea de venta "pendiente de compra" (venta anticipada) hasta que la
-- próxima compra del producto la reponga (ver PendienteReposicionRepository).
create table pendientes_reposicion (
  id uuid primary key default gen_random_uuid(),
  id_venta uuid references ventas (id) on delete cascade,
  numero_documento_venta text not null default '',
  id_item_detalle uuid references venta_items (id) on delete cascade,
  id_producto uuid references productos (id) on delete restrict,
  nombre_producto text not null default '',
  id_categoria uuid references categorias (id) on delete set null,
  cantidad_original numeric(14, 3) not null,
  cantidad_pendiente numeric(14, 3) not null,
  costo_registrado numeric(12, 2) not null,
  fecha_registro timestamptz not null default now(),
  estado text not null default 'Pendiente', -- 'Pendiente' | 'Completado' | 'Cancelado'
  fecha_completado timestamptz,
  usuario text not null default ''
);
create index idx_pendientes_reposicion_estado on pendientes_reposicion (estado);
create index idx_pendientes_reposicion_fecha_registro on pendientes_reposicion (fecha_registro);
create index idx_pendientes_reposicion_id_producto on pendientes_reposicion (id_producto);
create index idx_pendientes_reposicion_id_venta on pendientes_reposicion (id_venta);
comment on table pendientes_reposicion is 'Reemplaza pendientesReposicion.';

-- Ahora sí se pueden cerrar las 2 referencias que quedaron pendientes más
-- arriba (forward references a tablas que no existían todavía):
alter table producto_lotes_costo
  add constraint fk_producto_lotes_costo_id_compra
  foreign key (id_compra) references compras (id) on delete set null;

alter table compra_items
  add constraint fk_compra_items_pendiente_reposicion
  foreign key (id_pendiente_reposicion_vinculado) references pendientes_reposicion (id) on delete set null;

create index idx_compra_items_pendiente_reposicion on compra_items (id_pendiente_reposicion_vinculado);

-- ============================================================================
-- EGRESOS / PROMOCIONES / DISPOSITIVOS / CAJA
-- ============================================================================

-- egreso_model.dart / egreso_repository.dart ('egresos')
create table egresos (
  id uuid primary key default gen_random_uuid(),
  fecha timestamptz not null,
  monto numeric(12, 2) not null,
  descripcion text not null default '',
  usuario text not null default '',
  metodo_pago text not null default 'Efectivo',
  categoria text not null default 'Negocio',
  es_pagado boolean not null default true,
  fecha_pago timestamptz,
  fecha_registro timestamptz not null default now()
);
create index idx_egresos_fecha on egresos (fecha);
create index idx_egresos_categoria on egresos (categoria);
create index idx_egresos_metodo_pago on egresos (metodo_pago);
comment on table egresos is 'Reemplaza egresos. El "libro financiero" (MovimientoFinanciero) sigue siendo una consulta agregada sobre ventas/ventas_credito/venta_credito_abonos/compras/compras_credito/compra_credito_abonos/egresos, no una tabla aparte.';

-- promocion_model.dart / promocion_repository.dart ('promociones'). A
-- diferencia de los combos de venta/compra (que SÍ son snapshots
-- históricos, jsonb), las listas de productos de una promoción son un
-- catálogo VIVO y editable -no hace falta preservar el nombre viejo de un
-- producto si lo renombran-, así que en vez de repetir los arrays paralelos
-- idsProductos/nombresProductos (y sus 2 pares hermanos) tal cual venían de
-- Firestore, se normalizan en la tabla puente promocion_productos: permite
-- además la consulta natural "¿qué promociones aplican a este producto?"
-- sin tener que traer todas las promociones activas al cliente.
create table promociones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  -- 'porcentaje' | 'precioFijo' | 'comboCantidad' | 'comboMultiproducto' | 'regalo'
  tipo text not null check (
    tipo in ('porcentaje', 'precioFijo', 'comboCantidad', 'comboMultiproducto', 'regalo')
  ),
  -- porcentaje: 0-100. precioFijo: precio especial en Lempiras (con ISV).
  valor numeric(12, 2) not null default 0,
  -- comboCantidad/regalo: producto sobre el que se cuenta la cantidad llevada.
  id_producto_base uuid references productos (id) on delete restrict,
  cantidad_requerida integer not null default 1,
  -- comboCantidad/comboMultiproducto: precio total del combo/paquete.
  precio_combo numeric(12, 2) not null default 0,
  -- regalo: cantidad regalada de CADA producto en rol='regalo'.
  cantidad_regalo integer not null default 1,
  fecha_inicio timestamptz not null,
  fecha_fin timestamptz,
  -- 'Todos' | 'Contado' | 'Credito' (pese al nombre histórico "alcancePago",
  -- filtra por CONDICIÓN — no se renombra para no romper promos ya creadas).
  alcance_pago text not null default 'Todos',
  -- Vacío = todos los métodos de pago; si no, uno o más de 'Efectivo' |
  -- 'Tarjeta' | 'Transferencia'. 'Mixto' nunca matchea una lista restringida.
  metodos_pago_alcance text[] not null default '{}',
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  creado_por text not null default ''
);
create index idx_promociones_activo on promociones (activo);
create index idx_promociones_vigencia on promociones (fecha_inicio, fecha_fin);
create index idx_promociones_id_producto_base on promociones (id_producto_base);
comment on table promociones is 'Reemplaza promociones (cabecera). Ver promocion_productos para las listas de productos que antes eran arrays paralelos idsProductos/nombresProductos, idsProductosCombo/nombresProductosCombo e idsProductosRegalo/nombresProductosRegalo.';

create table promocion_productos (
  id uuid primary key default gen_random_uuid(),
  id_promocion uuid not null references promociones (id) on delete cascade,
  id_producto uuid not null references productos (id) on delete cascade,
  -- 'individual': target de porcentaje/precioFijo (antes idsProductos).
  -- 'combo': miembro de comboMultiproducto (antes idsProductosCombo).
  -- 'regalo': producto regalado (antes idsProductosRegalo).
  rol text not null check (rol in ('individual', 'combo', 'regalo')),
  unique (id_promocion, id_producto, rol)
);
create index idx_promocion_productos_id_promocion on promocion_productos (id_promocion);
create index idx_promocion_productos_id_producto on promocion_productos (id_producto);
comment on table promocion_productos is 'Tabla puente promociones <-> productos (ver comentario en promociones).';

-- dispositivo_model.dart / dispositivo_repository.dart ('dispositivos'). El
-- id NO es un uuid autogenerado: es el id de dispositivo (hostname, ver
-- core/utils/device_id.dart) que la app misma decide y usa como doc.id.
create table dispositivos (
  id text primary key,
  plataforma text not null default '',
  version_app integer not null default 0,
  usuario text not null default '',
  ultima_conexion timestamptz
);
create index idx_dispositivos_ultima_conexion on dispositivos (ultima_conexion);
comment on table dispositivos is 'Reemplaza dispositivos. id = identificador de equipo (hostname), no un uuid generado por la base.';

-- cierre_caja_model.dart / cierre_caja_repository.dart ('cierresCaja')
create table cierres_caja (
  id uuid primary key default gen_random_uuid(),
  fecha_inicio timestamptz not null,
  fecha_fin timestamptz not null,
  monto_inicial numeric(12, 2) not null default 0,
  ingresos_efectivo numeric(12, 2) not null default 0,
  ingresos_tarjeta numeric(12, 2) not null default 0,
  ingresos_transferencia numeric(12, 2) not null default 0,
  egresos_efectivo numeric(12, 2) not null default 0,
  egresos_transferencia numeric(12, 2) not null default 0,
  total_calculado_efectivo numeric(12, 2) not null default 0,
  total_transferencia numeric(12, 2) not null default 0,
  gran_total numeric(12, 2) not null default 0,
  total_real numeric(12, 2) not null default 0,
  diferencia numeric(12, 2) not null default 0,
  usuario_responsable text not null default '',
  observaciones text not null default '',
  fecha_registro timestamptz not null default now()
);
create index idx_cierres_caja_fecha_fin on cierres_caja (fecha_fin);
comment on table cierres_caja is 'Reemplaza cierresCaja.';

-- 'cajaEstado/actual' (CierreCajaRepository.obtenerEstadoCaja/guardarMontoInicial):
-- desde cuándo corre el turno de caja actual y con cuánto arrancó -se
-- actualiza solo, con el totalReal del último cierre-. Fila única (singleton).
create table caja_estado (
  id smallint primary key default 1 check (id = 1),
  fecha_desde timestamptz not null default now(),
  monto_inicial numeric(12, 2) not null default 0,
  usuario_responsable text not null default '',
  actualizado_en timestamptz
);
comment on table caja_estado is 'Fila única (id=1) — reemplaza cajaEstado/actual.';

-- ============================================================================
-- APARTADOS (módulo NUEVO, todavía no existe en el código Dart — se
-- construye en una fase posterior; mismo patrón de venta_items/venta_credito
-- para mantener consistencia con el resto del esquema).
-- ============================================================================

create table apartados (
  id uuid primary key default gen_random_uuid(),
  id_cliente uuid references clientes (id) on delete restrict,
  monto_total numeric(12, 2) not null,
  monto_inicial numeric(12, 2) not null default 0,
  modalidad text not null check (modalidad in ('cuotas_fijas', 'abonos_libres')),
  estado text not null default 'activo' check (estado in ('activo', 'completado', 'cancelado')),
  fecha_creacion timestamptz not null default now(),
  fecha_entrega timestamptz
);
create index idx_apartados_id_cliente on apartados (id_cliente);
create index idx_apartados_estado on apartados (estado);
comment on table apartados is 'Cabecera de un apartado (lay-away). Ver apartado_items para las líneas, apartado_cuotas si modalidad=cuotas_fijas, apartado_abonos si modalidad=abonos_libres.';

-- Snapshot de línea (mismo patrón que venta_items: nombre/precio congelados
-- al momento de apartar, no un join en vivo contra productos).
create table apartado_items (
  id uuid primary key default gen_random_uuid(),
  id_apartado uuid not null references apartados (id) on delete cascade,
  id_producto uuid references productos (id) on delete restrict,
  nombre_producto text not null,
  cantidad numeric(14, 3) not null,
  precio_unitario numeric(12, 2) not null,
  subtotal numeric(12, 2) not null
);
create index idx_apartado_items_id_apartado on apartado_items (id_apartado);
create index idx_apartado_items_id_producto on apartado_items (id_producto);
comment on table apartado_items is 'Detalle de un apartado (solo aplica, igual que venta_items, como tabla hija normalizada).';

-- Solo se usa si apartados.modalidad = 'cuotas_fijas'.
create table apartado_cuotas (
  id uuid primary key default gen_random_uuid(),
  id_apartado uuid not null references apartados (id) on delete cascade,
  numero_cuota integer not null,
  monto_programado numeric(12, 2) not null,
  -- Fecha programada de la cuota: es una fecha límite de calendario, sin
  -- hora significativa (a diferencia de fecha_registro/fecha en el resto del
  -- esquema, que sí son instantes) — por eso 'date' y no 'timestamptz'.
  fecha_programada date not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'pagada', 'vencida')),
  unique (id_apartado, numero_cuota)
);
create index idx_apartado_cuotas_id_apartado on apartado_cuotas (id_apartado);
create index idx_apartado_cuotas_estado on apartado_cuotas (estado);
create index idx_apartado_cuotas_fecha_programada on apartado_cuotas (fecha_programada);
comment on table apartado_cuotas is 'Cuotas fijas de un apartado en modalidad cuotas_fijas.';

-- Solo se usa si apartados.modalidad = 'abonos_libres'. Mismo patrón que
-- venta_credito_abonos/compra_credito_abonos.
create table apartado_abonos (
  id uuid primary key default gen_random_uuid(),
  id_apartado uuid not null references apartados (id) on delete cascade,
  monto_abonado numeric(12, 2) not null,
  fecha timestamptz not null default now(),
  saldo_anterior numeric(12, 2) not null,
  saldo_pendiente numeric(12, 2) not null
);
create index idx_apartado_abonos_id_apartado on apartado_abonos (id_apartado);
create index idx_apartado_abonos_fecha on apartado_abonos (fecha);
comment on table apartado_abonos is 'Abonos libres de un apartado en modalidad abonos_libres.';

-- ============================================================================
-- RLS: el login es CUSTOM (usuarios propios, hash+sal, sin Supabase Auth) —
-- no existe auth.uid() ni sesión de Supabase real detrás de cada acción, así
-- que no hay forma de escribir políticas por usuario. Se activa RLS en TODAS
-- las tablas (buena práctica / requisito para exponerlas via API), pero con
-- una política abierta ("using (true) with check (true)") que deja pasar
-- cualquier operación autenticada con la anon key — es lo más parecido al
-- comportamiento actual: app de escritorio/celular de confianza, detrás de
-- su propio login, sin multi-tenancy real entre negocios distintos. Esto es
-- una decisión deliberada, no un descuido: si en el futuro se necesita
-- aislar datos por negocio/sucursal, acá es donde se agregarían políticas
-- reales basadas en algún claim propio (no en auth.uid()).
-- ============================================================================

do $$
declare
  t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public'
    and tablename in (
      'negocio_config', 'contadores', 'presencia',
      'categorias', 'clientes', 'proveedores', 'usuarios', 'productos',
      'producto_lotes_costo', 'producto_historial_precios_compra', 'producto_historial_stock',
      'producto_historial_ventas', 'pendientes_reposicion',
      'compras', 'compra_items', 'compras_en_espera', 'compras_credito', 'compra_credito_abonos',
      'ventas', 'venta_items', 'ventas_en_espera', 'ventas_credito', 'venta_credito_abonos',
      'egresos', 'promociones', 'promocion_productos', 'dispositivos',
      'cierres_caja', 'caja_estado',
      'apartados', 'apartado_items', 'apartado_cuotas', 'apartado_abonos'
    )
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I on public.%I for all using (true) with check (true);',
      t || '_allow_all_anon', t
    );
  end loop;
end $$;

-- ============================================================================
-- REALTIME: se habilita replication solo en las tablas que hoy se leen con
-- .snapshots() (Stream) en Firestore, según lo pedido -confirmado
-- repositorio por repositorio-:
--   - productos: ProductoRepository.obtenerProductos() -> Stream
--   - negocio: NegocioRepository.obtenerNegocio() -> Stream
--   - ventas: VentaRepository tiene 3 streams sobre la colección ventas
--     (obtenerVentasConSolicitudImpresionEnVivo, ...GuiaEnvio,
--     obtenerVentasPendientesImpresion) — todos sobre la fila de ventas, no
--     sobre venta_items.
--   - ventas_credito: VentaCreditoRepository.obtenerCreditos()/obtenerAbonos() -> Stream
--   - caja: CierreCajaRepository.obtenerHistorial() -> Stream (cierresCaja).
--     cajaEstado se lee con Future puntual (obtenerEstadoCaja), pero se
--     incluye igual por ser chica y consultarse justo antes de cada cierre.
--   - dispositivos: DispositivoRepository.obtenerDispositivos() -> Stream
--   - apartados: módulo nuevo, se habilita desde ya para que la fase
--     Dart pueda usar Stream igual que el resto de pantallas "en vivo".
-- (categorias/clientes/proveedores/promociones también usan Stream hoy,
-- pero quedan fuera de la lista pedida explícitamente — se pueden agregar
-- después con el mismo alter publication si hace falta.)
-- ============================================================================

alter publication supabase_realtime add table
  productos,
  negocio_config,
  ventas,
  ventas_credito,
  venta_credito_abonos,
  cierres_caja,
  caja_estado,
  dispositivos,
  apartados,
  apartado_items,
  apartado_cuotas,
  apartado_abonos;

-- ============================================================================
-- Ck S de R.L. de C.V. — funciones Postgres para operaciones ATÓMICAS que en
-- Firestore corrían dentro de una Transaction (contadores, costeo FIFO,
-- registrar/anular venta y compra, reservas de stock de "en espera", abonos
-- de crédito con cadena dependiente, cierre de caja). Ver el comentario de
-- cada función para el porqué. Aplicado con tool/supabase_sql.dart y luego
-- documentado (append) en supabase/schema.sql.
-- ============================================================================

-- Falta en el esquema original: los reportes necesitan poder ordenar por el
-- momento REAL de creación (creadoEn en Firestore), distinto de
-- fecha_registro (fecha de negocio, que el cajero puede atrasar a mano).
alter table ventas add column if not exists creado_en timestamptz not null default now();

-- Falta en el esquema original: en Firestore cada línea de detalle llevaba
-- un campo 'orden' (id autogenerado no garantiza el orden de lectura) — acá
-- las filas tampoco vienen garantizadas en orden de inserción sin un ORDER
-- BY explícito, así que hace falta la misma columna.
alter table venta_items add column if not exists orden integer;
alter table compra_items add column if not exists orden integer;

-- ----------------------------------------------------------------------------
-- incrementar_contador: reemplaza el patrón lectura+escritura de
-- VentaRepository._claveContador/CompraRepository -dos cajeros no pueden
-- sacar el mismo número-. Un solo UPDATE/INSERT atómico.
-- ----------------------------------------------------------------------------
create or replace function incrementar_contador(p_clave text) returns integer
language plpgsql as $$
declare
  v_nuevo integer;
begin
  insert into contadores (clave, ultimo) values (p_clave, 1)
  on conflict (clave) do update set ultimo = contadores.ultimo + 1
  returning ultimo into v_nuevo;
  return v_nuevo;
end;
$$;

create or replace function formatear_cantidad(p_cantidad numeric) returns text
language sql immutable as $$
  select case when p_cantidad = round(p_cantidad, 0)
    then round(p_cantidad, 0)::bigint::text
    else round(p_cantidad, 2)::text
  end;
$$;

-- ----------------------------------------------------------------------------
-- consumir_fifo_lotes: consume [p_cantidad] de los lotes de un producto (el
-- más viejo primero, o por prioridad manual — ver reordenar_lotes), bloqueando
-- las filas tocadas (FOR UPDATE) para que dos ventas concurrentes del mismo
-- producto no consuman el mismo lote dos veces. Devuelve el costo unitario
-- promedio ponderado de lo consumido (usa p_costo_fallback para lo que no
-- alcance a cubrir ningún lote).
-- ----------------------------------------------------------------------------
create or replace function consumir_fifo_lotes(p_id_producto uuid, p_cantidad numeric, p_costo_fallback numeric)
returns numeric
language plpgsql as $$
declare
  v_restante numeric := p_cantidad;
  v_costo_total numeric := 0;
  v_consumido numeric;
  lote record;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    return p_costo_fallback;
  end if;
  for lote in
    select id, cantidad_restante, costo_unitario
    from producto_lotes_costo
    where id_producto = p_id_producto and cantidad_restante > 0
    order by (prioridad is null), prioridad, fecha
    for update
  loop
    exit when v_restante <= 0;
    v_consumido := least(lote.cantidad_restante, v_restante);
    update producto_lotes_costo set cantidad_restante = cantidad_restante - v_consumido where id = lote.id;
    v_costo_total := v_costo_total + v_consumido * lote.costo_unitario;
    v_restante := v_restante - v_consumido;
  end loop;
  if v_restante > 0 then
    v_costo_total := v_costo_total + v_restante * coalesce(p_costo_fallback, 0);
  end if;
  return v_costo_total / p_cantidad;
end;
$$;

-- ----------------------------------------------------------------------------
-- sincronizar_precio_compra_activo: productos.precio_compra refleja el lote
-- que el FIFO va a consumir A CONTINUACIÓN (ver comentario grande en
-- lote_costo_repository.dart original). Se llama luego de cualquier
-- operación que toque lotes.
-- ----------------------------------------------------------------------------
create or replace function sincronizar_precio_compra_activo(p_id_producto uuid) returns void
language plpgsql as $$
declare
  v_costo numeric;
begin
  select costo_unitario into v_costo
  from producto_lotes_costo
  where id_producto = p_id_producto and cantidad_restante > 0
  order by (prioridad is null), prioridad, fecha
  limit 1;
  if v_costo is not null then
    update productos set precio_compra = v_costo where id = p_id_producto;
  end if;
end;
$$;

create or replace function reordenar_lotes(p_id_producto uuid, p_ids_orden uuid[]) returns void
language plpgsql as $$
declare
  v_id uuid;
  v_idx integer := 0;
begin
  foreach v_id in array p_ids_orden loop
    update producto_lotes_costo set prioridad = v_idx where id = v_id and id_producto = p_id_producto;
    v_idx := v_idx + 1;
  end loop;
  perform sincronizar_precio_compra_activo(p_id_producto);
end;
$$;

-- ----------------------------------------------------------------------------
-- calcular_cantidades_descuento: dado un array de ítems (ItemVentaModel.toMap
-- en camelCase, con 'componentes' si es combo), expande cada combo en sus
-- componentes (mismo criterio que VentaRepository._expandirComponentes) y
-- agrupa la cantidad total a descontar por idProducto, excluyendo líneas
-- reembasadas o de categorías que no controlan stock (consultado en vivo
-- contra `categorias`, no confiado a un set que mande el cliente). Reusado
-- por registrar_venta (costeo + stock) y por guardar_venta_en_espera_manual
-- (reserva de stock, sin costeo).
-- ----------------------------------------------------------------------------
create or replace function calcular_cantidades_descuento(p_items jsonb) returns jsonb
language plpgsql as $$
declare
  v_result jsonb := '{}'::jsonb;
  item jsonb;
  comp jsonb;
  v_id_producto text;
  v_id_categoria uuid;
  v_cantidad numeric;
  v_controla boolean;
begin
  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if (item->'componentes' is null or jsonb_array_length(item->'componentes') = 0) then
      if coalesce((item->>'reembasado')::boolean, false) = false then
        v_id_producto := nullif(item->>'idProducto', '');
        if v_id_producto is not null then
          v_id_categoria := nullif(item->>'idCategoria', '')::uuid;
          select controla_stock into v_controla from categorias where id = v_id_categoria;
          if coalesce(v_controla, true) then
            v_cantidad := (item->>'cantidad')::numeric;
            v_result := jsonb_set(v_result, array[v_id_producto], to_jsonb(coalesce((v_result->>v_id_producto)::numeric, 0) + v_cantidad));
          end if;
        end if;
      end if;
    else
      for comp in select * from jsonb_array_elements(item->'componentes') loop
        v_id_producto := nullif(comp->>'idProducto', '');
        if v_id_producto is not null then
          v_id_categoria := nullif(comp->>'idCategoria', '')::uuid;
          select controla_stock into v_controla from categorias where id = v_id_categoria;
          if coalesce(v_controla, true) then
            v_cantidad := (comp->>'cantidad')::numeric * (item->>'cantidad')::numeric;
            v_result := jsonb_set(v_result, array[v_id_producto], to_jsonb(coalesce((v_result->>v_id_producto)::numeric, 0) + v_cantidad));
          end if;
        end if;
      end loop;
    end if;
  end loop;
  return v_result;
end;
$$;

-- ----------------------------------------------------------------------------
-- registrar_venta: equivalente a VentaRepository.registrarVenta (la
-- transacción completa de Firestore). Ver comentario de cada bloque.
-- payload (jsonb, claves camelCase como en ItemVentaModel/VentaModel):
--   tipoDocumento, condicion, metodoPago, documentoCliente, nombreCliente,
--   idCliente, nombreClienteNormalizado (precalculado en Dart con
--   normalizarNombreCliente), fechaRegistro, fechaVencimiento,
--   telefonoCredito, oc, regExonerado, regSag, observaciones,
--   descuentoGlobal, montoPago, montoCambio, pagosMixtos, subtotal,
--   impuesto, totalAPagar, usuario, esEnvio, envioNombre, envioDireccion,
--   envioTelefono, items: [ItemVentaModel.toMap() + 'orden' implícito].
-- Devuelve {id, numeroDocumento, creadoEn, detalleCostos:[...]} — Dart hace
-- items[i].copyWith(precioCompraUsado: detalleCostos[i]) para reconstruir el
-- VentaModel final.
-- ----------------------------------------------------------------------------
create or replace function registrar_venta(payload jsonb) returns jsonb
language plpgsql as $$
declare
  v_tipo_documento text := payload->>'tipoDocumento';
  v_condicion text := payload->>'condicion';
  v_clave_contador text;
  v_numero integer;
  v_numero_documento text;
  v_id_venta uuid := gen_random_uuid();
  v_id_cliente uuid;
  v_nombre_cliente text := coalesce(payload->>'nombreCliente', '');
  v_documento_cliente text := coalesce(payload->>'documentoCliente', '');
  v_fecha_registro timestamptz := (payload->>'fechaRegistro')::timestamptz;
  v_fecha_vencimiento timestamptz := nullif(payload->>'fechaVencimiento', '')::timestamptz;
  v_creado_en timestamptz := now();
  v_cantidad_productos numeric := 0;
  v_cantidades jsonb;
  v_costo_por_producto jsonb := '{}'::jsonb;
  v_id_producto_txt text;
  v_cantidad numeric;
  v_stock_actual numeric;
  v_precio_compra numeric;
  v_costo numeric;
  v_stock_nuevo numeric;
  item jsonb;
  v_idx integer;
  v_item_ref uuid;
  v_id_categoria uuid;
  v_controla boolean;
  v_es_combo boolean;
  v_costo_item numeric;
  v_detalle_costos jsonb := '[]'::jsonb;
  v_aplica_isv boolean;
  v_precio_con_isv numeric;
begin
  v_clave_contador := case v_tipo_documento
    when 'Cotizacion' then 'cotizacion'
    when 'VentaSinFacturar' then 'ventaSinFacturar'
    else 'venta'
  end;
  v_numero := incrementar_contador(v_clave_contador);
  v_numero_documento := case when v_tipo_documento = 'VentaSinFacturar'
    then lpad(v_numero::text, 4, '0')
    else lpad(v_numero::text, 8, '0')
  end;

  -- Resolver/crear cliente (igual que VentaRepository._resolverIdCliente).
  v_id_cliente := nullif(payload->>'idCliente', '')::uuid;
  if v_tipo_documento <> 'Cotizacion' and v_id_cliente is null then
    if trim(v_nombre_cliente) <> '' and upper(trim(v_nombre_cliente)) <> 'CONSUMIDOR FINAL' then
      select id into v_id_cliente from clientes where nombre_normalizado = payload->>'nombreClienteNormalizado' limit 1;
      if v_id_cliente is null then
        insert into clientes (dni, nombre_completo, nombre_normalizado, direccion, telefono, estado)
        values (
          case when trim(v_documento_cliente) = '' or trim(v_documento_cliente) = 'N/A' then '' else trim(v_documento_cliente) end,
          trim(v_nombre_cliente), payload->>'nombreClienteNormalizado', '', '', true
        ) returning id into v_id_cliente;
      end if;
    end if;
  end if;

  select coalesce(sum((i->>'cantidad')::numeric), 0) into v_cantidad_productos from jsonb_array_elements(payload->'items') i;

  insert into ventas (
    id, tipo_documento, numero_documento, documento_cliente, nombre_cliente, id_cliente,
    metodo_pago, monto_pago, monto_cambio, subtotal, impuesto, total_a_pagar, condicion,
    fecha_vencimiento, fecha_registro, creado_en, estado, usuario_registro, cantidad_productos,
    oc, reg_exonerado, reg_sag, observaciones, descuento_global, pagos_mixtos,
    pendiente_impresion, es_envio, envio_nombre, envio_direccion, envio_telefono
  ) values (
    v_id_venta, v_tipo_documento, v_numero_documento, v_documento_cliente, v_nombre_cliente, v_id_cliente,
    payload->>'metodoPago', (payload->>'montoPago')::numeric, (payload->>'montoCambio')::numeric,
    (payload->>'subtotal')::numeric, (payload->>'impuesto')::numeric, (payload->>'totalAPagar')::numeric,
    v_condicion, v_fecha_vencimiento, v_fecha_registro, v_creado_en, 'Activa', coalesce(payload->>'usuario', ''),
    v_cantidad_productos, coalesce(payload->>'oc', ''), coalesce(payload->>'regExonerado', ''),
    coalesce(payload->>'regSag', ''), coalesce(payload->>'observaciones', ''),
    coalesce((payload->>'descuentoGlobal')::numeric, 0), coalesce(payload->'pagosMixtos', '[]'::jsonb),
    false, coalesce((payload->>'esEnvio')::boolean, false), coalesce(payload->>'envioNombre', ''),
    coalesce(payload->>'envioDireccion', ''), coalesce(payload->>'envioTelefono', '')
  );

  if v_condicion = 'Credito' then
    insert into ventas_credito (
      id, documento_cliente, nombre_cliente, id_cliente, numero_documento, monto_total,
      saldo_pendiente, fecha_registro, fecha_vencimiento, telefono
    ) values (
      v_id_venta, case when v_documento_cliente = '' then 'N/A' else v_documento_cliente end, v_nombre_cliente,
      v_id_cliente, v_numero_documento, (payload->>'totalAPagar')::numeric, (payload->>'totalAPagar')::numeric,
      v_fecha_registro, coalesce(v_fecha_vencimiento, v_fecha_registro), coalesce(trim(payload->>'telefonoCredito'), '')
    );
  end if;

  if v_id_cliente is not null and v_tipo_documento <> 'Cotizacion' then
    update clientes set fecha_ultima_compra = v_fecha_registro where id = v_id_cliente;
  end if;

  -- Costeo FIFO + descuento de stock, agrupado por producto único (evita el
  -- bug de "dos líneas del mismo producto" que documenta el código Dart
  -- original: acá no puede pasar porque se agrupa ANTES de tocar nada).
  v_cantidades := calcular_cantidades_descuento(payload->'items');
  for v_id_producto_txt in select jsonb_object_keys(v_cantidades) loop
    v_cantidad := (v_cantidades->>v_id_producto_txt)::numeric;
    select stock, precio_compra into v_stock_actual, v_precio_compra from productos where id = v_id_producto_txt::uuid for update;
    v_costo := consumir_fifo_lotes(v_id_producto_txt::uuid, v_cantidad, coalesce(v_precio_compra, 0));
    v_costo_por_producto := jsonb_set(v_costo_por_producto, array[v_id_producto_txt], to_jsonb(v_costo));
    v_stock_nuevo := greatest(coalesce(v_stock_actual, 0) - v_cantidad, 0);
    update productos set stock = v_stock_nuevo where id = v_id_producto_txt::uuid;
    insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
    values (v_id_producto_txt::uuid, coalesce(v_stock_actual, 0), v_stock_nuevo, coalesce(payload->>'usuario', ''), 'Venta ' || v_numero_documento, now());
  end loop;

  -- Detalle (venta_items), historial de ventas por producto, y pendientes de
  -- reposición (venta anticipada) — en el mismo orden del carrito.
  v_idx := 0;
  v_aplica_isv := v_tipo_documento in ('Factura', 'Boleta');
  for item in select * from jsonb_array_elements(payload->'items') loop
    v_id_categoria := nullif(item->>'idCategoria', '')::uuid;
    v_es_combo := (item->'componentes' is not null and jsonb_array_length(item->'componentes') > 0);
    v_costo_item := (item->>'precioCompraUsado')::numeric;
    if not v_es_combo and coalesce((item->>'reembasado')::boolean, false) = false then
      select controla_stock into v_controla from categorias where id = v_id_categoria;
      if coalesce(v_controla, true) and v_costo_por_producto ? (item->>'idProducto') then
        v_costo_item := (v_costo_por_producto->>(item->>'idProducto'))::numeric;
      end if;
    end if;
    v_detalle_costos := v_detalle_costos || to_jsonb(v_costo_item);

    insert into venta_items (
      id_venta, id_producto, id_categoria, nombre_producto, precio_venta, cantidad, subtotal,
      precio_compra_usado, reembasado, descuento_porcentaje, componentes, pendiente_compra, codigos_color, orden
    ) values (
      v_id_venta, nullif(item->>'idProducto', '')::uuid, v_id_categoria, item->>'nombreProducto',
      (item->>'precioVenta')::numeric, (item->>'cantidad')::numeric, (item->>'subtotal')::numeric,
      v_costo_item, coalesce((item->>'reembasado')::boolean, false), coalesce((item->>'descuentoPorcentaje')::numeric, 0),
      coalesce(item->'componentes', '[]'::jsonb), coalesce((item->>'pendienteCompra')::boolean, false),
      coalesce(array(select jsonb_array_elements_text(coalesce(item->'codigosColor', '[]'::jsonb))), '{}'), v_idx
    ) returning id into v_item_ref;

    if v_tipo_documento <> 'Cotizacion' and coalesce((item->>'pendienteCompra')::boolean, false) and not v_es_combo then
      insert into pendientes_reposicion (
        id_venta, numero_documento_venta, id_item_detalle, id_producto, nombre_producto, id_categoria,
        cantidad_original, cantidad_pendiente, costo_registrado, fecha_registro, estado, usuario
      ) values (
        v_id_venta, v_numero_documento, v_item_ref, nullif(item->>'idProducto', '')::uuid, item->>'nombreProducto',
        v_id_categoria, (item->>'cantidad')::numeric, (item->>'cantidad')::numeric, v_costo_item,
        v_fecha_registro, 'Pendiente', coalesce(payload->>'usuario', '')
      );
    end if;

    if v_tipo_documento <> 'Cotizacion' then
      v_precio_con_isv := round((item->>'precioVenta')::numeric * (1 - coalesce((item->>'descuentoPorcentaje')::numeric, 0) / 100) * (case when v_aplica_isv then 1.15 else 1 end), 2);
      insert into producto_historial_ventas (
        id_producto, id_venta, precio_venta, precio_unitario, descuento_porcentaje, cantidad,
        fecha, tipo_documento, numero_documento, cliente, usuario
      ) values (
        nullif(item->>'idProducto', '')::uuid, v_id_venta, v_precio_con_isv, (item->>'precioVenta')::numeric,
        coalesce((item->>'descuentoPorcentaje')::numeric, 0), (item->>'cantidad')::numeric, now(),
        v_tipo_documento, v_numero_documento, v_nombre_cliente, coalesce(payload->>'usuario', '')
      );
    end if;
    v_idx := v_idx + 1;
  end loop;

  for v_id_producto_txt in select jsonb_object_keys(v_cantidades) loop
    perform sincronizar_precio_compra_activo(v_id_producto_txt::uuid);
  end loop;

  return jsonb_build_object('id', v_id_venta, 'numeroDocumento', v_numero_documento, 'creadoEn', v_creado_en, 'idCliente', v_id_cliente, 'detalleCostos', v_detalle_costos);
end;
$$;

-- ----------------------------------------------------------------------------
-- anular_venta: repone stock (agrupado por producto único), crea un lote de
-- ajuste al costo promedio ponderado repuesto, cancela pendientes de
-- reposición abiertas de esta venta, y borra el crédito asociado si no tiene
-- abonos (si tiene, rechaza igual que la versión Dart).
-- ----------------------------------------------------------------------------
create or replace function anular_venta(p_id uuid, p_usuario text, p_motivo text default '') returns void
language plpgsql as $$
declare
  v_estado text;
  v_condicion text;
  v_numero_documento text;
  v_credito_existe boolean := false;
  v_monto_total numeric;
  v_saldo_pendiente numeric;
  item record;
  v_id_categoria uuid;
  v_es_combo boolean;
  v_controla boolean;
  v_cantidad numeric;
  v_totales jsonb := '{}'::jsonb; -- idProducto -> {cantidad, costoTotal}
  v_id_producto_txt text;
  v_cantidad_total numeric;
  v_costo_total numeric;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
  v_costo_promedio numeric;
begin
  select estado, condicion, numero_documento into v_estado, v_condicion, v_numero_documento from ventas where id = p_id for update;
  if not found then
    raise exception 'No se encontró la venta';
  end if;
  if v_estado = 'Anulada' then
    raise exception 'Esta venta ya está anulada';
  end if;

  if v_condicion = 'Credito' then
    select monto_total, saldo_pendiente into v_monto_total, v_saldo_pendiente from ventas_credito where id = p_id;
    if found then
      v_credito_existe := true;
      if v_saldo_pendiente < v_monto_total then
        raise exception 'No se puede anular: esta venta a crédito ya tiene abonos registrados';
      end if;
    end if;
  end if;

  update ventas set estado = 'Anulada', usuario_anulacion = p_usuario, motivo_anulacion = coalesce(p_motivo, ''), fecha_anulacion = now() where id = p_id;
  if v_credito_existe then
    delete from ventas_credito where id = p_id;
  end if;
  update pendientes_reposicion set estado = 'Cancelado', fecha_completado = now() where id_venta = p_id and estado = 'Pendiente';

  -- Expandir combos (igual que _expandirComponentes) y agrupar por producto.
  -- OJO: en una línea combo, vi.id_producto es el producto DEL COMBO (nunca
  -- null), así que acá NO se puede usar coalesce(vi.id_producto, ...) -hay
  -- que decidir con CASE cuál id_producto/id_categoria/cantidad corresponde
  -- según si esta línea es combo o no.
  for item in
    select
      case when jsonb_array_length(coalesce(vi.componentes, '[]'::jsonb)) = 0 then vi.id_producto else nullif(comp->>'idProducto', '')::uuid end as id_producto,
      case when jsonb_array_length(coalesce(vi.componentes, '[]'::jsonb)) = 0 then vi.id_categoria else nullif(comp->>'idCategoria', '')::uuid end as id_categoria,
      case when jsonb_array_length(coalesce(vi.componentes, '[]'::jsonb)) = 0 then vi.cantidad else (comp->>'cantidad')::numeric * vi.cantidad end as cantidad,
      vi.reembasado,
      case when jsonb_array_length(coalesce(vi.componentes, '[]'::jsonb)) = 0 then vi.precio_compra_usado else (comp->>'precioCompraUsado')::numeric end as costo_unitario
    from venta_items vi
    left join lateral jsonb_array_elements(case when jsonb_array_length(coalesce(vi.componentes, '[]'::jsonb)) = 0 then '[null]'::jsonb else vi.componentes end) comp on true
    where vi.id_venta = p_id
  loop
    if item.reembasado then continue; end if;
    select controla_stock into v_controla from categorias where id = item.id_categoria;
    if not coalesce(v_controla, true) then continue; end if;
    v_id_producto_txt := item.id_producto::text;
    v_cantidad_total := coalesce((v_totales->v_id_producto_txt->>'cantidad')::numeric, 0) + item.cantidad;
    v_costo_total := coalesce((v_totales->v_id_producto_txt->>'costoTotal')::numeric, 0) + item.cantidad * coalesce(item.costo_unitario, 0);
    v_totales := jsonb_set(v_totales, array[v_id_producto_txt], jsonb_build_object('cantidad', v_cantidad_total, 'costoTotal', v_costo_total));
  end loop;

  for v_id_producto_txt in select jsonb_object_keys(v_totales) loop
    v_cantidad_total := (v_totales->v_id_producto_txt->>'cantidad')::numeric;
    v_costo_total := (v_totales->v_id_producto_txt->>'costoTotal')::numeric;
    v_costo_promedio := case when v_cantidad_total > 0 then v_costo_total / v_cantidad_total else 0 end;
    select stock into v_stock_actual from productos where id = v_id_producto_txt::uuid for update;
    v_stock_nuevo := coalesce(v_stock_actual, 0) + v_cantidad_total;
    update productos set stock = v_stock_nuevo where id = v_id_producto_txt::uuid;
    insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
    values (v_id_producto_txt::uuid, coalesce(v_stock_actual, 0), v_stock_nuevo, p_usuario, 'Anulación de venta ' || v_numero_documento, now());
    insert into producto_lotes_costo (id_producto, cantidad_original, cantidad_restante, costo_unitario, fecha, origen)
    values (v_id_producto_txt::uuid, v_cantidad_total, v_cantidad_total, v_costo_promedio, now(), 'ajuste');
    perform sincronizar_precio_compra_activo(v_id_producto_txt::uuid);
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- aplicar_pendiente_reposicion: reparte cantidad disponible de una línea de
-- compra contra UNA venta pendiente de reposición puntual (bloqueando la
-- fila). Devuelve cuánto se aplicó y el numeroDocumento de la venta cubierta
-- (para el mensaje de historial), o (0, null) si no aplica.
-- ----------------------------------------------------------------------------
create or replace function aplicar_pendiente_reposicion(
  p_id_pendiente uuid, p_disponible numeric, p_costo_unitario numeric,
  out p_aplicado numeric, out p_numero_documento_venta text
) language plpgsql as $$
declare
  v_cant_pendiente numeric;
  v_cant_original numeric;
  v_costo_registrado numeric;
  v_id_venta uuid;
  v_id_item_detalle uuid;
  v_numero_doc text;
  v_nueva_pendiente numeric;
  v_cubierta numeric;
  v_base numeric;
  v_costo_ponderado numeric;
begin
  p_aplicado := 0;
  p_numero_documento_venta := null;
  select cantidad_pendiente, cantidad_original, costo_registrado, id_venta, id_item_detalle, numero_documento_venta
    into v_cant_pendiente, v_cant_original, v_costo_registrado, v_id_venta, v_id_item_detalle, v_numero_doc
    from pendientes_reposicion where id = p_id_pendiente and estado = 'Pendiente'
    for update;
  if not found or v_cant_pendiente <= 0 or p_disponible <= 0 then
    return;
  end if;
  p_aplicado := least(p_disponible, v_cant_pendiente);
  v_nueva_pendiente := round(v_cant_pendiente - p_aplicado, 3);
  v_cubierta := v_cant_original - v_cant_pendiente;
  v_base := v_cubierta + p_aplicado;
  v_costo_ponderado := case when v_base <= 0 then p_costo_unitario else ((v_costo_registrado * v_cubierta) + (p_costo_unitario * p_aplicado)) / v_base end;
  update pendientes_reposicion set
    cantidad_pendiente = v_nueva_pendiente,
    costo_registrado = v_costo_ponderado,
    estado = case when v_nueva_pendiente <= 0 then 'Completado' else estado end,
    fecha_completado = case when v_nueva_pendiente <= 0 then now() else fecha_completado end
  where id = p_id_pendiente;
  if v_id_venta is not null and v_id_item_detalle is not null then
    update venta_items set precio_compra_usado = v_costo_ponderado where id = v_id_item_detalle;
  end if;
  p_numero_documento_venta := v_numero_doc;
end;
$$;

-- ----------------------------------------------------------------------------
-- registrar_compra: equivalente a CompraRepository.registrarCompra. payload:
--   noFactura, idProveedor, documentoProveedor, razonSocial, condicion,
--   metodoPago, fechaRegistro, fechaVencimiento, descuentoGlobalPorcentaje,
--   descuentoTotalMonto, isvPorcentaje, ajusteManual, subtotal, impuesto,
--   totalAPagar, usuario, items: [ItemCompraModel.toMap()].
-- Devuelve {id, numeroDocumento}.
-- ----------------------------------------------------------------------------
create or replace function registrar_compra(payload jsonb) returns jsonb
language plpgsql as $$
declare
  v_numero integer;
  v_numero_documento text;
  v_id_compra uuid := gen_random_uuid();
  v_condicion text := payload->>'condicion';
  v_fecha_registro timestamptz := (payload->>'fechaRegistro')::timestamptz;
  v_fecha_vencimiento timestamptz := nullif(payload->>'fechaVencimiento', '')::timestamptz;
  v_isv_porcentaje numeric := coalesce((payload->>'isvPorcentaje')::numeric, 15);
  v_cantidad_productos numeric := 0;
  item jsonb;
  v_id_producto uuid;
  v_id_categoria uuid;
  v_precio_final numeric;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
  v_disponible numeric;
  v_numeros_cubiertos text[] := '{}';
  v_id_vinculado uuid;
  pend record;
  v_resultado record;
  v_cantidad_aplicada numeric;
  v_motivo text;
  v_precio_venta_nuevo numeric;
  v_idx integer := 0;
begin
  v_numero := incrementar_contador('compra');
  v_numero_documento := lpad(v_numero::text, 8, '0');

  select coalesce(sum((i->>'cantidad')::numeric), 0) into v_cantidad_productos from jsonb_array_elements(payload->'items') i;

  insert into compras (
    id, tipo_documento, numero_documento, no_factura, id_proveedor, documento_proveedor, razon_social,
    condicion, metodo_pago, subtotal, descuento_global_porcentaje, descuento_total_monto, isv_porcentaje,
    impuesto, ajuste_manual, total_a_pagar, fecha_registro, fecha_vencimiento, estado, usuario_registro,
    cantidad_productos
  ) values (
    v_id_compra, 'Factura', v_numero_documento, coalesce(payload->>'noFactura', ''), nullif(payload->>'idProveedor', '')::uuid,
    coalesce(payload->>'documentoProveedor', ''), coalesce(payload->>'razonSocial', ''), v_condicion,
    coalesce(payload->>'metodoPago', ''), (payload->>'subtotal')::numeric, coalesce((payload->>'descuentoGlobalPorcentaje')::numeric, 0),
    coalesce((payload->>'descuentoTotalMonto')::numeric, 0), v_isv_porcentaje, (payload->>'impuesto')::numeric,
    coalesce((payload->>'ajusteManual')::numeric, 0), (payload->>'totalAPagar')::numeric, v_fecha_registro,
    v_fecha_vencimiento, 'Activa', coalesce(payload->>'usuario', ''), v_cantidad_productos
  );

  if v_condicion = 'Credito' then
    insert into compras_credito (
      id, id_proveedor, documento_proveedor, nombre_proveedor, numero_documento, no_factura, monto_total,
      saldo_pendiente, fecha_registro, fecha_vencimiento, manual
    ) values (
      v_id_compra, nullif(payload->>'idProveedor', '')::uuid,
      case when coalesce(payload->>'documentoProveedor', '') = '' then 'N/A' else payload->>'documentoProveedor' end,
      coalesce(payload->>'razonSocial', ''), v_numero_documento, coalesce(payload->>'noFactura', ''),
      (payload->>'totalAPagar')::numeric, (payload->>'totalAPagar')::numeric, v_fecha_registro,
      coalesce(v_fecha_vencimiento, v_fecha_registro), false
    );
  end if;

  for item in select * from jsonb_array_elements(payload->'items') loop
    v_id_producto := nullif(item->>'idProducto', '')::uuid;
    v_id_categoria := nullif(item->>'idCategoria', '')::uuid;
    v_precio_venta_nuevo := nullif(item->>'precioVentaNuevo', '')::numeric;
    v_id_vinculado := nullif(item->>'idPendienteReposicionVinculado', '')::uuid;

    insert into compra_items (
      id_compra, id_producto, id_categoria, nombre_producto, precio_compra, cantidad, subtotal,
      descuento_porcentaje, precio_venta_nuevo, id_pendiente_reposicion_vinculado,
      numero_documento_venta_vinculada, nombre_producto_venta_vinculada, orden
    ) values (
      v_id_compra, v_id_producto, v_id_categoria, item->>'nombreProducto', (item->>'precioCompra')::numeric,
      (item->>'cantidad')::numeric, (item->>'subtotal')::numeric, coalesce((item->>'descuentoPorcentaje')::numeric, 0),
      v_precio_venta_nuevo, v_id_vinculado, item->>'numeroDocumentoVentaVinculada', item->>'nombreProductoVentaVinculada', v_idx
    );
    v_idx := v_idx + 1;

    v_precio_final := round((item->>'precioCompra')::numeric * (1 - coalesce((item->>'descuentoPorcentaje')::numeric, 0) / 100) * (1 + v_isv_porcentaje / 100), 2);

    select stock into v_stock_actual from productos where id = v_id_producto for update;
    v_disponible := (item->>'cantidad')::numeric;
    v_numeros_cubiertos := '{}';

    if v_id_vinculado is not null then
      select * into v_resultado from aplicar_pendiente_reposicion(v_id_vinculado, v_disponible, v_precio_final);
      v_disponible := v_disponible - v_resultado.p_aplicado;
      if v_resultado.p_aplicado > 0 and v_resultado.p_numero_documento_venta is not null and not (v_resultado.p_numero_documento_venta = any(v_numeros_cubiertos)) then
        v_numeros_cubiertos := array_append(v_numeros_cubiertos, v_resultado.p_numero_documento_venta);
      end if;
    else
      for pend in select id from pendientes_reposicion where id_producto = v_id_producto and estado = 'Pendiente' order by fecha_registro for update loop
        exit when v_disponible <= 0;
        select * into v_resultado from aplicar_pendiente_reposicion(pend.id, v_disponible, v_precio_final);
        v_disponible := v_disponible - v_resultado.p_aplicado;
        if v_resultado.p_aplicado > 0 and v_resultado.p_numero_documento_venta is not null and not (v_resultado.p_numero_documento_venta = any(v_numeros_cubiertos)) then
          v_numeros_cubiertos := array_append(v_numeros_cubiertos, v_resultado.p_numero_documento_venta);
        end if;
      end loop;
    end if;

    v_cantidad_aplicada := round((item->>'cantidad')::numeric - v_disponible, 3);
    v_stock_nuevo := coalesce(v_stock_actual, 0) + (item->>'cantidad')::numeric - v_cantidad_aplicada;
    update productos set
      stock = v_stock_nuevo,
      precio_compra = v_precio_final,
      precio_venta = coalesce(v_precio_venta_nuevo, precio_venta)
    where id = v_id_producto;
    v_stock_actual := v_stock_nuevo; -- arrastre para la próxima línea del mismo producto en esta compra

    v_motivo := case when v_cantidad_aplicada > 0
      then 'Compra ' || v_numero_documento || ' (' || formatear_cantidad(v_cantidad_aplicada) || ' ya vendida por adelantado en factura(s) ' || array_to_string(v_numeros_cubiertos, ', ') || ')'
      else 'Compra ' || v_numero_documento
    end;
    insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
    values (v_id_producto, coalesce(v_stock_actual, 0) - ((item->>'cantidad')::numeric - v_cantidad_aplicada), v_stock_nuevo, coalesce(payload->>'usuario', ''), v_motivo, now());

    insert into producto_historial_precios_compra (
      id_producto, id_compra, precio_compra, precio_unitario, descuento_porcentaje, isv_porcentaje,
      cantidad, fecha, numero_documento, no_factura, proveedor, usuario
    ) values (
      v_id_producto, v_id_compra, v_precio_final, (item->>'precioCompra')::numeric, coalesce((item->>'descuentoPorcentaje')::numeric, 0),
      v_isv_porcentaje, (item->>'cantidad')::numeric, now(), v_numero_documento, coalesce(payload->>'noFactura', ''),
      coalesce(payload->>'razonSocial', ''), coalesce(payload->>'usuario', '')
    );

    insert into producto_lotes_costo (id_producto, cantidad_original, cantidad_restante, costo_unitario, fecha, origen, id_compra)
    values (v_id_producto, (item->>'cantidad')::numeric, (item->>'cantidad')::numeric - v_cantidad_aplicada, v_precio_final, v_fecha_registro, 'compra', v_id_compra);

    perform sincronizar_precio_compra_activo(v_id_producto);
  end loop;

  return jsonb_build_object('id', v_id_compra, 'numeroDocumento', v_numero_documento);
end;
$$;

-- ----------------------------------------------------------------------------
-- anular_compra: descuenta el stock que había sumado, recorta el lote que
-- generó (sin "des-vender" lo ya consumido de él), y borra el crédito
-- asociado si no tiene abonos.
-- ----------------------------------------------------------------------------
create or replace function anular_compra(p_id uuid, p_usuario text, p_motivo text default '') returns void
language plpgsql as $$
declare
  v_estado text;
  v_condicion text;
  v_numero_documento text;
  v_credito_existe boolean := false;
  v_monto_total numeric;
  v_saldo_pendiente numeric;
  item record;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
  v_lote_id uuid;
  v_restante_actual numeric;
begin
  select estado, condicion, numero_documento into v_estado, v_condicion, v_numero_documento from compras where id = p_id for update;
  if not found then
    raise exception 'No se encontró la compra';
  end if;
  if v_estado = 'Anulada' then
    raise exception 'Esta compra ya está anulada';
  end if;

  if v_condicion = 'Credito' then
    select monto_total, saldo_pendiente into v_monto_total, v_saldo_pendiente from compras_credito where id = p_id;
    if found then
      v_credito_existe := true;
      if v_saldo_pendiente < v_monto_total then
        raise exception 'No se puede anular: esta compra a crédito ya tiene abonos registrados';
      end if;
    end if;
  end if;

  update compras set estado = 'Anulada', usuario_anulacion = p_usuario, motivo_anulacion = coalesce(p_motivo, ''), fecha_anulacion = now() where id = p_id;
  if v_credito_existe then
    delete from compras_credito where id = p_id;
  end if;

  for item in select id_producto, cantidad from compra_items where id_compra = p_id loop
    select stock into v_stock_actual from productos where id = item.id_producto for update;
    v_stock_nuevo := coalesce(v_stock_actual, 0) - item.cantidad;
    update productos set stock = v_stock_nuevo where id = item.id_producto;

    select id, cantidad_restante into v_lote_id, v_restante_actual from producto_lotes_costo where id_producto = item.id_producto and id_compra = p_id limit 1 for update;
    if v_lote_id is not null then
      update producto_lotes_costo set cantidad_restante = greatest(v_restante_actual - item.cantidad, 0) where id = v_lote_id;
    end if;

    insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
    values (item.id_producto, coalesce(v_stock_actual, 0), v_stock_nuevo, p_usuario, 'Anulación de compra ' || v_numero_documento, now());
    perform sincronizar_precio_compra_activo(item.id_producto);
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- guardar_venta_en_espera_manual / eliminar_venta_en_espera: reserva/libera
-- stock igual que VentaRepository -sin costear nada, solo aparta cantidad-.
-- ----------------------------------------------------------------------------
create or replace function guardar_venta_en_espera_manual(payload jsonb) returns uuid
language plpgsql as $$
declare
  v_es_nueva boolean := (payload->>'id' is null or payload->>'id' = '');
  v_id uuid := case when v_es_nueva then gen_random_uuid() else (payload->>'id')::uuid end;
  v_cantidades_nuevas jsonb;
  v_cantidades_liberar jsonb := '{}'::jsonb;
  v_stock_reservado boolean;
  v_id_producto_txt text;
  v_liberar numeric;
  v_reservar numeric;
  v_neto numeric;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
  v_usuario text := coalesce(payload->>'usuario', '');
begin
  v_cantidades_nuevas := calcular_cantidades_descuento(payload->'items');

  if not v_es_nueva then
    select stock_reservado, cantidades_reservadas into v_stock_reservado, v_cantidades_liberar from ventas_en_espera where id = v_id for update;
    if not found or v_stock_reservado is not true then
      v_cantidades_liberar := '{}'::jsonb;
    end if;
  end if;

  for v_id_producto_txt in select key from jsonb_each(v_cantidades_nuevas) union select key from jsonb_each(coalesce(v_cantidades_liberar, '{}'::jsonb)) loop
    v_liberar := coalesce((v_cantidades_liberar->>v_id_producto_txt)::numeric, 0);
    v_reservar := coalesce((v_cantidades_nuevas->>v_id_producto_txt)::numeric, 0);
    v_neto := v_reservar - v_liberar;
    continue when v_neto = 0;
    select stock into v_stock_actual from productos where id = v_id_producto_txt::uuid for update;
    if not found then continue; end if;
    v_stock_nuevo := coalesce(v_stock_actual, 0) - v_neto;
    update productos set stock = v_stock_nuevo where id = v_id_producto_txt::uuid;
    insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
    values (v_id_producto_txt::uuid, coalesce(v_stock_actual, 0), v_stock_nuevo, v_usuario,
      case when v_neto > 0 then 'Reservado para venta en espera' else 'Ajuste de reserva de venta en espera' end, now());
  end loop;

  insert into ventas_en_espera (
    id, fecha, tipo_documento, condicion, metodo_pago, documento_cliente, nombre_cliente, id_cliente,
    fecha_vencimiento, oc, reg_exonerado, reg_sag, observaciones, descuento_global, items, origen,
    stock_reservado, cantidades_reservadas
  ) values (
    v_id, now(), coalesce(payload->>'tipoDocumento', 'Factura'), coalesce(payload->>'condicion', 'Contado'),
    coalesce(payload->>'metodoPago', 'Efectivo'), coalesce(payload->>'documentoCliente', ''), coalesce(payload->>'nombreCliente', ''),
    nullif(payload->>'idCliente', '')::uuid, nullif(payload->>'fechaVencimiento', '')::timestamptz, coalesce(payload->>'oc', ''),
    coalesce(payload->>'regExonerado', ''), coalesce(payload->>'regSag', ''), coalesce(payload->>'observaciones', ''),
    coalesce((payload->>'descuentoGlobal')::numeric, 0), coalesce(payload->'items', '[]'::jsonb), 'manual', true, v_cantidades_nuevas
  )
  on conflict (id) do update set
    fecha = now(), tipo_documento = excluded.tipo_documento, condicion = excluded.condicion, metodo_pago = excluded.metodo_pago,
    documento_cliente = excluded.documento_cliente, nombre_cliente = excluded.nombre_cliente, id_cliente = excluded.id_cliente,
    fecha_vencimiento = excluded.fecha_vencimiento, oc = excluded.oc, reg_exonerado = excluded.reg_exonerado, reg_sag = excluded.reg_sag,
    observaciones = excluded.observaciones, descuento_global = excluded.descuento_global, items = excluded.items,
    origen = 'manual', stock_reservado = true, cantidades_reservadas = excluded.cantidades_reservadas;

  return v_id;
end;
$$;

create or replace function eliminar_venta_en_espera(p_id uuid, p_usuario text default '') returns void
language plpgsql as $$
declare
  v_stock_reservado boolean;
  v_cantidades jsonb;
  v_id_producto_txt text;
  v_cantidad numeric;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
begin
  select stock_reservado, cantidades_reservadas into v_stock_reservado, v_cantidades from ventas_en_espera where id = p_id for update;
  if not found then return; end if;
  if v_stock_reservado then
    for v_id_producto_txt in select key from jsonb_each(coalesce(v_cantidades, '{}'::jsonb)) loop
      v_cantidad := (v_cantidades->>v_id_producto_txt)::numeric;
      continue when v_cantidad = 0;
      select stock into v_stock_actual from productos where id = v_id_producto_txt::uuid for update;
      if not found then continue; end if;
      v_stock_nuevo := coalesce(v_stock_actual, 0) + v_cantidad;
      update productos set stock = v_stock_nuevo where id = v_id_producto_txt::uuid;
      insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
      values (v_id_producto_txt::uuid, coalesce(v_stock_actual, 0), v_stock_nuevo, p_usuario, 'Liberado de venta en espera', now());
    end loop;
  end if;
  delete from ventas_en_espera where id = p_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- Ajustes de stock manuales de Inventario (ProductoRepository.registrarIngreso
-- /registrarSalida/descontarStock).
-- ----------------------------------------------------------------------------
create or replace function registrar_ingreso_stock(payload jsonb) returns void
language plpgsql as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_cantidad numeric := (payload->>'cantidad')::numeric;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
begin
  if v_cantidad <= 0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
  select stock into v_stock_actual from productos where id = v_id for update;
  v_stock_nuevo := coalesce(v_stock_actual, 0) + v_cantidad;
  update productos set stock = v_stock_nuevo where id = v_id;
  insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
  values (v_id, coalesce(v_stock_actual, 0), v_stock_nuevo, coalesce(payload->>'usuario', ''),
    case when trim(coalesce(payload->>'motivo', '')) = '' then 'Ingreso manual' else trim(payload->>'motivo') end, now());
  insert into producto_lotes_costo (id_producto, cantidad_original, cantidad_restante, costo_unitario, fecha, origen)
  values (v_id, v_cantidad, v_cantidad, (payload->>'costoUnitario')::numeric, now(), 'ajuste');
  perform sincronizar_precio_compra_activo(v_id);
end;
$$;

create or replace function registrar_salida_stock(payload jsonb) returns void
language plpgsql as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_cantidad numeric := (payload->>'cantidad')::numeric;
  v_id_lote uuid := nullif(payload->>'idLote', '')::uuid;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
  v_restante_lote numeric;
  v_precio_compra numeric;
  v_costo numeric;
begin
  if v_cantidad <= 0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
  select stock, precio_compra into v_stock_actual, v_precio_compra from productos where id = v_id for update;

  if v_id_lote is not null then
    select cantidad_restante into v_restante_lote from producto_lotes_costo where id = v_id_lote for update;
    if not found then raise exception 'Ese lote ya no existe, actualizá e intentá de nuevo'; end if;
    if v_cantidad > v_restante_lote then
      raise exception 'Ese lote solo tiene % unidades disponibles', formatear_cantidad(v_restante_lote);
    end if;
    update producto_lotes_costo set cantidad_restante = v_restante_lote - v_cantidad where id = v_id_lote;
  else
    if v_cantidad > coalesce(v_stock_actual, 0) then
      raise exception 'No hay suficiente existencia sin lote específico';
    end if;
    v_costo := consumir_fifo_lotes(v_id, v_cantidad, coalesce(v_precio_compra, 0));
  end if;

  v_stock_nuevo := coalesce(v_stock_actual, 0) - v_cantidad;
  update productos set stock = v_stock_nuevo where id = v_id;
  insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
  values (v_id, coalesce(v_stock_actual, 0), v_stock_nuevo, coalesce(payload->>'usuario', ''),
    case when trim(coalesce(payload->>'motivo', '')) = '' then 'Salida manual' else trim(payload->>'motivo') end, now());
  perform sincronizar_precio_compra_activo(v_id);
end;
$$;

create or replace function descontar_stock(payload jsonb) returns void
language plpgsql as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_cantidad numeric := (payload->>'cantidad')::numeric;
  v_stock_actual numeric;
  v_stock_nuevo numeric;
begin
  select stock into v_stock_actual from productos where id = v_id for update;
  v_stock_nuevo := coalesce(v_stock_actual, 0) - v_cantidad;
  update productos set stock = v_stock_nuevo where id = v_id;
  insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
  values (v_id, coalesce(v_stock_actual, 0), v_stock_nuevo, coalesce(payload->>'usuario', ''), coalesce(payload->>'motivo', ''), now());
end;
$$;

-- ----------------------------------------------------------------------------
-- Abonos de crédito (venta y compra): cadena dependiente -editar/eliminar uno
-- del medio recalcula todos los que le siguen desde montoTotal-.
-- ----------------------------------------------------------------------------
create or replace function recalcular_cadena_abonos_venta_credito(p_id_credito uuid, p_monto_total numeric) returns void
language plpgsql as $$
declare
  v_saldo numeric := round(p_monto_total, 2);
  rec record;
  v_saldo_anterior numeric;
  v_crudo numeric;
begin
  for rec in select id, monto_abonado, interes from venta_credito_abonos where id_venta_credito = p_id_credito order by fecha for update loop
    v_saldo_anterior := v_saldo;
    v_crudo := v_saldo_anterior - rec.monto_abonado + rec.interes;
    if v_crudo < -0.01 then
      raise exception 'El abono de % superaría el saldo disponible en ese momento (%)', rec.monto_abonado, (v_saldo_anterior + rec.interes);
    end if;
    v_saldo := round(greatest(v_crudo, 0), 2);
    update venta_credito_abonos set saldo_anterior = round(v_saldo_anterior, 2), saldo_pendiente = v_saldo where id = rec.id;
  end loop;
  update ventas_credito set saldo_pendiente = v_saldo where id = p_id_credito;
end;
$$;

create or replace function registrar_abono_venta_credito(payload jsonb) returns void
language plpgsql as $$
declare
  v_id_credito uuid := (payload->>'idCredito')::uuid;
  v_saldo_anterior numeric := (payload->>'saldoAnterior')::numeric;
  v_monto_abonado numeric := (payload->>'montoAbonado')::numeric;
  v_interes numeric := coalesce((payload->>'interes')::numeric, 0);
  v_nuevo_saldo numeric;
begin
  if v_monto_abonado > v_saldo_anterior + v_interes + 0.01 then
    raise exception 'El abono supera el saldo disponible en este crédito';
  end if;
  v_nuevo_saldo := round(greatest(v_saldo_anterior - v_monto_abonado + v_interes, 0), 2);
  update ventas_credito set saldo_pendiente = v_nuevo_saldo where id = v_id_credito;
  insert into venta_credito_abonos (id_venta_credito, fecha, monto_abonado, saldo_anterior, interes, saldo_pendiente, metodo_pago, numero_recibo, usuario)
  values (v_id_credito, (payload->>'fecha')::timestamptz, round(v_monto_abonado, 2), round(v_saldo_anterior, 2), round(v_interes, 2), v_nuevo_saldo,
    coalesce(payload->>'metodoPago', ''), coalesce(payload->>'numeroRecibo', ''), coalesce(payload->>'usuario', ''));
end;
$$;

create or replace function editar_abono_venta_credito(payload jsonb) returns void
language plpgsql as $$
declare
  v_id_credito uuid := (payload->>'idCredito')::uuid;
begin
  update venta_credito_abonos set
    monto_abonado = round((payload->>'montoAbonado')::numeric, 2),
    interes = round(coalesce((payload->>'interes')::numeric, 0), 2),
    fecha = (payload->>'fecha')::timestamptz,
    metodo_pago = coalesce(payload->>'metodoPago', ''),
    numero_recibo = coalesce(payload->>'numeroRecibo', '')
  where id = (payload->>'idAbono')::uuid;
  perform recalcular_cadena_abonos_venta_credito(v_id_credito, (payload->>'montoTotal')::numeric);
end;
$$;

create or replace function eliminar_abono_venta_credito(p_id_credito uuid, p_id_abono uuid, p_monto_total numeric) returns void
language plpgsql as $$
begin
  delete from venta_credito_abonos where id = p_id_abono;
  perform recalcular_cadena_abonos_venta_credito(p_id_credito, p_monto_total);
end;
$$;

create or replace function recalcular_cadena_abonos_compra_credito(p_id_compra uuid, p_monto_total numeric) returns void
language plpgsql as $$
declare
  v_saldo numeric := round(p_monto_total, 2);
  rec record;
  v_saldo_anterior numeric;
  v_crudo numeric;
begin
  for rec in select id, monto_abonado, interes from compra_credito_abonos where id_compra_credito = p_id_compra order by fecha for update loop
    v_saldo_anterior := v_saldo;
    v_crudo := v_saldo_anterior - rec.monto_abonado + rec.interes;
    if v_crudo < -0.01 then
      raise exception 'El abono de % superaría el saldo disponible en ese momento (%)', rec.monto_abonado, (v_saldo_anterior + rec.interes);
    end if;
    v_saldo := round(greatest(v_crudo, 0), 2);
    update compra_credito_abonos set saldo_anterior = round(v_saldo_anterior, 2), saldo_pendiente = v_saldo where id = rec.id;
  end loop;
  update compras_credito set saldo_pendiente = v_saldo where id = p_id_compra;
end;
$$;

create or replace function registrar_abono_compra_credito(payload jsonb) returns void
language plpgsql as $$
declare
  v_id_compra uuid := (payload->>'idCompra')::uuid;
  v_saldo_anterior numeric := (payload->>'saldoAnterior')::numeric;
  v_monto_abonado numeric := (payload->>'montoAbonado')::numeric;
  v_interes numeric := coalesce((payload->>'interes')::numeric, 0);
  v_nuevo_saldo numeric;
begin
  if v_monto_abonado > v_saldo_anterior + v_interes + 0.01 then
    raise exception 'El abono supera el saldo disponible en esa factura';
  end if;
  v_nuevo_saldo := round(greatest(v_saldo_anterior - v_monto_abonado + v_interes, 0), 2);
  update compras_credito set saldo_pendiente = v_nuevo_saldo where id = v_id_compra;
  insert into compra_credito_abonos (id_compra_credito, id_proveedor, nombre_proveedor, fecha, monto_abonado, saldo_anterior, interes, saldo_pendiente, metodo_pago, numero_recibo, usuario)
  values (v_id_compra, nullif(payload->>'idProveedor', '')::uuid, coalesce(payload->>'nombreProveedor', ''), (payload->>'fecha')::timestamptz,
    round(v_monto_abonado, 2), round(v_saldo_anterior, 2), round(v_interes, 2), v_nuevo_saldo, coalesce(payload->>'metodoPago', ''),
    coalesce(payload->>'numeroRecibo', ''), coalesce(payload->>'usuario', ''));
end;
$$;

create or replace function editar_abono_compra_credito(payload jsonb) returns void
language plpgsql as $$
declare
  v_id_compra uuid := (payload->>'idCompra')::uuid;
begin
  update compra_credito_abonos set
    monto_abonado = round((payload->>'montoAbonado')::numeric, 2),
    interes = round(coalesce((payload->>'interes')::numeric, 0), 2),
    fecha = (payload->>'fecha')::timestamptz,
    metodo_pago = coalesce(payload->>'metodoPago', ''),
    numero_recibo = coalesce(payload->>'numeroRecibo', '')
  where id = (payload->>'idAbono')::uuid;
  perform recalcular_cadena_abonos_compra_credito(v_id_compra, (payload->>'montoTotal')::numeric);
end;
$$;

create or replace function eliminar_abono_compra_credito(p_id_compra uuid, p_id_abono uuid, p_monto_total numeric) returns void
language plpgsql as $$
begin
  delete from compra_credito_abonos where id = p_id_abono;
  perform recalcular_cadena_abonos_compra_credito(p_id_compra, p_monto_total);
end;
$$;

create or replace function registrar_abono_general_compra_credito(payload jsonb) returns void
language plpgsql as $$
declare
  item jsonb;
  v_id_compra uuid;
  v_saldo_actual numeric;
  v_monto_aplicado numeric;
  v_saldo_resultante numeric;
begin
  for item in select * from jsonb_array_elements(payload->'distribucion') loop
    v_id_compra := (item->>'idCompra')::uuid;
    v_monto_aplicado := (item->>'montoAplicado')::numeric;
    select saldo_pendiente into v_saldo_actual from compras_credito where id = v_id_compra for update;
    if v_monto_aplicado > coalesce(v_saldo_actual, 0) + 0.01 then
      raise exception 'El monto asignado supera el saldo pendiente de una factura';
    end if;
    v_saldo_resultante := round(v_saldo_actual - v_monto_aplicado, 2);
    update compras_credito set saldo_pendiente = v_saldo_resultante where id = v_id_compra;
    insert into compra_credito_abonos (id_compra_credito, id_proveedor, nombre_proveedor, fecha, monto_abonado, saldo_anterior, interes, saldo_pendiente, metodo_pago, numero_recibo, usuario)
    values (v_id_compra, nullif(item->>'idProveedor', '')::uuid, coalesce(item->>'nombreProveedor', ''), (payload->>'fecha')::timestamptz,
      round(v_monto_aplicado, 2), round(v_saldo_actual, 2), 0, v_saldo_resultante, coalesce(payload->>'metodoPago', ''), '', coalesce(payload->>'usuario', ''));
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- Cierre de caja: inserta el cierre y arranca el turno siguiente con el
-- totalReal de este, en una sola operación (CierreCajaRepository.registrarCierre).
-- ----------------------------------------------------------------------------
create or replace function registrar_cierre_caja(payload jsonb) returns void
language plpgsql as $$
declare
  v_fecha_fin timestamptz := (payload->>'fechaFin')::timestamptz;
  v_total_real numeric := (payload->>'totalReal')::numeric;
  v_usuario text := coalesce(payload->>'usuarioResponsable', '');
begin
  insert into cierres_caja (
    fecha_inicio, fecha_fin, monto_inicial, ingresos_efectivo, ingresos_tarjeta, ingresos_transferencia,
    egresos_efectivo, egresos_transferencia, total_calculado_efectivo, total_transferencia, gran_total,
    total_real, diferencia, usuario_responsable, observaciones
  ) values (
    (payload->>'fechaInicio')::timestamptz, v_fecha_fin, (payload->>'montoInicial')::numeric,
    (payload->>'ingresosEfectivo')::numeric, (payload->>'ingresosTarjeta')::numeric, (payload->>'ingresosTransferencia')::numeric,
    (payload->>'egresosEfectivo')::numeric, (payload->>'egresosTransferencia')::numeric, (payload->>'totalCalculadoEfectivo')::numeric,
    (payload->>'totalTransferencia')::numeric, (payload->>'granTotal')::numeric, v_total_real, (payload->>'diferencia')::numeric,
    v_usuario, coalesce(payload->>'observaciones', '')
  );
  insert into caja_estado (id, fecha_desde, monto_inicial, usuario_responsable, actualizado_en)
  values (1, v_fecha_fin, v_total_real, v_usuario, now())
  on conflict (id) do update set fecha_desde = excluded.fecha_desde, monto_inicial = excluded.monto_inicial,
    usuario_responsable = excluded.usuario_responsable, actualizado_en = excluded.actualizado_en;
end;
$$;

-- ----------------------------------------------------------------------------
-- escaneo_remoto: NO se migró a tabla en el diseño original del esquema (ver
-- comentario en schema.sql: "encajan mejor como canal de Realtime"), pero la
-- app sí necesita esta funcionalidad viva (celular como lector de código de
-- barras) — se agrega como 2 tablas chicas, efímeras (sesiones de segundos de
-- vida), en vez de rediseñar sobre Realtime broadcast/presence puro para no
-- arriesgar una reimplementación sin poder probarla en este entorno.
-- ----------------------------------------------------------------------------
create table if not exists escaneos_remotos (
  codigo text primary key,
  conectado boolean not null default false,
  creado_en timestamptz not null default now()
);
create table if not exists escaneo_remoto_eventos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null references escaneos_remotos (codigo) on delete cascade,
  valor text not null,
  fecha timestamptz not null default now()
);
create index if not exists idx_escaneo_remoto_eventos_codigo on escaneo_remoto_eventos (codigo);

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'escaneos_remotos' and policyname = 'escaneos_remotos_allow_all_anon') then
    alter table public.escaneos_remotos enable row level security;
    create policy escaneos_remotos_allow_all_anon on public.escaneos_remotos for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'escaneo_remoto_eventos' and policyname = 'escaneo_remoto_eventos_allow_all_anon') then
    alter table public.escaneo_remoto_eventos enable row level security;
    create policy escaneo_remoto_eventos_allow_all_anon on public.escaneo_remoto_eventos for all using (true) with check (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'escaneos_remotos'
  ) then
    alter publication supabase_realtime add table escaneos_remotos;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'escaneo_remoto_eventos'
  ) then
    alter publication supabase_realtime add table escaneo_remoto_eventos;
  end if;
end $$;

-- Permisos ad-hoc por usuario del rol Encargado (roles.dart, usuario_model.dart,
-- acceso_especial.dart): qué pantallas (SubModulo.moduleKey) y qué acciones
-- (PermisosEspeciales.*) tiene habilitadas ESE usuario en particular. Solo se
-- guardan (no vacíos) cuando rol == 'Encargado'; para cualquier otro rol quedan
-- en '{}'. Estructura libre, no se consulta por SQL -jsonb-.
alter table usuarios add column if not exists pantallas_permitidas jsonb not null default '{}'::jsonb;
alter table usuarios add column if not exists acciones_permitidas jsonb not null default '{}'::jsonb;

-- ============================================================================
-- APARTADOS (fase Dart, ver lib/features/apartados/). Ajuste puntual sobre
-- el esquema original de apartados (arriba): falta un snapshot congelado del
-- nombre del cliente -mismo criterio que ventas.nombre_cliente /
-- ventas_credito.nombre_cliente / compras.razon_social en el resto del
-- esquema-, para listar apartados sin depender de un join contra clientes en
-- cada pantalla (clientes.id_cliente ya tiene on delete restrict, así que el
-- registro real siempre existe, pero el nombre puede cambiar después).
-- ----------------------------------------------------------------------------
alter table apartados add column if not exists nombre_cliente text not null default '';
create index if not exists idx_apartados_nombre_cliente on apartados (nombre_cliente);

-- ----------------------------------------------------------------------------
-- producto_disponibilidad: cuánto de un producto está físicamente en stock
-- vs. cuánto ya está comprometido por apartados ACTIVOS (todavía no
-- entregados) -para no vender/apartar de más algo que ya se separó para
-- otro cliente-. Es de solo lectura (se usa con SELECT desde Dart, tanto en
-- Inventario como al armar un apartado nuevo); la validación que de verdad
-- IMPIDE apartar de más vive en crear_apartado (abajo), que recalcula esto
-- mismo pero bloqueando la fila de productos (FOR UPDATE) para que dos
-- apartados concurrentes del mismo producto no pasen los dos el chequeo a la
-- vez -esta vista sola, sin ese lock, no alcanzaría para evitar esa carrera-.
-- ----------------------------------------------------------------------------
create or replace view producto_disponibilidad as
select
  p.id as id_producto,
  p.stock as stock_fisico,
  coalesce(a.cantidad_apartada, 0) as cantidad_apartada,
  p.stock - coalesce(a.cantidad_apartada, 0) as disponible
from productos p
left join (
  select ai.id_producto, sum(ai.cantidad) as cantidad_apartada
  from apartado_items ai
  join apartados ap on ap.id = ai.id_apartado
  where ap.estado = 'activo'
  group by ai.id_producto
) a on a.id_producto = p.id;
comment on view producto_disponibilidad is 'stock_fisico (productos.stock) vs. cantidad_apartada (activa) vs. disponible real. Ver crear_apartado para el chequeo atómico real al crear un apartado.';

-- ----------------------------------------------------------------------------
-- crear_apartado: inserta cabecera + items (+ cuotas si modalidad =
-- 'cuotas_fijas', ya armadas por Dart -número/monto/fecha de cada cuota,
-- nada hardcodeado acá-), validando ANTES de insertar nada que cada producto
-- de la lista tenga existencia disponible de verdad (stock físico menos lo
-- ya apartado por otros apartados activos), bloqueando la fila de
-- productos (FOR UPDATE) para que dos apartados concurrentes del mismo
-- producto no pasen los dos el chequeo a la vez. NO descuenta stock -eso
-- pasa recién en marcar_apartado_entregado-, esto solo reserva.
-- payload: idCliente, nombreCliente, montoTotal, montoInicial, modalidad,
--   fechaCreacion, items: [{idProducto, nombreProducto, cantidad,
--   precioUnitario, subtotal}], cuotas (solo si modalidad='cuotas_fijas'):
--   [{numeroCuota, montoProgramado, fechaProgramada}].
-- ----------------------------------------------------------------------------
create or replace function crear_apartado(payload jsonb) returns jsonb
language plpgsql as $$
declare
  v_id_apartado uuid := gen_random_uuid();
  v_id_cliente uuid := nullif(payload->>'idCliente', '')::uuid;
  v_monto_total numeric := (payload->>'montoTotal')::numeric;
  v_monto_inicial numeric := coalesce((payload->>'montoInicial')::numeric, 0);
  v_modalidad text := payload->>'modalidad';
  item jsonb;
  cuota jsonb;
  v_id_producto uuid;
  v_cantidad numeric;
  v_nombre text;
  v_stock_fisico numeric;
  v_cantidad_apartada numeric;
  v_disponible numeric;
begin
  if v_monto_inicial > v_monto_total + 0.01 then
    raise exception 'El pago inicial no puede superar el monto total del apartado';
  end if;

  -- Chequeo de disponibilidad (con lock) ANTES de insertar nada: si un
  -- producto no alcanza, toda la operación se cancela sola (ver raise
  -- exception dentro de una función plpgsql = rollback automático de lo que
  -- ya se hubiera insertado en esta misma llamada).
  for item in select * from jsonb_array_elements(payload->'items') loop
    v_id_producto := nullif(item->>'idProducto', '')::uuid;
    if v_id_producto is null then continue; end if;
    v_cantidad := (item->>'cantidad')::numeric;
    v_nombre := coalesce(item->>'nombreProducto', '');
    select stock into v_stock_fisico from productos where id = v_id_producto for update;
    select coalesce(sum(ai.cantidad), 0) into v_cantidad_apartada
      from apartado_items ai
      join apartados ap on ap.id = ai.id_apartado
      where ai.id_producto = v_id_producto and ap.estado = 'activo';
    v_disponible := coalesce(v_stock_fisico, 0) - v_cantidad_apartada;
    if v_disponible < v_cantidad then
      raise exception 'Existencia insuficiente de "%": disponible % (ya hay % apartado), solicitado %',
        v_nombre, formatear_cantidad(v_disponible), formatear_cantidad(v_cantidad_apartada), formatear_cantidad(v_cantidad);
    end if;
  end loop;

  insert into apartados (id, id_cliente, nombre_cliente, monto_total, monto_inicial, modalidad, estado, fecha_creacion)
  values (
    v_id_apartado, v_id_cliente, coalesce(payload->>'nombreCliente', ''), v_monto_total, v_monto_inicial, v_modalidad,
    'activo', coalesce(nullif(payload->>'fechaCreacion', '')::timestamptz, now())
  );

  for item in select * from jsonb_array_elements(payload->'items') loop
    insert into apartado_items (id_apartado, id_producto, nombre_producto, cantidad, precio_unitario, subtotal)
    values (
      v_id_apartado, nullif(item->>'idProducto', '')::uuid, item->>'nombreProducto',
      (item->>'cantidad')::numeric, (item->>'precioUnitario')::numeric, (item->>'subtotal')::numeric
    );
  end loop;

  if v_modalidad = 'cuotas_fijas' then
    for cuota in select * from jsonb_array_elements(coalesce(payload->'cuotas', '[]'::jsonb)) loop
      insert into apartado_cuotas (id_apartado, numero_cuota, monto_programado, fecha_programada, estado)
      values (
        v_id_apartado, (cuota->>'numeroCuota')::integer, (cuota->>'montoProgramado')::numeric,
        (cuota->>'fechaProgramada')::date, 'pendiente'
      );
    end loop;
  end if;

  return jsonb_build_object('id', v_id_apartado);
end;
$$;

-- ----------------------------------------------------------------------------
-- registrar_abono_apartado: modalidad 'abonos_libres'. A diferencia de
-- venta_credito_abonos/compra_credito_abonos (que confían en un
-- saldoAnterior calculado en Dart, porque ahí sí hay una columna
-- saldo_pendiente en la cabecera que Dart ya leyó de un stream reciente),
-- apartados NO tiene columna de saldo propia -el saldo siempre se deriva de
-- monto_total/monto_inicial/abonos-, así que acá se recalcula el saldo
-- anterior DE NUEVO server-side (bloqueando la fila de apartados) en vez de
-- confiar en lo que mande Dart: evita que dos abonos concurrentes al mismo
-- apartado lean el mismo "saldo anterior" viejo y ninguno de los dos falle.
-- ----------------------------------------------------------------------------
create or replace function registrar_abono_apartado(payload jsonb) returns jsonb
language plpgsql as $$
declare
  v_id_apartado uuid := (payload->>'idApartado')::uuid;
  v_monto_abonado numeric := (payload->>'montoAbonado')::numeric;
  v_monto_total numeric;
  v_monto_inicial numeric;
  v_estado text;
  v_modalidad text;
  v_ya_abonado numeric;
  v_saldo_anterior numeric;
  v_saldo_pendiente numeric;
begin
  select monto_total, monto_inicial, estado, modalidad into v_monto_total, v_monto_inicial, v_estado, v_modalidad
    from apartados where id = v_id_apartado for update;
  if not found then
    raise exception 'No se encontró el apartado';
  end if;
  if v_estado <> 'activo' then
    raise exception 'Este apartado no admite abonos (estado: %)', v_estado;
  end if;
  if v_modalidad <> 'abonos_libres' then
    raise exception 'Este apartado es de cuotas fijas, no de abonos libres';
  end if;
  if v_monto_abonado <= 0 then
    raise exception 'Ingresá un monto de abono válido';
  end if;

  select coalesce(sum(monto_abonado), 0) into v_ya_abonado from apartado_abonos where id_apartado = v_id_apartado;
  v_saldo_anterior := round(v_monto_total - v_monto_inicial - v_ya_abonado, 2);
  if v_monto_abonado > v_saldo_anterior + 0.01 then
    raise exception 'El abono (%) supera el saldo pendiente (%)', round(v_monto_abonado, 2), v_saldo_anterior;
  end if;
  v_saldo_pendiente := round(greatest(v_saldo_anterior - v_monto_abonado, 0), 2);

  insert into apartado_abonos (id_apartado, monto_abonado, fecha, saldo_anterior, saldo_pendiente)
  values (v_id_apartado, round(v_monto_abonado, 2), coalesce(nullif(payload->>'fecha', '')::timestamptz, now()), v_saldo_anterior, v_saldo_pendiente);

  return jsonb_build_object('saldoAnterior', v_saldo_anterior, 'saldoPendiente', v_saldo_pendiente);
end;
$$;

-- ----------------------------------------------------------------------------
-- marcar_apartado_entregado: acá -y solo acá- se descuenta el stock físico
-- de verdad (mismo motor FIFO que registrar_venta: consumir_fifo_lotes +
-- historial_stock + sincronizar_precio_compra_activo), porque es el momento
-- en que el producto de verdad sale del local. Exige saldo pendiente en 0
-- -no se puede entregar algo que no se terminó de pagar, es la esencia de
-- un apartado- y estado 'activo' (no ya entregado/cancelado).
-- ----------------------------------------------------------------------------
create or replace function marcar_apartado_entregado(p_id_apartado uuid, p_usuario text) returns void
language plpgsql as $$
declare
  v_estado text;
  v_monto_total numeric;
  v_monto_inicial numeric;
  v_modalidad text;
  v_ya_pagado numeric;
  v_saldo numeric;
  item record;
  v_stock_actual numeric;
  v_precio_compra numeric;
  v_costo numeric;
  v_stock_nuevo numeric;
begin
  select estado, monto_total, monto_inicial, modalidad into v_estado, v_monto_total, v_monto_inicial, v_modalidad
    from apartados where id = p_id_apartado for update;
  if not found then
    raise exception 'No se encontró el apartado';
  end if;
  if v_estado <> 'activo' then
    raise exception 'Este apartado no está activo (estado: %)', v_estado;
  end if;

  if v_modalidad = 'abonos_libres' then
    select coalesce(sum(monto_abonado), 0) into v_ya_pagado from apartado_abonos where id_apartado = p_id_apartado;
  else
    select coalesce(sum(monto_programado), 0) into v_ya_pagado from apartado_cuotas where id_apartado = p_id_apartado and estado = 'pagada';
  end if;
  v_saldo := round(v_monto_total - v_monto_inicial - v_ya_pagado, 2);
  if v_saldo > 0.01 then
    raise exception 'Este apartado todavía tiene un saldo pendiente de %', v_saldo;
  end if;

  for item in select id_producto, cantidad from apartado_items where id_apartado = p_id_apartado loop
    if item.id_producto is null then continue; end if;
    select stock, precio_compra into v_stock_actual, v_precio_compra from productos where id = item.id_producto for update;
    v_costo := consumir_fifo_lotes(item.id_producto, item.cantidad, coalesce(v_precio_compra, 0));
    v_stock_nuevo := greatest(coalesce(v_stock_actual, 0) - item.cantidad, 0);
    update productos set stock = v_stock_nuevo where id = item.id_producto;
    insert into producto_historial_stock (id_producto, stock_anterior, stock_nuevo, usuario, motivo, fecha)
    values (item.id_producto, coalesce(v_stock_actual, 0), v_stock_nuevo, coalesce(p_usuario, ''), 'Entrega de apartado', now());
    perform sincronizar_precio_compra_activo(item.id_producto);
  end loop;

  update apartados set estado = 'completado', fecha_entrega = now() where id = p_id_apartado;
end;
$$;
-- Tablas que la app consume con .stream() (Supabase Realtime) pero que no
-- habían quedado en la publicación `supabase_realtime` al crear el esquema.
--
-- Sin esto, `.stream()` entrega solo el snapshot inicial y nunca recibe los
-- INSERT/UPDATE/DELETE posteriores: en la app se veía como que un registro
-- recién guardado no aparecía hasta apretar "Refrescar", y como un parpadeo
-- constante de la pantalla (la suscripción reintentando en loop). En el
-- sistema original esto no pasaba porque Firestore transmite en vivo todas
-- las colecciones por defecto, sin publicación que configurar.
alter publication supabase_realtime add table categorias;
alter publication supabase_realtime add table clientes;
alter publication supabase_realtime add table proveedores;
alter publication supabase_realtime add table usuarios;
alter publication supabase_realtime add table promociones;
alter publication supabase_realtime add table compras_credito;
alter publication supabase_realtime add table compra_credito_abonos;
alter publication supabase_realtime add table compras_en_espera;
alter publication supabase_realtime add table ventas_en_espera;
alter publication supabase_realtime add table pendientes_reposicion;
alter publication supabase_realtime add table producto_lotes_costo;
