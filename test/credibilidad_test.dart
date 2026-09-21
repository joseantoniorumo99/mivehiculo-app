/// Lo que hace creíble el historial: de dónde salió cada anotación y si el
/// coche está verificado (documento + posesión).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/modelo.dart';

void main() {
  group('credibilidad de una intervención', () {
    test('la que viene del informe del taller es del taller, tenga o no factura', () {
      final c = Cita(vehiculoId: 'v1', lugarId: 'x', fecha: '2026-09-01', informe: {'titulo': 'Frenos', 'total': 100});
      final i = c.informeComoIntervencion();
      expect(i.origen, 'taller');
      expect(i.credibilidad, Credibilidad.taller);
      expect(i.conPrueba, isTrue);
    });

    test('la del dueño con factura o fotos tiene prueba; sin nada, no', () {
      expect(Intervencion(vehiculoId: 'v1', fecha: '2026-01-01', factura: 'f1.jpg').credibilidad, Credibilidad.conPrueba);
      expect(Intervencion(vehiculoId: 'v1', fecha: '2026-01-01', fotos: ['a.jpg']).credibilidad, Credibilidad.conPrueba);
      final sin = Intervencion(vehiculoId: 'v1', fecha: '2026-01-01');
      expect(sin.credibilidad, Credibilidad.sinPrueba);
      expect(sin.conPrueba, isFalse);
    });

    test('el origen sobrevive al JSON y una anotación vieja es propia', () {
      final i = Intervencion(vehiculoId: 'v1', fecha: '2026-01-01', origen: 'taller');
      expect(Intervencion.deJson(i.aJson()).origen, 'taller');
      expect(Intervencion.deJson({'vehiculoId': 'v1', 'fecha': '2026-01-01'}).origen, 'propia');
    });
  });

  group('coche verificado', () {
    test('ficha y OBD con el mismo bastidor', () {
      final v = Vehiculo(bastidorFicha: 'VF7SXHMZ0JT123456', bastidorObd: 'VF7SXHMZ0JT123456');
      expect(v.verificado, isTrue);
      expect(v.bastidoresDiscrepan, isFalse);
      expect(v.pasosVerificacion, 2);
    });

    test('solo uno de los dos no verifica, y se sabe cuál falta', () {
      expect(Vehiculo(bastidorObd: 'VF7SXHMZ0JT123456').verificado, isFalse);
      expect(Vehiculo(bastidorObd: 'VF7SXHMZ0JT123456').pasosVerificacion, 1);
      expect(Vehiculo().pasosVerificacion, 0);
    });

    test('dos bastidores distintos discrepan, no verifican', () {
      final v = Vehiculo(bastidorFicha: 'VF7SXHMZ0JT123456', bastidorObd: 'WVWZZZ1KZAW000001');
      expect(v.verificado, isFalse);
      expect(v.bastidoresDiscrepan, isTrue);
    });

    test('los bastidores sobreviven al JSON', () {
      final v = Vehiculo(bastidor: 'A', bastidorFicha: 'B', bastidorObd: 'C');
      final j = Vehiculo.deJson(v.aJson());
      expect(j.bastidorFicha, 'B');
      expect(j.bastidorObd, 'C');
    });
  });
}
