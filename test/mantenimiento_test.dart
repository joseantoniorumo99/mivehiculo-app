/// Pruebas de lo que le toca al coche: ITV, avisos, AdBlue, huecos y formato.
///
/// Todas las fechas van FIJADAS con `hoyPara`: una prueba que depende del día
/// en que se ejecuta se pone roja sola un enero cualquiera y nadie sabe por
/// qué.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/mantenimiento.dart';
import 'package:mivehiculo/datos/modelo.dart';

void main() {
  final hoy = DateTime(2026, 9, 16);

  group('la ITV según la norma', () {
    test('con mes de matriculación se dice el mes', () {
      // Matriculado en junio de 2019: primera a los 4 años (jun 2023), luego
      // cada 2 (jun 2025, jun 2027). Hoy es sep 2026 → toca jun 2027.
      final itv = proximaItv(2019, '2019-06', hoyPara: hoy)!;
      expect(itv.exacta, isTrue);
      expect(itv.anio, 2027);
      expect(itv.mes, 6);
      expect(itv.faltan, 1);
    });

    test('a partir de los diez años es anual', () {
      // 2012-03: 2016, 2018, 2020, 2022 (10 años), luego 2023, 2024, 2025,
      // 2026 (mar, ya pasó) → mar 2027
      final itv = proximaItv(2012, '2012-03', hoyPara: hoy)!;
      expect(itv.anio, 2027);
      expect(itv.mes, 3);
    });

    test('sin mes, se aproxima por el año y se DICE que es aproximada', () {
      final itv = proximaItv(2019, '', hoyPara: hoy)!;
      expect(itv.exacta, isFalse);
      expect(itv.mes, isNull);
      expect(itv.anio, 2027);
      expect(itv.cuando, 'hacia 2027');
    });

    test('un coche que toca este año sale con faltan <= 0', () {
      // 2020-11: 2024, 2026 (nov, todavía no ha pasado) → faltan 0
      final itv = proximaItv(2020, '2020-11', hoyPara: hoy)!;
      expect(itv.anio, 2026);
      expect(itv.faltan, 0);
    });

    test('sin año no hay ITV que calcular', () {
      expect(proximaItv(null, '', hoyPara: hoy), isNull);
    });
  });

  group('los avisos', () {
    Vehiculo coche({int? km = 120000}) => Vehiculo(
          id: 'v1',
          marca: 'Opel',
          modelo: 'Astra',
          anio: 2019,
          matriculacion: '2019-06',
          combustible: 'Diésel',
          km: km,
        );

    test('solo la ITV cuando el diario está vacío', () {
      final lista = avisosDe(coche(), const [], hoyPara: hoy);
      expect(lista.map((a) => a.clave), contains('itv'));
      expect(lista.where((a) => a.clave == 'aceite'), isEmpty,
          reason: 'sin saber cuándo se cambió, no se avisa');
    });

    test('el aceite avisa cuando quedan pocos km desde el último cambio', () {
      final diario = [
        Intervencion(vehiculoId: 'v1', fecha: '2026-01-10', tipo: 'aceite', km: 108000),
      ];
      // 120000 - 108000 = 12000 recorridos; quedan 3000 de 15000 → media
      final a = avisosDe(coche(), diario, hoyPara: hoy).firstWhere((x) => x.clave == 'aceite');
      expect(a.detalle, contains('3.000 km'));
      expect(a.urgencia, Urgencia.baja);
    });

    test('vencido cuando se pasó del intervalo', () {
      final diario = [
        Intervencion(vehiculoId: 'v1', fecha: '2025-01-10', tipo: 'aceite', km: 100000),
      ];
      final a = avisosDe(coche(), diario, hoyPara: hoy).firstWhere((x) => x.clave == 'aceite');
      expect(a.urgencia, Urgencia.alta);
      expect(a.detalle, contains('Vencido'));
    });

    test('el aceite dentro de una revisión general cuenta como cambio', () {
      /// Una factura con cinco conceptos se etiqueta "revision", pero si dentro
      /// iba el aceite, el aviso del aceite tiene que darse por atendido.
      final diario = [
        Intervencion(
          vehiculoId: 'v1',
          fecha: '2026-06-01',
          tipo: 'revision',
          km: 118000,
          lineas: [Linea(concepto: 'Aceite 5W30', importe: 60, tipo: 'aceite')],
        ),
      ];
      final lista = avisosDe(coche(), diario, hoyPara: hoy);
      // 120000 - 118000 = 2000 → quedan 13000 > 35 % de 15000: no molesta
      expect(lista.where((a) => a.clave == 'aceite'), isEmpty);
      expect(ultimaDelTipo(diario, 'aceite'), isNotNull);
    });

    test('sin km en la anotación no se inventa un punto de partida', () {
      final diario = [
        Intervencion(vehiculoId: 'v1', fecha: '2024-01-10', tipo: 'aceite'),
      ];
      expect(avisosDe(coche(), diario, hoyPara: hoy).where((a) => a.clave == 'aceite'), isEmpty);
    });

    test('un diésel de 2019 lleva AdBlue y sale el aviso', () {
      final lista = avisosDe(coche(), const [], hoyPara: hoy);
      expect(lista.any((a) => a.tipo.contains('AdBlue')), isTrue);
    });

    test('van ordenados por urgencia', () {
      final diario = [
        Intervencion(vehiculoId: 'v1', fecha: '2025-01-10', tipo: 'aceite', km: 100000),
      ];
      final lista = avisosDe(coche(), diario, hoyPara: hoy);
      expect(lista.first.urgencia, Urgencia.alta);
      expect(lista.last.urgencia, Urgencia.baja);
    });
  });

  group('el AdBlue', () {
    test('un gasolina no lo lleva', () {
      expect(adBlueDeLaNorma('Gasolina', 2022).lleva, 'no');
    });
    test('un diésel de 2017 puede que sí', () {
      expect(adBlueDeLaNorma('Diésel', 2017).lleva, 'quizas');
    });
    test('lo que confirme el dueño manda sobre la norma', () {
      final v = Vehiculo(combustible: 'Diésel', anio: 2022, adBlue: 'no');
      expect(estadoAdBlue(v).lleva, 'no');
      expect(estadoAdBlue(v).detalle, 'Lo has confirmado tú.');
    });
  });

  group('los años sin documentar', () {
    test('un coche de 2019 con diario desde 2026 tiene siete huecos', () {
      final v = Vehiculo(anio: 2019);
      final diario = [Intervencion(vehiculoId: v.id, fecha: '2026-03-01')];
      expect(aniosSinDocumentar(v, diario, hoyPara: hoy), [2019, 2020, 2021, 2022, 2023, 2024, 2025]);
    });
    test('sin año no hay huecos que contar', () {
      expect(aniosSinDocumentar(Vehiculo(), const [], hoyPara: hoy), isEmpty);
    });
  });

  group('formato a la española', () {
    test('miles con punto', () {
      expect(conMiles(120000), '120.000');
      expect(conMiles(999), '999');
      expect(conMiles(1234567), '1.234.567');
      expect(conMiles(-3000), '-3.000');
    });
    test('euros con coma y sin decimales de relleno', () {
      expect(enEuros(700), '700 €');
      expect(enEuros(1234.5), '1.234,50 €');
      expect(enEuros(0.07), '0,07 €');
      expect(enEuros(null), '—');
    });
    test('fecha corta sin ambigüedad', () {
      expect(fechaCorta('2026-03-04'), '4 mar 2026');
      expect(fechaCorta('2019-06'), 'jun 2019');
      expect(fechaCorta('raro'), 'raro');
    });
  });
}
