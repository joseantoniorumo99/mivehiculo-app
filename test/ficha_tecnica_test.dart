/// La ficha técnica leída de una foto: lo que importa es no inventar. Un
/// bastidor con una letra mal leída, o una fecha de ITV tomada por la de
/// matriculación, contaminan el coche entero.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/ficha_tecnica.dart';

void main() {
  const marcas = ['Citroën', 'Peugeot', 'SEAT', 'Volkswagen', 'Toyota'];

  test('una ficha bien leída, con los códigos en línea', () {
    const texto = '''
TARJETA ITV  1234 KLM
A  1234KLM
B  15/03/2018
D.1  CITROEN
D.2  SXHMZ0
D.3  C3
E  VF7SXHMZ0JT123456
F.1  1640
P.1  1560
P.2  73
P.3  GASOLEO
S.1  5
''';
    final d = leerFichaTecnica(texto, marcasConocidas: marcas);
    expect(d.matricula, '1234 KLM');
    expect(d.marca, 'Citroën');
    expect(d.modelo, 'C3');
    expect(d.bastidor, 'VF7SXHMZ0JT123456');
    expect(d.cilindrada, 1560);
    expect(d.potenciaKw, 73);
    expect(d.potenciaCv, 99);
    expect(d.combustible, 'Diésel');
    expect(d.matriculacion, '2018-03-15');
    expect(d.anio, 2018);
    expect(d.leido, contains('bastidor'));
  });

  test('los códigos en una línea y el valor en la siguiente', () {
    const texto = '''
D.1
PEUGEOT
D.3
PEUGEOT 308
E
VF3LCBHZWHS123456
P.3
GASOLINA
B
02-06-2017
''';
    final d = leerFichaTecnica(texto, marcasConocidas: marcas);
    expect(d.marca, 'Peugeot');
    expect(d.modelo, '308');
    expect(d.bastidor, 'VF3LCBHZWHS123456');
    expect(d.combustible, 'Gasolina');
    expect(d.matriculacion, '2017-06-02');
  });

  test('las letras que un VIN no lleva se corrigen (O→0, I→1)', () {
    final d = leerFichaTecnica('E VF7SXHMZOJT1234S6');
    // "O" pasa a "0"; la S final no es dígito y los cuatro últimos deben serlo → no vale
    expect(d.bastidor, isNull);
    final d2 = leerFichaTecnica('E VF7SXHMZOJTI23456');
    expect(d2.bastidor, 'VF7SXHMZ0JT123456');
  });

  test('diecisiete letras seguidas no son un bastidor', () {
    final d = leerFichaTecnica('ABCDEFGHJKLMNPRST más texto');
    expect(d.bastidor, isNull);
  });

  test('sin código B, la fecha más antigua es la de matriculación, no la de la ITV', () {
    const texto = '''
Fecha ITV 10/05/2024
Próxima 10/05/2026
Matriculación 21/11/2016
''';
    final d = leerFichaTecnica(texto);
    expect(d.matriculacion, '2016-11-21');
  });

  test('sin código D.1, la marca se reconoce si está en el catálogo', () {
    final d = leerFichaTecnica('vehículo SEAT LEON 1.6 TDI', marcasConocidas: marcas);
    expect(d.marca, 'SEAT');
  });

  test('una foto sin nada legible no propone nada', () {
    final d = leerFichaTecnica('lorem ipsum 12 34');
    expect(d.hayAlgo, isFalse);
  });

  test('cilindrada por "cm3" cuando no hay código', () {
    final d = leerFichaTecnica('Motor 1598 cm3 GASOLINA');
    expect(d.cilindrada, 1598);
    expect(d.combustible, 'Gasolina');
  });

  test('un híbrido diésel y un eléctrico', () {
    expect(leerFichaTecnica('P.3 HIBRIDO DIESEL').combustible, 'Híbrido diésel');
    expect(leerFichaTecnica('P.3 ELECTRICO').combustible, 'Eléctrico');
    expect(leerFichaTecnica('P.3 GLP').combustible, 'GLP');
  });
}
