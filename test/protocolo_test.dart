/// Pruebas del protocolo OBD-II portado a Dart.
///
/// Son las mismas que defendían la versión web, y defienden lo mismo: que el
/// análisis del hexadecimal sea correcto cuando el adaptador NO se porta bien.
/// Un ELM327 cuela texto suyo entre las respuestas, cambia el formato según
/// cómo esté configurado, y en protocolos que no son CAN algunos se saltan el
/// byte de cuenta de los códigos. Cada una de esas rarezas cambia el
/// resultado, y ninguna se ve en una captura de pantalla.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/obd/protocolo.dart';
import 'package:mivehiculo/obd/transporte_bluetooth.dart';

void main() {
  group('lectura del hexadecimal', () {
    test('con espacios y sin espacios da lo mismo', () {
      expect(aBytes('41 0C 1A F8'), [0x41, 0x0C, 0x1A, 0xF8]);
      expect(aBytes('410C1AF8'), [0x41, 0x0C, 0x1A, 0xF8]);
    });

    test('tira el texto que cuela el adaptador', () {
      // SEARCHING... es lo que escribe mientras busca el protocolo del coche
      expect(aBytes('SEARCHING... 41 0C 1A F8'), [0x41, 0x0C, 0x1A, 0xF8]);
      expect(aBytes('0: 41 0C 1A F8'), [0x41, 0x0C, 0x1A, 0xF8]);
    });

    test('reconoce las respuestas que no son datos', () {
      expect(esError('NO DATA'), isTrue);
      expect(esError('UNABLE TO CONNECT'), isTrue);
      expect(esError('41 0C 1A F8'), isFalse);
    });
  });

  group('códigos de avería', () {
    test('decodifica según SAE J2012', () {
      expect(decodificarDtc(0x04, 0x20), 'P0420');
      expect(decodificarDtc(0x03, 0x01), 'P0301');
    });

    test('un hueco a cero no es un código', () {
      expect(decodificarDtc(0x00, 0x00), isNull);
    });

    test('dice la familia sin inventarse la avería concreta', () {
      // La letra y el primer dígito SÍ están en el estándar; la avería
      // concreta depende del fabricante y ahí hay que callarse.
      expect(describirDtc('P0420'), contains('genérico'));
      expect(describirDtc('P1234'), contains('fabricante'));
    });
  });

  group('diálogo con el adaptador', () {
    test('las revoluciones salen del hexadecimal, no de una tabla', () async {
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      expect(await s.iniciar(), isTrue);
      final l = await s.leerPid(0x0C);
      // (256*0x1A + 0xF8) / 4 = 1726
      expect(l!.valor, closeTo(1726, 0.01));
      expect(l.unidad, 'rpm');
    });

    test('un PID que el coche no da devuelve null, no un cero', () async {
      // Un cero es un DATO ("está a cero") y null es "no lo sabemos".
      // Confundirlos es lo que hace que una app enseñe un depósito vacío.
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      await s.iniciar();
      expect(await s.leerPid(0x0A), isNull); // presión de combustible: no está
    });

    test('enumera los PID leyendo los MAPAS DE BITS', () async {
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      await s.iniciar();
      final lista = await s.pidsSoportados();
      // El simulador tiene 15 PID con datos: ni uno más ni uno menos. Si
      // saliera de una lista escrita a mano esto pasaría igual y en el coche
      // no, que es justo lo que esta prueba impide.
      expect(lista.length, 15);
      expect(lista, contains(0x0C));
      expect(lista, contains(0x5E));
      expect(lista, isNot(contains(0x20))); // 0x20 es el bit de "hay más", no un dato
    });

    test('lee los códigos guardados', () async {
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      await s.iniciar();
      final c = await s.leerCodigos(3);
      expect(c.map((a) => a.codigo), containsAll(['P0420', 'P0301']));
    });

    test('los pendientes del modo 07 van aparte', () async {
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      await s.iniciar();
      expect(await s.leerCodigos(7), isEmpty);
    });

    test('saca el bastidor de los 17 caracteres ASCII', () async {
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      await s.iniciar();
      expect(await s.leerVin(), 'VF1RFA00567123456');
    });
  });

  group('el bastidor de un coche de verdad', () {
    /// Respuesta LITERAL de un Opel Astra, copiada del registro de la app en
    /// el coche. Llega en cinco tramas y cada una trae su cabecera `4902NN`.
    const respuestaReal = '49020100000057 490202304C3054 49020347463438 '
        '49020433363133 49020537323536';

    test('parte por tramas y no se cuela ninguna cabecera', () {
      expect(vinDeRespuesta(aBytes(respuestaReal)), 'W0L0TGF4836137256');
    });

    test('la W del principio NO se pierde', () {
      // Iba en la primera trama, detrás de tres bytes de relleno a cero. La
      // primera versión se comía las tres primeras letras enteras.
      expect(vinDeRespuesta(aBytes(respuestaReal))!.startsWith('W0L'), isTrue);
    });

    test('no aparecen íes de contrabando', () {
      /// 0x49 es la letra I en ASCII y es el primer byte de CADA cabecera de
      /// trama. Filtrar "solo letras y dígitos" sobre el flujo entero las
      /// dejaba pasar: salía 0TIGF48I3613I7256, que no es el bastidor de
      /// ningún coche. Esta prueba existe por eso exactamente.
      final vin = vinDeRespuesta(aBytes(respuestaReal))!;
      expect(vin, isNot(contains('I')));
      expect(vin.length, 17);
    });

    test('sin cabecera 4902 no se inventa un bastidor', () {
      expect(vinDeRespuesta(aBytes('NO DATA')), isNull);
      expect(vinDeRespuesta(aBytes('41 0C 1A F8')), isNull);
    });

    test('el observador ve CADA comando y CADA respuesta', () async {
      // Sin esto un volcado no enseñaría los mapas de PID soportados y
      // mentiría por omisión justo donde se explica por qué falta un dato.
      final visto = <String>[];
      final s = Sesion(TransporteSimulado(retardo: Duration.zero),
          mirar: (que, texto) => visto.add('$que:$texto'));
      await s.iniciar();
      expect(visto, contains('envia:ATZ'));
      expect(visto.where((v) => v.startsWith('recibe:')), isNotEmpty);
    });
  });

  group('el simulador no puede mentir', () {
    test('no anuncia un PID que luego no da', () async {
      // El mapa de soportados se CALCULA de la tabla de valores. Si se
      // escribiera a mano podría anunciar algo que contesta NO DATA, que es
      // justo el fallo que un simulador debe reproducir y no inventar.
      final s = Sesion(TransporteSimulado(retardo: Duration.zero));
      await s.iniciar();
      for (final pid in await s.pidsSoportados()) {
        expect(await s.leerPid(pid), isNotNull,
            reason: 'anuncia 0x${pid.toRadixString(16)} y no lo da');
      }
    });
  });
}
