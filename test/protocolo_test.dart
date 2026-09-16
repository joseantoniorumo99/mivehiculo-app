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

    /// LOS PUNTOS PEGADOS A LA RESPUESTA. Mientras busca el protocolo, el
    /// ELM327 escribe un punto por intento y a veces se quedan pegados al
    /// dato. Exigir hexadecimal puro tiraba el trozo ENTERO y con él la
    /// respuesta, y eso dejó la pantalla en blanco con el coche delante.
    test('los puntos pegados al dato no se llevan el dato', () {
      // Literal del registro de un Opel Astra, primer comando de la sesión
      expect(aBytes('SEARCHING... ..4100FE3FB811'),
          [0x41, 0x00, 0xFE, 0x3F, 0xB8, 0x11]);
      expect(aBytes('..410C1AF8'), [0x41, 0x0C, 0x1A, 0xF8]);
      // Y "SEARCHING..." sin puntos sigue sin ser hexadecimal
      expect(aBytes('SEARCHING...'), isEmpty);
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
      // El simulador tiene 21 PID con datos: ni uno más ni uno menos. Si
      // saliera de una lista escrita a mano esto pasaría igual y en el coche
      // no, que es justo lo que esta prueba impide.
      expect(lista.length, 21);
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
  });

  /// UN COCHE DE VERDAD, GRABADO. Las respuestas son literales del registro de
  /// un Opel Astra leído en la calle. Vale más que cualquier caso inventado:
  /// dos fallos que costaron dos viajes al coche —el bastidor con cabeceras y
  /// los puntos del SEARCHING— se ven aquí y no en un simulador amable.
  group('sesión grabada de un Opel Astra', () {
    const respuestas = <String, String>{
      'ATZ': 'ATZ ELM327 v1.5',
      'ATE0': 'ATE0 OK',
      'ATL0': 'OK',
      'ATS0': 'OK',
      'ATH0': 'OK',
      'ATSP0': 'OK',
      // El primero de la sesión llega con SEARCHING y puntos pegados
      '0100': 'SEARCHING... ..4100FE3FB811',
      '0120': '412000000000',
      '0105': '41054B',
      '010C': '410C0000',
      '010D': '410D00',
      '0111': '411123',
      '0104': '410432',
      '010B': '410B63',
      '010E': '410E80',
      '010F': '410F2D',
      '0110': '4110012C',
      '03': '43000000000000',
      '0902': '49020100000057 490202304C3054 49020347463438 '
          '49020433363133 49020537323536',
    };

    Sesion sesionGrabada() => Sesion(_Grabado(respuestas));

    test('enumera los PID que el coche anuncia de verdad', () async {
      final s = sesionGrabada();
      await s.iniciar();
      final lista = await s.pidsSoportados();
      // FE 3F B8 11 -> 01..07, 0B..10, 11, 13, 14, 15, 1C (y 20 = "hay más")
      expect(lista, contains(0x05));
      expect(lista, contains(0x0C));
      expect(lista, contains(0x11));
      expect(lista, isNot(contains(0x20)));
      expect(lista, isNot(contains(0x42))); // este coche NO da la tensión
    });

    test('lee lo que hay y no se queda en blanco', () async {
      final s = sesionGrabada();
      await s.iniciar();
      final l = await s.leerLoQueHaya();
      expect(l, isNotEmpty, reason: 'con el coche delante no puede dar cero');
      final refrigerante = l.firstWhere((x) => x.pid == 0x05);
      expect(refrigerante.valor, 35); // 0x4B = 75, 75-40 = 35 °C
      final rpm = l.firstWhere((x) => x.pid == 0x0C);
      expect(rpm.valor, 0); // motor parado
    });

    test('la mariposa se llama mariposa, no acelerador', () async {
      // 0x23 = 35 -> 13,7 %. Con el pie FUERA. El dato es correcto: este
      // sensor tiene tope mecánico y en ralentí no baja de ~10 %.
      final s = sesionGrabada();
      await s.iniciar();
      final l = await s.leerLoQueHaya();
      final m = l.firstWhere((x) => x.pid == 0x11);
      expect(m.valor, closeTo(13.7, 0.1));
      expect(m.nombre.toLowerCase(), contains('mariposa'));
    });

    test('y el bastidor sale entero y correcto', () async {
      final s = sesionGrabada();
      await s.iniciar();
      expect(await s.leerVin(), 'W0L0TGF4836137256');
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

  /// LO QUE EL COCHE DA Y LA APP NO ENTENDÍA. Este grupo existe porque la
  /// pantalla enseñaba menos datos de los que el coche había contestado y no
  /// decía en ningún sitio que faltaran: se filtraban en silencio los PID sin
  /// fórmula conocida, y la cuenta no cuadraba con lo que el propio coche
  /// declara soportar.
  group('ningún dato del coche se tira en silencio', () {
    test('un PID que la app no conoce sale con sus bytes', () async {
      // 0x02 lo anuncia cualquier coche y esta app no lo interpreta.
      final s = Sesion(_Grabado(const {
        '0100': '4100E0000000', // solo 01, 02 y 03
        '0102': '410201AB',
      }));
      await s.iniciar();
      final l = await s.leerPid(0x02);
      expect(l, isNotNull, reason: 'el coche lo ha contestado: no se tira');
      expect(l!.esNumero, isFalse);
      expect(l.texto, '01 AB');
      expect(l.reconocido, isFalse);
      expect(l.crudo, [0x01, 0xAB]);
    });

    test('los que no se entienden van los últimos, no mezclados', () {
      final orden = porInteres([
        const Lectura(0x02, 'PID 0x02', '', null, texto: '01 AB'),
        const Lectura(0x05, 'Temperatura del refrigerante', '°C', 35),
      ]);
      expect(orden.first.pid, 0x05);
      expect(orden.last.pid, 0x02);
    });

    test('un PID que el coche no contesta sigue siendo null', () async {
      final s = Sesion(_Grabado(const {'0100': '4100E0000000'}));
      await s.iniciar();
      expect(await s.leerPid(0x02), isNull);
    });
  });

  group('los datos que no son números', () {
    test('el testigo del motor y cuántos códigos hay', () async {
      // 0x83 = testigo encendido (bit alto) y 3 códigos guardados
      final s = Sesion(_Grabado(const {'0101': '410183070000'}));
      await s.iniciar();
      final l = await s.leerPid(0x01);
      expect(l!.texto, contains('ENCENDIDO'));
      expect(l.texto, contains('3 códigos'));
      expect(l.esNumero, isFalse);
    });

    test('con el testigo apagado y sin códigos lo dice claro', () async {
      final s = Sesion(_Grabado(const {'0101': '410100070000'}));
      await s.iniciar();
      final l = await s.leerPid(0x01);
      expect(l!.texto, 'Apagado · sin códigos guardados');
    });

    test('un código en singular no dice "1 códigos"', () async {
      final s = Sesion(_Grabado(const {'0101': '410181070000'}));
      await s.iniciar();
      expect((await s.leerPid(0x01))!.texto, contains('1 código guardado'));
    });

    test('la norma OBD sale con su nombre, no con un número', () async {
      final s = Sesion(_Grabado(const {'011C': '411C06'}));
      await s.iniciar();
      expect((await s.leerPid(0x1C))!.texto, contains('EOBD'));
    });

    test('el sistema de combustible dice en qué bucle está', () async {
      final s = Sesion(_Grabado(const {'0103': '41030200'}));
      await s.iniciar();
      expect((await s.leerPid(0x03))!.texto, contains('bucle cerrado'));
    });
  });

  group('las sondas lambda', () {
    test('la tensión sale en voltios y con decimales que se vean', () async {
      // 0x8C = 140; 140/200 = 0,70 V
      final s = Sesion(_Grabado(const {'0114': '41148C80'}));
      await s.iniciar();
      final l = await s.leerPid(0x14);
      expect(l!.valor, closeTo(0.70, 0.001));
      expect(l.unidad, 'V');
    });

    test('la presión de vapores puede ser NEGATIVA', () async {
      /// Va en complemento a dos. Leerla sin signo daba saltos de 65.000 Pa
      /// que parecen una avería gravísima y son un depósito en depresión,
      /// que es lo normal.
      final s = Sesion(_Grabado(const {'0132': '4132FF38'}));
      await s.iniciar();
      expect((await s.leerPid(0x32))!.valor, -200);
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

/// Un transporte que devuelve respuestas GRABADAS de un coche real. Lo que no
/// esté en la tabla contesta "NO DATA", igual que un coche con un PID que no
/// soporta — así el simulador no puede ser más amable que la realidad.
class _Grabado implements Transporte {
  final Map<String, String> respuestas;
  _Grabado(this.respuestas);

  @override
  Future<String> enviar(String comando) async {
    final c = comando.toUpperCase().replaceAll(RegExp(r'\s'), '');
    return '${respuestas[c] ?? "NO DATA"}\r\r>';
  }

  @override
  Future<void> cerrar() async {}
}
