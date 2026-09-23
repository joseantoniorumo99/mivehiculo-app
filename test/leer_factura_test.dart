/// El intérprete de facturas: lo que importa es no confundir 1.234,56 con
/// 1,23, ni la base con el total, ni proponer nada de un texto que no es una
/// factura. Misma lógica que assets/leer-factura.js en la web.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/leer_factura.dart';

const facturaCompleta = '''
TALLERES HERMANOS RUIZ S.L.
C/ Torneo, 48 - 41002 Sevilla
CIF B-91234567   Tel. 954 000 000
FACTURA Nº 2026/0412
Fecha: 14/03/2026
Cliente: José García
Vehículo: SEAT León 1.6 TDI   Matrícula 4821 KYT
Kilometraje: 87.450 km

Concepto                         Cant.  Precio   Importe
Diagnosis electrónica              1     45,00     45,00
Motor de arranque Valeo            1    210,50    210,50
Brazo de suspensión delantero      1    138,70    138,70
Aceite 5W30 Castrol 5L             1     52,00     52,00
Mano de obra                       3     44,00    132,00

Base imponible                                     578,20
IVA 21 %                                           121,42
TOTAL FACTURA                                      699,62 €
Forma de pago: tarjeta   Vencimiento: 14/04/2026
''';

void main() {
  final hoy = DateTime.utc(2026, 9, 23);

  group('números españoles', () {
    test('coma decimal y punto de miles', () {
      expect(aNumero('1.234,56'), 1234.56);
      expect(aNumero('699,62 €'), 699.62);
      expect(aNumero('45,00'), 45.0);
    });
    test('punto decimal a la inglesa solo si es el único y con dos cifras', () {
      expect(aNumero('45.00'), 45.0);
      expect(aNumero('87.450'), 87450);
      expect(aNumero('1.234.567'), 1234567);
    });
    test('vacío o basura es null', () {
      expect(aNumero(''), isNull);
      expect(aNumero('abc'), isNull);
    });
  });

  group('la factura entera', () {
    final r = leerFactura(facturaCompleta, hoy: hoy);
    final d = r.datos!;

    test('se reconoce como factura', () => expect(r.ok, isTrue));
    test('la fecha es la de emisión, no el vencimiento', () => expect(d.fecha, '2026-03-14'));
    test('el importe es el TOTAL, no la base ni el IVA', () => expect(d.importe, 699.62));
    test('el taller sale de la cabecera sin la forma jurídica', () => expect(d.taller, 'TALLERES HERMANOS RUIZ'));
    test('los km salen del kilometraje', () => expect(d.km, 87450));
    test('el desglose trae las cinco líneas con su importe', () {
      expect(d.lineas.length, 5);
      expect(d.lineas.first.concepto, 'Diagnosis electrónica');
      expect(d.lineas.first.importe, 45.0);
      expect(d.lineas[1].tipo, 'bateria'); // motor de arranque
      expect(d.lineas[3].tipo, 'aceite');
      expect(d.lineas.last.concepto, 'Mano de obra');
    });
    test('con varias cosas distintas la etiqueta es revisión general', () => expect(d.tipo, 'revision'));
    test('el desglose suma la base, así que el IVA va aparte', () => expect(d.iva, 'sin'));
  });

  group('aceite + filtro de aceite es un cambio de aceite', () {
    const texto = '''
AUTOS PEPE
Factura 77   Fecha 02/02/2026
Aceite 5W30 4L                 38,00
Filtro de aceite               12,50
Mano de obra                   25,00
Total                          75,50 €
''';
    final d = leerFactura(texto, hoy: hoy).datos!;
    test('tipo aceite', () => expect(d.tipo, 'aceite'));
    test('total', () => expect(d.importe, 75.5));
    test('el desglose suma el total: sin IVA aparte', () => expect(d.iva, 'con'));
  });

  test('un arranque y un brazo de suspensión empatan: revisión, no batería', () {
    const texto = '''
TALLER X   Factura 1   Fecha 02/02/2026
Motor de arranque              210,00
Brazo de suspensión            138,00
Mano de obra                    90,00
TOTAL                          438,00 €
''';
    expect(leerFactura(texto, hoy: hoy).datos!.tipo, 'revision');
  });

  test('fecha larga y sin línea de total: la suma del desglose', () {
    const texto = '''
NEUMÁTICOS SUR
Albarán 12 de mayo de 2025
Neumático Michelin 205/55       89,90
Neumático Michelin 205/55       89,90
Equilibrado                     12,00
IVA incluido en euros
''';
    final d = leerFactura(texto, hoy: hoy).datos!;
    expect(d.fecha, '2025-05-12');
    expect(d.importe, 191.8);
    expect(d.tipo, 'rueda');
  });

  test('una fecha del futuro se descarta', () {
    expect(fechaDeFactura('Factura 30/12/2030 total 10 €', hoy: hoy), isNull);
  });

  test('sin señales de factura no se propone nada', () {
    final r = leerFactura('Lista de la compra: leche, pan, huevos, 3 manzanas y un melón', hoy: hoy);
    expect(r.ok, isFalse);
    expect(r.error, contains('no parece una factura'));
  });

  test('con menos de veinte caracteres no hay nada que leer', () {
    expect(leerFactura('total 5', hoy: hoy).ok, isFalse);
  });

  test('un número solo de kilómetros pequeño no es un cuentakilómetros', () {
    expect(kmDeFactura('Desplazamiento 12 km'), isNull);
    expect(kmDeFactura('Lectura 123.456 km'), 123456);
  });
}
