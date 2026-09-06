import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data/base_repository.dart';
import 'cierre_caja_model.dart';
import '../../egresos/data/egreso_repository.dart';

class EstadoCaja {
  final DateTime fechaDesde;
  final double montoInicial;

  const EstadoCaja({required this.fechaDesde, required this.montoInicial});
}

class CierreCajaRepository with ConRedMixin {
  final _db = Supabase.instance.client;
  final _egresoRepository = EgresoRepository();

  Future<EstadoCaja> obtenerEstadoCaja() {
    return conRed(() async {
      final filas = await _db.from('caja_estado').select().eq('id', 1).limit(1);
      if (filas.isEmpty) {
        final hoy = DateTime.now();
        return EstadoCaja(fechaDesde: DateTime(hoy.year, hoy.month, hoy.day), montoInicial: 0);
      }
      final data = filas.first;
      return EstadoCaja(
        fechaDesde: data['fecha_desde'] == null ? DateTime.now() : DateTime.parse(data['fecha_desde'] as String),
        montoInicial: (data['monto_inicial'] ?? 0).toDouble(),
      );
    });
  }

  Future<void> guardarMontoInicial(DateTime fechaDesde, double montoInicial, String usuario) {
    return conRed(() => _db.from('caja_estado').upsert({
          'id': 1,
          'fecha_desde': fechaDesde.toIso8601String(),
          'monto_inicial': montoInicial,
          'usuario_responsable': usuario,
          'actualizado_en': DateTime.now().toIso8601String(),
        }));
  }

  Future<TotalesCaja> calcularTotales(DateTime inicio, DateTime finInclusive) async {
    final movimientos = await _egresoRepository.obtenerLibroFinanciero(inicio, finInclusive);

    double ingresosEfectivo = 0, ingresosTarjeta = 0, ingresosTransferencia = 0;
    double egresosEfectivo = 0, egresosTransferencia = 0;

    for (final m in movimientos) {
      if (m.ingreso > 0) {
        switch (m.metodoPago) {
          case 'Efectivo':
            ingresosEfectivo += m.ingreso;
            break;
          case 'Tarjeta':
            ingresosTarjeta += m.ingreso;
            break;
          case 'Transferencia':
            ingresosTransferencia += m.ingreso;
            break;
        }
      } else if (m.egreso > 0) {
        switch (m.metodoPago) {
          case 'Efectivo':
            egresosEfectivo += m.egreso;
            break;
          case 'Transferencia':
            egresosTransferencia += m.egreso;
            break;
        }
      }
    }

    return TotalesCaja(
      ingresosEfectivo: ingresosEfectivo,
      ingresosTarjeta: ingresosTarjeta,
      ingresosTransferencia: ingresosTransferencia,
      egresosEfectivo: egresosEfectivo,
      egresosTransferencia: egresosTransferencia,
    );
  }

  /// Inserta el cierre y arranca el turno siguiente con el totalReal de
  /// este, en una sola operación atómica — ver `registrar_cierre_caja` en
  /// supabase/schema.sql.
  Future<void> registrarCierre(CierreCajaModel cierre) {
    // El siguiente periodo arranca a las 00:00 del mismo día calendario en
    // que se registra el cierre (no en el minuto exacto), para que parta de
    // un día completo en vez de un instante arbitrario del día -mismo
    // ajuste que CierreCajaRepository.registrarCierre en Lopsi (Firestore)-.
    // Antes se guardaba fechaFin tal cual: si el cierre se hacía a media
    // mañana, ese instante exacto (no medianoche) quedaba como inicio del
    // turno siguiente. Se calcula acá, en hora local del dispositivo (no con
    // date_trunc en el servidor, que trabaja en UTC y correría el día para
    // negocios en otro huso horario), y se manda ya resuelto al RPC.
    final finCierre = cierre.fechaFin;
    final siguientePeriodo = DateTime(finCierre.year, finCierre.month, finCierre.day);
    return conRed(() => _db.rpc('registrar_cierre_caja', params: {
          'payload': {
            'fechaInicio': cierre.fechaInicio.toIso8601String(),
            'fechaFin': cierre.fechaFin.toIso8601String(),
            'siguientePeriodo': siguientePeriodo.toIso8601String(),
            'montoInicial': cierre.montoInicial,
            'ingresosEfectivo': cierre.ingresosEfectivo,
            'ingresosTarjeta': cierre.ingresosTarjeta,
            'ingresosTransferencia': cierre.ingresosTransferencia,
            'egresosEfectivo': cierre.egresosEfectivo,
            'egresosTransferencia': cierre.egresosTransferencia,
            'totalCalculadoEfectivo': cierre.totalCalculadoEfectivo,
            'totalTransferencia': cierre.totalTransferencia,
            'granTotal': cierre.granTotal,
            'totalReal': cierre.totalReal,
            'diferencia': cierre.diferencia,
            'usuarioResponsable': cierre.usuarioResponsable,
            'observaciones': cierre.observaciones,
          },
        }));
  }

  Stream<List<CierreCajaModel>> obtenerHistorial() {
    return conRedStream(() => _db
        .from('cierres_caja')
        .stream(primaryKey: ['id'])
        .order('fecha_fin', ascending: false)
        .map((filas) => filas.map((d) => CierreCajaModel.fromMap(d['id'] as String, d)).toList()));
  }
}
