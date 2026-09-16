/// Cómo llegan el almacén y la nube a cada pantalla.
///
/// Un InheritedWidget y punto. No hace falta un paquete de gestión de estado
/// para dos objetos que viven toda la vida de la app: las pantallas escuchan
/// con `ListenableBuilder` al que les interese y se repintan cuando cambia.
library;

import 'package:flutter/widgets.dart';

import 'datos/actualizacion.dart';
import 'datos/almacen.dart';
import 'datos/nube.dart';

class Estado extends InheritedWidget {
  final Almacen almacen;
  final Nube nube;
  final Actualizacion actualizacion;

  const Estado({
    super.key,
    required this.almacen,
    required this.nube,
    required this.actualizacion,
    required super.child,
  });

  static Estado de(BuildContext context) {
    final e = context.getInheritedWidgetOfExactType<Estado>();
    assert(e != null, 'No hay Estado por encima de este widget');
    return e!;
  }

  @override
  bool updateShouldNotify(Estado old) =>
      almacen != old.almacen || nube != old.nube || actualizacion != old.actualizacion;
}

extension EstadoEnContexto on BuildContext {
  Almacen get almacen => Estado.de(this).almacen;
  Nube get nube => Estado.de(this).nube;
  Actualizacion get actualizacion => Estado.de(this).actualizacion;
}
