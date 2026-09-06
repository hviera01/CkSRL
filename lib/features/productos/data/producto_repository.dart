import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'producto_model.dart';
import 'producto_import_service.dart';
import 'historial_stock_model.dart';
import 'historial_precio_compra_model.dart';
import 'historial_venta_producto_model.dart';

class ResumenImportacionProductos {
  final int creados;
  final int actualizados;
  final int categoriasCreadas;

  ResumenImportacionProductos({required this.creados, required this.actualizados, required this.categoriasCreadas});
}

class ProductoRepository with ConRedMixin {
  final _db = Supabase.instance.client;

  Stream<List<ProductoModel>> obtenerProductos() {
    return conRedStream(() => _db
        .from('productos')
        .stream(primaryKey: ['id'])
        .order('nombre')
        .map((filas) => filas.map((d) => ProductoModel.fromMap(d['id'] as String, d)).toList()));
  }

  String _generarCodigo() {
    final ahora = DateTime.now().millisecondsSinceEpoch.toString();
    return 'PROD-${ahora.substring(ahora.length - 8)}';
  }

  Future<ProductoModel> crear({
    required String codigo,
    required String codigoBarras,
    required String nombre,
    required String descripcion,
    required String idCategoria,
    required double stock,
    required double precioCompra,
    required double precioVenta,
    required double precioVenta2,
    required double precioVenta3,
    required bool estado,
    String imagenUrl = '',
    bool esCombo = false,
    List<ComponenteProductoModel> componentes = const [],
  }) {
    return conRed(() async {
      var codigoFinal = codigo.trim();
      if (codigoFinal.isEmpty) {
        codigoFinal = _generarCodigo();
      } else {
        final existe = await _db.from('productos').select('id').eq('codigo', codigoFinal).limit(1);
        if (existe.isNotEmpty) {
          throw Exception('Ya existe un producto con ese código');
        }
      }
      final fila = await _db.from('productos').insert({
        'codigo': codigoFinal,
        'codigo_barras': codigoBarras.trim(),
        'nombre': nombre.trim(),
        'descripcion': descripcion.trim(),
        'id_categoria': idCategoria.isEmpty ? null : idCategoria,
        'stock': stock,
        'precio_compra': precioCompra,
        'precio_venta': precioVenta,
        'precio_venta2': precioVenta2,
        'precio_venta3': precioVenta3,
        'estado': estado,
        'imagen_url': imagenUrl,
        'es_combo': esCombo,
        'componentes': componentes.map((c) => c.toMap()).toList(),
      }).select().single();
      final id = fila['id'] as String;

      // Si el producto se crea con existencia inicial, esa cantidad también
      // necesita su propio lote de costo — si no, al venderla no hay lote
      // que consumir por FIFO y termina costeándose con el precioCompra
      // vigente en el momento de la venta en vez del costo real inicial.
      if (stock > 0) {
        await _db.from('producto_lotes_costo').insert({
          'id_producto': id,
          'cantidad_original': stock,
          'cantidad_restante': stock,
          'costo_unitario': precioCompra,
          'fecha': DateTime.now().toIso8601String(),
          'origen': 'inicial',
        });
      }
      return ProductoModel(
        id: id,
        codigo: codigoFinal,
        codigoBarras: codigoBarras.trim(),
        nombre: nombre.trim(),
        descripcion: descripcion.trim(),
        idCategoria: idCategoria,
        stock: stock,
        precioCompra: precioCompra,
        precioVenta: precioVenta,
        precioVenta2: precioVenta2,
        precioVenta3: precioVenta3,
        estado: estado,
        imagenUrl: imagenUrl,
        esCombo: esCombo,
        componentes: componentes,
      );
    });
  }

