/// Los consejos de mejoras: aplican al coche que es, y no repiten lo que ya
/// consta hecho.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/consejos.dart';
import 'package:mivehiculo/datos/modelo.dart';

void main() {
  final hoy = DateTime(2026, 9, 18);

  test('sin coche no hay consejos', () {
    expect(consejosPara(null, const [], hoyPara: hoy), isEmpty);
  });

  test('un diésel con kilómetros recibe el FAP el primero', () {
    final coche = Vehiculo(combustible: 'Diésel', anio: 2018, km: 98000);
    final c = consejosPara(coche, const [], hoyPara: hoy);
    expect(c.first.titulo, contains('filtro de partículas'));
    expect(c.map((x) => x.titulo), contains('Limpieza de inyectores'));
    // Sin AdBlue confirmado y de 2018, no se aconseja AdBlue
    expect(c.map((x) => x.titulo).any((t) => t.contains('AdBlue')), isFalse);
    // Y nada de bujías: eso es de gasolina
    expect(c.map((x) => x.titulo).any((t) => t.contains('Bujías')), isFalse);
  });

  test('un diésel de 2020 lleva AdBlue por la norma y se le aconseja el bueno', () {
    final coche = Vehiculo(combustible: 'Diésel', anio: 2020, km: 30000);
    final c = consejosPara(coche, const [], hoyPara: hoy);
    expect(c.map((x) => x.titulo).any((t) => t.contains('AdBlue')), isTrue);
    // Con 30.000 km no toca limpiar el FAP
    expect(c.map((x) => x.titulo).any((t) => t.contains('partículas')), isFalse);
  });

  test('un gasolina con 70.000 km sin bujías anotadas: bujías; con ellas recientes, no', () {
    final coche = Vehiculo(id: 'v1', combustible: 'Gasolina', anio: 2016, km: 70000);
    expect(consejosPara(coche, const [], hoyPara: hoy).map((x) => x.titulo), contains('Bujías nuevas'));
    final conBujias = [
      Intervencion(vehiculoId: 'v1', fecha: '2026-03-01', tipo: 'revision', titulo: 'Revisión', lineas: [Linea(concepto: 'Juego de bujías', importe: 60)]),
    ];
    expect(consejosPara(coche, conBujias, hoyPara: hoy).map((x) => x.titulo), isNot(contains('Bujías nuevas')));
  });

  test('lo hecho hace poco no se aconseja: líquido de frenos y alineado', () {
    final coche = Vehiculo(id: 'v1', combustible: 'Gasolina', anio: 2015, km: 120000);
    final hecho = [
      Intervencion(vehiculoId: 'v1', fecha: '2026-06-10', tipo: 'freno', titulo: 'Cambio del líquido de frenos'),
      Intervencion(vehiculoId: 'v1', fecha: '2026-05-02', tipo: 'rueda', titulo: 'Ruedas', nota: 'Alineado incluido'),
    ];
    final titulos = consejosPara(coche, hecho, hoyPara: hoy).map((x) => x.titulo).toList();
    expect(titulos, isNot(contains('Cambio del líquido de frenos')));
    expect(titulos, isNot(contains('Alineado y presiones')));
  });

  test('híbrido y eléctrico tienen los suyos', () {
    final h = consejosPara(Vehiculo(combustible: 'Híbrido', anio: 2017, km: 90000), const [], hoyPara: hoy);
    expect(h.map((x) => x.titulo), contains('Revisión de la batería híbrida'));
    final e = consejosPara(Vehiculo(combustible: 'Eléctrico', anio: 2021, km: 40000), const [], hoyPara: hoy);
    expect(e.first.titulo, contains('salud de la batería'));
    // Un eléctrico no cambia aceite ni filtro de aire del motor
    expect(e.map((x) => x.titulo).any((t) => t.contains('Aceite')), isFalse);
  });

  test('cada consejo lleva motivo y ganancia escritos, y va ordenado', () {
    final c = consejosPara(Vehiculo(combustible: 'Diésel', anio: 2014, km: 150000), const [], hoyPara: hoy);
    expect(c, isNotEmpty);
    for (final x in c) {
      expect(x.motivo.length, greaterThan(20));
      expect(x.gana.length, greaterThan(10));
    }
    for (var i = 1; i < c.length; i++) {
      expect(c[i].prioridad, greaterThanOrEqualTo(c[i - 1].prioridad));
    }
  });

  test('el resumen dice lo que la app sabe', () {
    expect(resumenParaConsejos(Vehiculo(combustible: 'Diésel', anio: 2018, km: 98500)), 'Para un diésel de 2018 con 98.500 km');
    expect(resumenParaConsejos(Vehiculo()), 'Sin datos del coche todavía');
  });
}
