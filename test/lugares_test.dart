/// Los sitios del mapa: cómo se convierte lo de OpenStreetMap y cómo se leen
/// los horarios. Aquí adivinar es peor que callarse: "cerrado" cuando está
/// abierto manda a alguien a otro sitio.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/lugares/lugares.dart';

void main() {
  group('opening_hours de OSM', () {
    test('el caso normal de un taller', () {
      final h = traducirOpeningHours('Mo-Fr 09:00-13:00,16:00-20:00; Sa 09:00-13:00')!;
      expect(h[0], [[540, 780], [960, 1200]]); // lunes
      expect(h[5], [[540, 780]]); // sábado
      expect(h[6], isEmpty); // domingo: cerrado
    });

    test('24/7 es todos los días entero', () {
      final h = traducirOpeningHours('24/7')!;
      expect(h.every((d) => d.length == 1 && d[0][1] == 1440), isTrue);
    });

    test('los festivos se ignoran sin romper el resto', () {
      final h = traducirOpeningHours('Mo-Sa 08:00-20:00; PH off')!;
      expect(h[0], [[480, 1200]]);
      expect(h[6], isEmpty);
    });

    test('un tramo que cruza medianoche se corta a las 24:00', () {
      final h = traducirOpeningHours('Fr-Sa 22:00-02:00')!;
      expect(h[4], [[1320, 1440]]);
    });

    test('lo que no se entiende devuelve null, no un horario inventado', () {
      expect(traducirOpeningHours('sunrise-sunset'), isNull);
      expect(traducirOpeningHours('Mo-Fr 09:00-13:00; Sa "cita previa"'), isNull);
      expect(traducirOpeningHours(''), isNull);
    });
  });

  group('abierto ahora', () {
    final lugar = Lugar(
      id: 'x',
      tipo: TipoLugar.taller,
      nombre: 'Taller',
      lat: 0,
      lon: 0,
      horario: traducirOpeningHours('Mo-Fr 09:00-13:00,16:00-20:00'),
    );

    test('un martes a las 10 está abierto y dice a qué hora cierra', () {
      final martes = DateTime(2026, 9, 15, 10, 0);
      expect(lugar.abiertoAhora(martes), isTrue);
      expect(lugar.estadoAhora(martes), 'Abierto · cierra a las 13:00');
    });

    test('a las 14 está cerrado y dice cuándo abre', () {
      expect(lugar.estadoAhora(DateTime(2026, 9, 15, 14, 0)), 'Cerrado · abre a las 16:00');
    });

    test('un domingo está cerrado sin hora de apertura', () {
      expect(lugar.estadoAhora(DateTime(2026, 9, 20, 11, 0)), 'Cerrado ahora');
    });

    test('sin horario no se dice ni abierto ni cerrado', () {
      const sin = Lugar(id: 'y', tipo: TipoLugar.taller, nombre: 'T', lat: 0, lon: 0);
      expect(sin.abiertoAhora(), isNull);
      expect(sin.estadoAhora(), isNull);
    });
  });

  group('de OpenStreetMap a Lugar', () {
    test('un taller con servicios declarados', () {
      final l = lugarDeOsm({
        'type': 'node',
        'id': 42,
        'lat': 37.4,
        'lon': -5.9,
        'tags': {
          'shop': 'car_repair',
          'name': 'Talleres Pepe',
          'phone': '+34 954 000 000',
          'service:vehicle:brake_repair': 'yes',
          'service:vehicle:oil_change': 'yes',
          'addr:street': 'Calle Larga',
          'addr:housenumber': '3',
          'addr:city': 'Sevilla',
        },
      })!;
      expect(l.tipo, TipoLugar.taller);
      expect(l.nombre, 'Talleres Pepe');
      expect(l.servicios, containsAll(['Frenos', 'Aceite']));
      expect(l.direccion, 'Calle Larga 3, Sevilla');
      expect(l.hace('frenos'), isTrue);
      expect(l.id, 'osm-node-42');
    });

    test('una estación de ITV hace ITV y no "mecánica general"', () {
      final l = lugarDeOsm({
        'type': 'way',
        'id': 7,
        'center': {'lat': 37.4, 'lon': -5.9},
        'tags': {'amenity': 'vehicle_inspection', 'name': 'ITV Sevilla'},
      })!;
      expect(l.esItv, isTrue);
      expect(l.servicios, ['ITV']);
    });

    test('un taller sin servicios declarados hace mecánica general', () {
      final l = lugarDeOsm({
        'type': 'node',
        'id': 1,
        'lat': 1,
        'lon': 1,
        'tags': {'shop': 'car_repair'},
      })!;
      expect(l.servicios, ['Mecánica general']);
      expect(l.nombre, 'Taller sin nombre');
    });

    test('lo que no es de los nuestros o no tiene coordenadas se descarta', () {
      expect(lugarDeOsm({'type': 'node', 'id': 1, 'lat': 1, 'lon': 1, 'tags': {'shop': 'bakery'}}), isNull);
      expect(lugarDeOsm({'type': 'way', 'id': 1, 'tags': {'shop': 'car_repair'}}), isNull);
    });

    test('recambios de segunda mano es un desguace', () {
      final l = lugarDeOsm({
        'type': 'node', 'id': 1, 'lat': 1, 'lon': 1,
        'tags': {'shop': 'car_parts', 'second_hand': 'only'},
      })!;
      expect(l.tipo, TipoLugar.desguace);
    });
  });

  group('distancias', () {
    test('Sevilla–Madrid son unos 390 km en línea recta', () {
      final d = distanciaKm(37.3891, -5.9845, 40.4168, -3.7038);
      expect(d, closeTo(390, 5));
    });
    test('el texto va en metros de cerca y en km de lejos', () {
      expect(textoDistancia(0.249), 'a 249 m');
      expect(textoDistancia(3.44), 'a 3,4 km');
      expect(textoDistancia(12.7), 'a 13 km');
    });
  });
}