  Future<void> actualizar({
    required String id,
    required String codigo,
    required String codigoBarras,
    required String nombre,
    required String descripcion,
    required String idCategoria,
    required double precioCompra,
    required double precioVenta,
    required double precioVenta2,
    required double precioVenta3,
    required bool estado,
    String imagenUrl = '',
    // Solo se envían al editar un combo ya existente: el tipo de producto no
    // se puede cambiar después de creado, pero la receta de componentes sí.
    bool? esCombo,
    List<ComponenteProductoModel>? componentes,
  }) {
    return conRed(() async {
      final codigoFinal = codigo.trim().isEmpty ? _generarCodigo() : codigo.trim();
      final existe = await _db.from('productos').select('id').eq('codigo', codigoFinal).limit(2);
      final duplicado = existe.any((d) => d['id'] != id);
      if (duplicado) {
        throw Exception('Ya existe un producto con ese código');
      }
      final datos = <String, dynamic>{
        'codigo': codigoFinal,
        'codigo_barras': codigoBarras.trim(),
        'nombre': nombre.trim(),
        'descripcion': descripcion.trim(),
        'id_categoria': idCategoria.isEmpty ? null : idCategoria,
        'precio_compra': precioCompra,
        'precio_venta': precioVenta,
        'precio_venta2': precioVenta2,
        'precio_venta3': precioVenta3,
        'estado': estado,
        'imagen_url': imagenUrl,
      };
      if (esCombo != null) datos['es_combo'] = esCombo;
      if (componentes != null) datos['componentes'] = componentes.map((c) => c.toMap()).toList();
      await _db.from('productos').update(datos).eq('id', id);
    });
  }

  Future<void> eliminar(String id) {
    return conRed(() => _db.from('productos').delete().eq('id', id));
  }

  /// Crea o actualiza en lote los productos de una importación desde Excel.
  Future<ResumenImportacionProductos> importarProductos(List<FilaImportacionProducto> filas) {
    return conRed(() async {
      final productosExistentes = await _db.from('productos').select('id, codigo, es_combo');
      final idPorCodigo = <String, String>{};
      for (final d in productosExistentes) {
        if (d['es_combo'] == true) continue;
        final codigo = (d['codigo'] as String? ?? '').trim().toLowerCase();
        if (codigo.isNotEmpty) idPorCodigo[codigo] = d['id'] as String;
      }

      final categoriasExistentes = await _db.from('categorias').select('id, descripcion');
      final idCategoriaPorNombre = <String, String>{};
      for (final d in categoriasExistentes) {
        final descripcion = (d['descripcion'] as String? ?? '').trim().toLowerCase();
        if (descripcion.isNotEmpty) idCategoriaPorNombre[descripcion] = d['id'] as String;
      }

      var creados = 0, actualizados = 0, categoriasCreadas = 0;
      final categoriasNuevas = <Map<String, dynamic>>[];
      final productosActualizar = <Map<String, dynamic>>[];
      final productosCrear = <Map<String, dynamic>>[];

      for (final fila in filas) {
        final nombreCategoriaNorm = fila.categoria.trim().toLowerCase();
        var idCategoria = idCategoriaPorNombre[nombreCategoriaNorm];
        if (idCategoria == null) {
          idCategoria = 'nueva:$nombreCategoriaNorm';
          if (!idCategoriaPorNombre.containsValue(idCategoria)) {
            categoriasNuevas.add({'descripcion': fila.categoria.trim(), 'estado': true});
            idCategoriaPorNombre[nombreCategoriaNorm] = idCategoria;
            categoriasCreadas++;
          }
        }

        final codigoNorm = fila.codigo.trim().toLowerCase();
        final idExistente = codigoNorm.isEmpty ? null : idPorCodigo[codigoNorm];

        final datosComunes = {
          'nombre': fila.nombre.trim(),
          'descripcion': fila.descripcion.trim(),
          'stock': fila.stock,
          'precio_compra': fila.precioCompra,
          'precio_venta': fila.precioVenta,
          'estado': fila.estado,
        };

        if (idExistente != null) {
          productosActualizar.add({'id': idExistente, 'id_categoria_clave': idCategoria, ...datosComunes, 'codigo': fila.codigo.trim()});
          actualizados++;
        } else {
          productosCrear.add({'id_categoria_clave': idCategoria, ...datosComunes, 'codigo': fila.codigo.trim(), 'codigo_barras': '', 'precio_venta2': 0.0, 'precio_venta3': 0.0});
          creados++;
        }
      }

      // Crea primero las categorías nuevas (si hubo), y resuelve sus ids
      // reales antes de tocar productos.
      final idRealPorClave = <String, String>{};
      if (categoriasNuevas.isNotEmpty) {
        final insertadas = await _db.from('categorias').insert(categoriasNuevas).select('id, descripcion');
        for (final c in insertadas) {
          final clave = 'nueva:${(c['descripcion'] as String).trim().toLowerCase()}';
          idRealPorClave[clave] = c['id'] as String;
        }
      }
      String resolverCategoria(String clave) => idRealPorClave[clave] ?? clave;

      for (final p in productosActualizar) {
        final id = p.remove('id') as String;
        final claveCategoria = p.remove('id_categoria_clave') as String;
        await _db.from('productos').update({...p, 'id_categoria': resolverCategoria(claveCategoria)}).eq('id', id);
      }
      if (productosCrear.isNotEmpty) {
        final filasInsertar = productosCrear.map((p) {
          final claveCategoria = p.remove('id_categoria_clave') as String;
          return {...p, 'id_categoria': resolverCategoria(claveCategoria)};
        }).toList();
        await _db.from('productos').insert(filasInsertar);
      }

      return ResumenImportacionProductos(creados: creados, actualizados: actualizados, categoriasCreadas: categoriasCreadas);
    });
  }

