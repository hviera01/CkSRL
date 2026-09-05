import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/usuario_model.dart';
import '../../providers/usuarios_provider.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/data/modulos_menu.dart';
import '../../../../core/utils/mayusculas_input_formatter.dart';
import '../../../../core/widgets/campo_teclado_compacto.dart';
import '../../../negocio/data/negocio_model.dart';

class UsuarioFormDialog extends ConsumerStatefulWidget {
  final UsuarioModel? usuario;

  const UsuarioFormDialog({super.key, this.usuario});

  @override
  ConsumerState<UsuarioFormDialog> createState() => _UsuarioFormDialogState();
}

class _UsuarioFormDialogState extends ConsumerState<UsuarioFormDialog> {
  final _documentoController = TextEditingController();
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _claveController = TextEditingController();
  String _rol = Roles.empleado;
  bool _activo = true;
  bool _guardando = false;
  String? _error;
  // Solo se muestran/editan cuando _rol == Roles.encargado (ver build()).
  late Map<String, bool> _pantallasPermitidas;
  late Map<String, bool> _accionesPermitidas;

  @override
  void initState() {
    super.initState();
    _pantallasPermitidas = Map<String, bool>.from(widget.usuario?.pantallasPermitidas ?? {});
    _accionesPermitidas = Map<String, bool>.from(widget.usuario?.accionesPermitidas ?? {});
    if (widget.usuario != null) {
      _documentoController.text = widget.usuario!.documento;
      _nombreController.text = widget.usuario!.nombreCompleto;
      _correoController.text = widget.usuario!.correo;
      _rol = widget.usuario!.rol.isNotEmpty
          ? widget.usuario!.rol
          : Roles.empleado;
      _activo = widget.usuario!.estado;
    }
  }

  @override
  void dispose() {
    _documentoController.dispose();
    _nombreController.dispose();
    _correoController.dispose();
    _claveController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final documento = _documentoController.text.trim();
    final nombre = _nombreController.text.trim();
    final correo = _correoController.text.trim();
    final clave = _claveController.text.trim();
    final editando = widget.usuario != null;

    if (documento.isEmpty || nombre.isEmpty) {
      setState(() => _error = 'Documento y nombre completo son obligatorios');
      return;
    }
    if (!editando && clave.isEmpty) {
      setState(() => _error = 'La contraseña es obligatoria');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final repo = ref.read(usuarioRepositoryProvider);
      if (!editando) {
        await repo.crear(documento, nombre, correo, clave, _rol, _activo, _pantallasPermitidas, _accionesPermitidas);
      } else {
        await repo.actualizar(
          widget.usuario!.id,
          documento,
          nombre,
          correo,
          _rol,
          _activo,
          clave.isEmpty ? null : clave,
          _pantallasPermitidas,
          _accionesPermitidas,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Eliminar usuario',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Seguro que querés eliminar este usuario?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F1B3D),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _guardando = true);
    try {
      await ref.read(usuarioRepositoryProvider).eliminar(widget.usuario!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _guardando = false;
      });
    }
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFE8EAF0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.usuario != null;
    final tamano = MediaQuery.of(context).size;
    final esMovil = tamano.width < 500;
    final anchoDialog = esMovil ? tamano.width - 48 : 440.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Container(
          width: anchoDialog,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1B3D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.people_alt_outlined,
                      color: Color(0xFF0F1B3D),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      editando ? 'Editar Usuario' : 'Nuevo Usuario',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              CampoTecladoCompacto(
                controller: _documentoController,
                numerico: false,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _documentoController,
                  autofocus: true,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Documento'),
                ),
              ),
              const SizedBox(height: 14),
              CampoTecladoCompacto(
                controller: _nombreController,
                numerico: false,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _nombreController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Nombre completo'),
                ),
              ),
              const SizedBox(height: 14),
              CampoTecladoCompacto(
                controller: _correoController,
                numerico: false,
                child: TextField(
                  inputFormatters: [mayusculasInputFormatter],
                  autocorrect: false,
                  enableSuggestions: false,
                  controller: _correoController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _decoracion('Correo'),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _claveController,
                obscureText: true,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _decoracion(
                  editando ? 'Nueva contraseña (opcional)' : 'Contraseña',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _rol,
                decoration: _decoracion('Rol'),
                items: Roles.todos
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(
                          r,
                          style: GoogleFonts.poppins(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _rol = v ?? Roles.empleado),
              ),
              if (_rol == Roles.encargado) ...[
                const SizedBox(height: 18),
                _seccionPantallasPermitidas(),
                const SizedBox(height: 18),
                _seccionAccionesPermitidas(),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EAF0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      'Estado',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _activo ? 'Activo' : 'Inactivo',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _activo
                            ? const Color(0xFF16A34A)
                            : Colors.grey.shade500,
                      ),
                    ),
                    Switch(
                      value: _activo,
                      activeColor: const Color(0xFF16A34A),
                      onChanged: (v) => setState(() => _activo = v),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _error!,
                    style: GoogleFonts.poppins(
                      color: Colors.red.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  if (editando)
                    IconButton(
                      onPressed: _guardando ? null : _eliminar,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFF0F1B3D),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF0F1B3D,
                        ).withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _guardando ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.poppins(color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F1B3D),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          )
                        : Text(
                            'Guardar',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Permisos del rol Encargado ----------
  // Solo se renderizan (y solo se guardan) cuando _rol == Roles.encargado.
  // Reusa visualmente el patrón "fila con switch" de negocio_screen.dart,
  // aquí con Checkbox por ser una lista más larga de tildes.

  Widget _seccionPermisos({required String titulo, required String subtitulo, required Widget contenido}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 2),
          Text(subtitulo, style: GoogleFonts.poppins(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          contenido,
        ],
      ),
    );
  }

  Widget _seccionPantallasPermitidas() {
    return _seccionPermisos(
      titulo: 'Pantallas permitidas',
      subtitulo: 'Qué va a poder ver este usuario en el menú lateral.',
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: obtenerModulos().map((modulo) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(modulo.titulo, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F1B3D))),
                ...modulo.subModulos.map((sub) => _filaCheck(
                      valor: _pantallasPermitidas[sub.moduleKey] == true,
                      titulo: sub.titulo,
                      onChanged: (v) => setState(() => _pantallasPermitidas[sub.moduleKey] = v),
                    )),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _seccionAccionesPermitidas() {
    return _seccionPermisos(
      titulo: 'Acciones permitidas',
      subtitulo: 'Qué botones de crear/editar/eliminar (y acciones sensibles) va a poder usar.',
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: PermisosEspeciales.etiquetas.entries.map((entrada) {
          return _filaCheck(
            valor: _accionesPermitidas[entrada.key] == true,
            titulo: entrada.value,
            descripcion: PermisosEspeciales.descripciones[entrada.key],
            onChanged: (v) => setState(() => _accionesPermitidas[entrada.key] = v),
          );
        }).toList(),
      ),
    );
  }

  Widget _filaCheck({required bool valor, required String titulo, String? descripcion, required void Function(bool) onChanged}) {
    return InkWell(
      onTap: () => onChanged(!valor),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: valor,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: const Color(0xFF0F1B3D),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: GoogleFonts.poppins(fontSize: 12.5, color: const Color(0xFF1A1A1A))),
                    if (descripcion != null && descripcion.isNotEmpty)
                      Text(descripcion, style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
