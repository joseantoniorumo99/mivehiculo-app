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

  /// La tabla es mensual: la última serie de cada mes. Una serie cae en el
  /// primer mes cuyo final la alcanza. Antes se interpolaba entre una ancla
  /// por año y un C3 de 2018 salió como de 2020.
  test('la última serie de un mes cae en ese mes', () {
    final f = fechaDeMatricula('9999 KHG')!; // fin de enero de 2018
    expect(f.iso, '2018-01');
    expect(f.exacta, isTrue);
  });

  test('la serie siguiente ya es el mes siguiente', () {
    expect(fechaDeMatricula('0000 KHH')!.iso, '2018-02');
    expect(fechaDeMatricula('0000 KTK')!.iso, '2019-02'); // KTJ cerró enero
  });

  test('una serie de mitad de año cae en su mes', () {
    final f = fechaDeMatricula('4821 KYT')!; // KYN cerró junio de 2019
    expect(f.iso, '2019-07');
  });

  test('una serie más nueva que la tabla se extrapola y se dice', () {
    final f = fechaDeMatricula('0000 NSB')!; // detrás de NPZ (abr 2026)
    expect(f.anio, 2026);
    expect(f.exacta, isFalse);
  });

  test('el arranque del sistema es septiembre de 2000', () {
    expect(fechaDeMatricula('0000 BBB')!.iso, '2000-09');
  });

  test('la posición en la secuencia es base 20', () {
    expect(indiceDeSerie('BBB'), 0);
    expect(indiceDeSerie('BBC'), 1);
    expect(indiceDeSerie('BCB'), 20);
    expect(indiceDeSerie('AAA'), isNull);
  });
}
