/// La comparación de versiones: es lo que decide si se avisa de una nueva.
/// Comparar "1.10.0" con "1.9.3" como texto diría que la 1.9.3 es más nueva.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/actualizacion.dart';

void main() {
  test('número a número, no como texto', () {
    expect(Actualizacion.compararVersiones('1.10.0', '1.9.3'), greaterThan(0));
    expect(Actualizacion.compararVersiones('1.1.0', '1.0.0'), greaterThan(0));
    expect(Actualizacion.compararVersiones('1.1.0', '1.1.0'), 0);
    expect(Actualizacion.compararVersiones('1.0.9', '1.1.0'), lessThan(0));
  });

  test('el número de build no cuenta: 1.1.0+2 es la 1.1.0', () {
    expect(Actualizacion.compararVersiones('1.1.0+2', '1.1.0'), 0);
    expect(Actualizacion.compararVersiones('1.2', '1.1.0'), greaterThan(0));
  });
}
