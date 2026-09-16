/// La matrícula española dice cuándo se matriculó el coche.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/matricula.dart';

void main() {
  test('reconoce el formato vigente y lo formatea', () {
    expect(partesDeMatricula('4821kyt')!.serie, 'KYT');
    expect(formatearMatricula('4821-kyt'), '4821 KYT');
    expect(partesDeMatricula('SE-1234-AB'), isNull); // provincial, anterior a 2000
    expect(partesDeMatricula('1234 ABE'), isNull); // la E no es consonante del sistema
  });

  test('las anclas devuelven exactamente su enero', () {
    final f = fechaDeMatricula('0000 KTK')!; // primera serie de 2019
    expect(f.anio, 2019);
    expect(f.mes, 1);
    expect(f.iso, '2019-01');
  });

  test('una serie entre dos anclas cae en el año que toca', () {
    final f = fechaDeMatricula('4821 KYT')!; // entre KTK (2019) y LFJ (2020)
    expect(f.anio, 2019);
    expect(f.mes, greaterThan(1));
  });

  test('una serie más nueva que la última ancla sigue el ritmo', () {
    final f = fechaDeMatricula('0000 NLB')!; // detrás de NKG (2026)
    expect(f.anio, 2026);
  });

  test('las series anteriores al arranque del sistema no se datan', () {
    expect(fechaDeMatricula('0000 BBB')!.anio, 2000);
  });

  test('la posición en la secuencia es base 20', () {
    expect(indiceDeSerie('BBB'), 0);
    expect(indiceDeSerie('BBC'), 1);
    expect(indiceDeSerie('BCB'), 20);
    expect(indiceDeSerie('AAA'), isNull);
  });
}
