/// El almacén: que lo que se guarda se lee igual, que la matrícula manda, que
/// los km solo suben, y que las marcas de sincronización cuentan la verdad.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/almacen.dart';
import 'package:mivehiculo/datos/modelo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ida y vuelta del JSON', () {
    test('un vehículo con todo y con nada', () {
      final v = Vehiculo(marca: 'Opel', modelo: 'Astra', anio: 2019, km: 120000, matriculacion: '2019-06');
      final copia = Vehiculo.deJson(jsonDecode(jsonEncode(v.aJson())) as Map<String, dynamic>);
      expect(copia.id, v.id);
      expect(copia.km, 120000);
      expect(copia.anioEfectivo, 2019);
      final vacio = Vehiculo.deJson({});
      expect(vacio.km, isNull, reason: 'un hueco no es un cero');
      expect(vacio.nombre, 'Mi coche');
    });

    test('una intervención con desglose y una lectura', () {
      final i = Intervencion(
        vehiculoId: 'v1',
        fecha: '2026-03-04',
        tipo: 'revision',
        coste: 700,
        lineas: [Linea(concepto: 'Aceite', importe: 60, tipo: 'aceite')],
      );
      final copia = Intervencion.deJson(jsonDecode(jsonEncode(i.aJson())) as Map<String, dynamic>);
      expect(copia.lineas.single.tipo, 'aceite');
      expect(copia.tiposTocados, {'revision', 'aceite'});
      expect(copia.sumaLineas, 60);

      final l = LecturaGuardada(vehiculoId: 'v1', cuando: '2026-09-16T10:00:00Z', valores: {'Revoluciones': '0 rpm'});
      final lc = LecturaGuardada.deJson(jsonDecode(jsonEncode(l.aJson())) as Map<String, dynamic>);
      expect(lc.valores['Revoluciones'], '0 rpm');
    });

    test('un número entrecomillado de un respaldo viejo se lee, no se pierde', () {
      final v = Vehiculo.deJson({'km': '120.000', 'anio': '2019'});
      expect(v.km, 120000);
      expect(v.anio, 2019);
      final i = Intervencion.deJson({'vehiculoId': 'v', 'fecha': '2026-01-01', 'coste': '1234,5'});
      expect(i.coste, 1234.5);
    });
  });

  group('vehículos', () {
    test('repetir una matrícula lleva al coche que ya había', () async {
      final a = Almacen()..cargarDePruebas();
      final primero = await a.anadirVehiculo(Vehiculo(matricula: '4821 KYT', marca: 'Seat'));
      final segundo = await a.anadirVehiculo(Vehiculo(matricula: '4821-kyt', marca: 'Otro'));
      expect(segundo.id, primero.id);
      expect(a.vehiculos.length, 1);
    });

    test('los km solo suben por el diario; a mano sí bajan', () async {
      final a = Almacen()..cargarDePruebas();
      await a.anadirVehiculo(Vehiculo(matricula: '1111 BBB', km: 100000));
      await a.ponerKm(90000);
      expect(a.coche!.km, 100000);
      await a.ponerKm(110000);
      expect(a.coche!.km, 110000);
      await a.corregirKm(95000);
      expect(a.coche!.km, 95000);
    });

    test('quitar un coche se lleva su diario, sus citas y sus lecturas', () async {
      final a = Almacen()..cargarDePruebas();
      final v = await a.anadirVehiculo(Vehiculo(matricula: '2222 BBB'));
      await a.guardarIntervencion(Intervencion(vehiculoId: v.id, fecha: '2026-01-01'));
      await a.guardarLectura(LecturaGuardada(vehiculoId: v.id, cuando: '2026-01-01T00:00:00Z'));
      await a.quitarVehiculo(v.id);
      expect(a.vehiculos, isEmpty);
      expect(a.diario, isEmpty);
      expect(a.lecturas, isEmpty);
      expect(a.idsBorrados, isNotEmpty, reason: 'la nube tiene que enterarse');
    });

    test('el diario es del coche activo', () async {
      final a = Almacen()..cargarDePruebas();
      final uno = await a.anadirVehiculo(Vehiculo(matricula: '3333 BBB'));
      final dos = await a.anadirVehiculo(Vehiculo(matricula: '4444 BBB'));
      await a.guardarIntervencion(Intervencion(vehiculoId: uno.id, fecha: '2026-01-01'));
      expect(a.coche!.id, dos.id);
      expect(a.diarioDelCoche, isEmpty);
      await a.activar(uno.id);
      expect(a.diarioDelCoche.length, 1);
    });
  });

  group('marcas para la nube', () {
    test('guardar marca; enviar lo da por hecho; borrar deja lápida', () async {
      final a = Almacen()..cargarDePruebas();
      final v = await a.anadirVehiculo(Vehiculo(matricula: '5555 BBB'));
      expect(a.marcaDe(v.id), isNotNull);
      expect(a.hayPendiente, isTrue);
      a.marcarEnviado(v.id, a.marcaDe(v.id)!);
      expect(a.hayPendiente, isFalse);
      await a.quitarVehiculo(v.id);
      expect(a.borradoEn(v.id), isNotNull);
      expect(a.marcaDe(v.id), isNull);
    });

    test('lo que baja del servidor no se vuelve a subir', () async {
      final a = Almacen()..cargarDePruebas();
      final v = Vehiculo(id: 'remoto1', matricula: '6666 BBB', marca: 'Dacia');
      await a.aplicarRemoto('vehiculo', v.aJson(), '2026-09-16T10:00:00.000Z');
      expect(a.vehiculos.single.marca, 'Dacia');
      expect(a.marcaDe('remoto1'), '2026-09-16T10:00:00.000Z');
      expect(a.enviadoEn('remoto1'), '2026-09-16T10:00:00.000Z');
      expect(a.hayPendiente, isFalse);
      expect(a.tipoDe('remoto1'), 'vehiculo');
    });

    test('el guardado entero sobrevive a una ida y vuelta por texto', () async {
      final a = Almacen()..cargarDePruebas();
      final v = await a.anadirVehiculo(Vehiculo(matricula: '7777 BBB', marca: 'Ford'));
      await a.guardarIntervencion(Intervencion(vehiculoId: v.id, fecha: '2026-02-02', coste: 50));
      final texto = a.aJsonTexto();
      final j = jsonDecode(texto) as Map<String, dynamic>;
      expect((j['vehiculos'] as List).length, 1);
      expect((j['diario'] as List).length, 1);
      expect((j['marcas'] as Map).length, 2);
    });
  });

  group('de quién es lo que hay en el móvil', () {
    test('sin coche ni diario no hay datos que proteger', () async {
      final a = Almacen();
      await a.cargar();
      expect(a.hayDatosLocales, isFalse);
    });

    test('con un coche sí hay datos locales', () async {
      final a = Almacen()..cargarDePruebas();
      await a.anadirVehiculo(Vehiculo(marca: 'Seat', modelo: 'León'));
      expect(a.hayDatosLocales, isTrue);
    });

    test('marcarPropietario se guarda y sobrevive a una recarga', () async {
      final a = Almacen();
      await a.cargar();
      expect(a.propietarioLocal, isNull, reason: 'un móvil nuevo no es de nadie todavía');
      await a.marcarPropietario('usuario-1');
      expect(a.propietarioLocal, 'usuario-1');

      final b = Almacen();
      await b.cargar();
      expect(b.propietarioLocal, 'usuario-1', reason: 'lo mismo que había guardado el anterior');
    });

    test('borrarTodo también olvida de quién era el móvil', () async {
      final a = Almacen()..cargarDePruebas();
      await a.anadirVehiculo(Vehiculo(marca: 'Seat'));
      await a.marcarPropietario('usuario-1');
      await a.borrarTodo();
      expect(a.propietarioLocal, isNull);
      expect(a.hayDatosLocales, isFalse);
    });
  });
}
