import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import '../../../core/utils/reintentos.dart';
import 'negocio_model.dart';

class NegocioRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  // Cache en memoria de la última lectura exitosa de `obtenerNegocioActual`.
  // Antes cada acción puntual (pedir clave especial, abrir ajuste de stock,
  // generar el código de barras, etc.) esperaba una ida y vuelta nueva al
  // servidor, y en la primera vez de la sesión esa ida y vuelta podía tardar
  // varios segundos sin que la pantalla mostrara nada mientras tanto — daba
  // la sensación de que el toque no había hecho nada. Con este cache, una
  // vez que se obtiene la configuración una vez (por ejemplo, justo después
  // del login, ver `AuthNotifier.login`), el resto de acciones de la sesión
  // la reciben al instante.
  static NegocioModel? _cache;
  static DateTime? _cacheFecha;
  // 10 minutos: no hay riesgo de quedar con datos viejos porque
  // `_invalidarCache()` se llama apenas se guarda un cambio real; este plazo
  // solo evita repetir la ida y vuelta al servidor en acciones puntuales
  // (editar producto, ajustar stock, etc.) que antes volvían a pedirla cada
  // 30 segundos aunque nada hubiera cambiado.
  static const _vigenciaCache = Duration(minutes: 10);

  String hashClave(String clave) {
    return sha256.convert(utf8.encode(clave)).toString();
  }

  Stream<NegocioModel> obtenerNegocio() {
    return conRedStream(() => _db
        .from('negocio_config')
        .stream(primaryKey: ['id'])
        .map((filas) => NegocioModel.fromMap(filas.isEmpty ? null : filas.first)));
  }

  /// Lectura única (no suscripción en vivo) de la configuración del negocio.
  /// Se usa antes de acciones puntuales (registrar venta, imprimir, pedir
  /// clave especial) en vez de `negocioStreamProvider.future`: ese depende
  /// de que el listener en vivo llegue a emitir su primer valor, lo cual en
  /// algunas redes puede tardar mucho o no llegar nunca y dejaba la acción
  /// "cargando" para siempre. Acá, si no responde rápido, se sigue con la
  /// configuración por defecto en vez de trabar la acción.
  Future<NegocioModel> obtenerNegocioActual() async {
    final cache = _cache;
    final cacheFecha = _cacheFecha;
    if (cache != null &&
        cacheFecha != null &&
        DateTime.now().difference(cacheFecha) < _vigenciaCache) {
      return cache;
    }
    try {
      final filas = await _db.from('negocio_config').select().limit(1).timeout(const Duration(seconds: 8));
      final negocio = NegocioModel.fromMap(filas.isEmpty ? null : filas.first);
      _cache = negocio;
      _cacheFecha = DateTime.now();
      return negocio;
    } catch (_) {
      return cache ?? const NegocioModel();
    }
  }

  /// Como [obtenerNegocioActual], pero pensada para gates de seguridad
  /// (`verificarAccesoEspecial`): ahí una falla de red NUNCA debe
  /// interpretarse como "no hay clave especial configurada", porque eso
  /// deja pasar la acción protegida sin pedir nada. A diferencia de
  /// [obtenerNegocioActual], si no hay cache vigente y la lectura falla o
  /// tarda más de la cuenta (típico justo al abrir la app, con la conexión
  /// todavía estableciéndose), esto reintenta unas veces (ver
  /// [conReintentos]) antes de relanzar la excepción, para que una demora
  /// pasajera de conexión se resuelva sola en vez de bloquear al cajero a
  /// la primera.
  Future<NegocioModel> obtenerNegocioParaSeguridad() async {
    final cache = _cache;
    final cacheFecha = _cacheFecha;
    if (cache != null &&
        cacheFecha != null &&
        DateTime.now().difference(cacheFecha) < _vigenciaCache) {
      return cache;
    }
    return conReintentos(() async {
      final filas = await _db.from('negocio_config').select().limit(1).timeout(const Duration(seconds: 8));
      final negocio = NegocioModel.fromMap(filas.isEmpty ? null : filas.first);
      _cache = negocio;
      _cacheFecha = DateTime.now();
      return negocio;
    });
  }

  /// Invalida el cache de [obtenerNegocioActual]: se llama luego de guardar
  /// cualquier cambio a la configuración para que el resto de la sesión no
  /// siga usando datos viejos (permisos, clave especial, etc.) hasta que
  /// venza el cache por su cuenta.
  void _invalidarCache() {
    _cache = null;
    _cacheFecha = null;
  }

  Future<void> _guardar(Map<String, dynamic> datos) {
    return conRed(() async {
      await _db.from('negocio_config').upsert({'id': 1, ...datos});
      _invalidarCache();
    });
  }

  Future<void> actualizarDatosGenerales({
    required String nombre,
    required String correo,
    required String rtn,
    required String cai,
    required String direccion,
    required String telefono,
    required String eslogan,
    required String rangoPrefijo,
    required String rangoDesde,
    required String rangoHasta,
    required DateTime? fechaLimiteEmision,
  }) {
    return _guardar({
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
    });
  }

  Future<void> guardarLogoColor(Uint8List bytes) {
    return _guardar({'logo_color_base64': base64Encode(bytes)});
  }

  Future<void> guardarLogoBn(Uint8List bytes) {
    return _guardar({'logo_bn_base64': base64Encode(bytes)});
  }

  Future<void> actualizarPermisos(Map<String, bool> permisos) {
    return _guardar({'permisos': permisos});
  }

  Future<void> establecerClave(String clave) {
    return _guardar({'clave_especial_hash': hashClave(clave)});
  }

  Future<void> quitarClave() {
    return _guardar({'clave_especial_hash': ''});
  }

  Future<void> actualizarImpresoraTermica(String url, String nombre) {
    return _guardar({'impresora_termica_url': url, 'impresora_termica_nombre': nombre});
  }

  Future<void> actualizarImpresoraEtiquetas(String url, String nombre) {
    return _guardar({'impresora_etiquetas_url': url, 'impresora_etiquetas_nombre': nombre});
  }

  Future<void> establecerFacturaImprimirCopia(bool valor) {
    return _guardar({'factura_imprimir_copia': valor});
  }

  Future<void> establecerFacturaPreciosConIsv(bool valor) {
    return _guardar({'factura_precios_con_isv': valor});
  }

  Future<void> establecerTecladoCompactoTablet(bool valor) {
    return _guardar({'teclado_compacto_tablet': valor});
  }

  Future<void> establecerModoImpresion(String modo) {
    return _guardar({'modo_impresion': modo});
  }

  /// Interruptor maestro de impresión (ver NegocioModel.imprimirFacturas):
  /// si [valor] es false, al confirmar una venta no se intenta imprimir nada.
  Future<void> establecerImprimirFacturas(bool valor) {
    return _guardar({'imprimir_facturas': valor});
  }

  Future<void> actualizarImpresoraRed(String ip, int puerto) {
    return _guardar({'impresora_red_ip': ip, 'impresora_red_puerto': puerto});
  }

  /// [hostname] vacío vuelve al comportamiento de siempre (cualquier
  /// escritorio actúa como PC principal) -ver NegocioModel.pcPrincipalHostname-.
  Future<void> establecerPcPrincipalHostname(String hostname) {
    return _guardar({'pc_principal_hostname': hostname});
  }
}
