class PermisosMenu {
  static const List<String> modulosEmpleado = [
    'ventas',
    'ventas_credito',
    'clientes',
    'compras',
    'compras_credito',
    'proveedores',
    'reporte_ventas',
    'reporte_compras',
    'egresos',
    'caja',
  ];

  static bool tieneAcceso(String rol, String modulo) {
    if (rol == 'Administrador') return true;
    return modulosEmpleado.contains(modulo);
  }
}