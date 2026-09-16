/// Pruebas del panel del inicio: la serie de gasto y las cuatro cifras.
///
/// Defienden las dos reglas del panel: ningún porcentaje sin dos periodos
/// comparables de verdad, y ninguna gráfica plana fingiendo ser un dato.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/modelo.dart';
import 'package:mivehiculo/datos/panel.dart';

void main() {
  final hoy = DateTime(2026, 9, 16);
  Intervencion gasto(String fecha, double coste, {int? km}) =>
      Intervencion(vehiculoId: 'v1', fecha: fecha, tipo: 'otro', coste: coste, km: km);

  group('la serie de gasto', () {
    test('con el diario vacío está VACÍA, no plana', () {
      final s = serieGasto(const [], Periodo.anio, hoyPara: hoy);
      expect(s.vacia, isTrue);
      expect(s.grupos.length, 6);
      expect(s.nombrePrevio, isNull);
    });

    test('el año son seis bimestres', () {
      final s = serieGasto([gasto('2026-03-10', 300), gasto('2026-04-02', 100)], Periodo.anio, hoyPara: hoy);
      expect(s.grupos.length, 6);
      expect(s.grupos[1].actual, 400); // mar-abr
      expect(s.totalActual, 400);
      expect(s.vacia, isFalse);
    });

    test('sin nada del año anterior NO hay con qué comparar', () {
      final s = serieGasto([gasto('2026-03-10', 300)], Periodo.anio, hoyPara: hoy);
      expect(s.nombrePrevio, isNull);
    });

    test('con el año anterior sí, y el chip da un porcentaje', () {
      final s = serieGasto([gasto('2025-03-10', 200), gasto('2026-03-10', 300)], Periodo.anio, hoyPara: hoy);
      expect(s.nombrePrevio, '2025');
      expect(s.totalPrevio, 200);
      final m = metricasDe(Vehiculo(id: 'v1', km: 1000), [gasto('2025-03-10', 200), gasto('2026-03-10', 300)],
          Periodo.anio, hoyPara: hoy);
      expect(m[1].chip!.texto, '↑ 50 %');
      expect(m[1].chip!.tono, TonoChip.sube);
    });

    test('seis meses: cada grupo es un mes y el previo es el mismo mes del año pasado', () {
      final s = serieGasto([gasto('2026-08-10', 50), gasto('2025-08-10', 100)], Periodo.seisMeses, hoyPara: hoy);
      expect(s.grupos.length, 6);
      expect(s.grupos.last.etiqueta, 'sep');
      final agosto = s.grupos[4];
      expect(agosto.etiqueta, 'ago');
      expect(agosto.actual, 50);
      expect(agosto.previo, 100);
      expect(agosto.hayPrevio, isTrue);
    });

    test('todo: empieza en el primer año con datos, no seis atrás', () {
      final s = serieGasto([gasto('2024-01-10', 10)], Periodo.todo, hoyPara: hoy);
      expect(s.grupos.map((g) => g.etiqueta), ['24', '25', '26']);
    });

    test('el tope del eje es redondo', () {
      expect(topeRedondo(712), 750);
      expect(topeRedondo(1234), 1500);
      expect(topeRedondo(80), 80);
      expect(topeRedondo(0), 1);
    });
  });

  group('las cuatro cifras', () {
    test('sin km el valor es un guion, no un cero', () {
      final m = metricasDe(Vehiculo(id: 'v1'), const [], Periodo.anio, hoyPara: hoy);
      expect(m[0].valor, '—');
      expect(m[0].chip, isNull);
    });

    test('el chip de km solo sale con una anotación dentro del periodo', () {
      final v = Vehiculo(id: 'v1', km: 120000);
      final sinAnotacion = metricasDe(v, const [], Periodo.anio, hoyPara: hoy);
      expect(sinAnotacion[0].chip, isNull);
      final con = metricasDe(v, [gasto('2026-02-01', 10, km: 110000)], Periodo.anio, hoyPara: hoy);
      expect(con[0].chip!.texto, '+10.000 km');
    });

    test('la ITV aproximada lleva su nota', () {
      final m = metricasDe(Vehiculo(id: 'v1', anio: 2019), const [], Periodo.anio, hoyPara: hoy);
      expect(m[2].nota, 'Aproximada por el año');
      final exacta = metricasDe(Vehiculo(id: 'v1', anio: 2019, matriculacion: '2019-06'), const [], Periodo.anio, hoyPara: hoy);
      expect(exacta[2].nota, isNull);
      expect(exacta[2].valor, 'jun 2027');
    });

    test('el gasto igual que antes se dice con palabras', () {
      final m = metricasDe(Vehiculo(id: 'v1'), [gasto('2025-03-10', 300), gasto('2026-03-10', 300)],
          Periodo.anio, hoyPara: hoy);
      expect(m[1].chip!.texto, 'Igual que antes');
    });
  });
}