  /// Ajusta el stock a mano (Inventario) — ver registrar_ingreso_stock en
  /// supabase/schema.sql: hace atómicamente lo que en Firestore era una
  /// Transaction (stock + historial + lote de costo).
  Future<void> registrarIngreso({
    required String id,
    required double cantidad,
    required double costoUnitario,
    required String usuario,
    String motivo = '',
  }) {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a 0');
    return conRed(() => _db.rpc('registrar_ingreso_stock', params: {
          'payload': {'id': id, 'cantidad': cantidad, 'costoUnitario': costoUnitario, 'usuario': usuario, 'motivo': motivo},
        }));
  }

  Future<void> registrarSalida({
    required String id,
    required double cantidad,
    String? idLote,
    required String usuario,
    String motivo = '',
  }) {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a 0');
    return conRed(() => _db.rpc('registrar_salida_stock', params: {
          'payload': {'id': id, 'cantidad': cantidad, 'idLote': idLote, 'usuario': usuario, 'motivo': motivo},
        }));
  }

  /// Descuenta stock de forma atómica, registrando el movimiento en el
  /// historial. Usado para reembasados.
  Future<bool> descontarStock({
    required String id,
    required double cantidad,
    required String usuario,
    required String motivo,
  }) async {
    try {
      await _db.rpc('descontar_stock', params: {
        'payload': {'id': id, 'cantidad': cantidad, 'usuario': usuario, 'motivo': motivo},
      }).timeout(const Duration(seconds: 12));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<HistorialStockModel>> obtenerHistorialStock(String idProducto) {
    return conRed(() async {
      final filas = await _db.from('producto_historial_stock').select().eq('id_producto', idProducto).order('fecha', ascending: false);
      return filas.map((d) => HistorialStockModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  Future<List<HistorialPrecioCompraModel>> obtenerHistorialPreciosCompra(String idProducto) {
    return conRed(() async {
      final filas = await _db.from('producto_historial_precios_compra').select().eq('id_producto', idProducto).order('fecha');
      return filas.map((d) => HistorialPrecioCompraModel.fromMap(d['id'] as String, d)).toList();
    });
  }

  Future<List<HistorialVentaProductoModel>> obtenerHistorialVentas(String idProducto) {
    return conRed(() async {
      final filas = await _db.from('producto_historial_ventas').select().eq('id_producto', idProducto).order('fecha');
      return filas.map((d) => HistorialVentaProductoModel.fromMap(d['id'] as String, d)).toList();
    });
  }
}
