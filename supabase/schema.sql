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
