/// TRANSPORTE BLUETOOTH CLÁSICO (SPP / RFCOMM).
///
/// Esta es la razón de que la app exista. Un ELM327 corriente habla Bluetooth
/// clásico, y eso NINGÚN navegador puede alcanzarlo:
///   · Web Bluetooth solo habla BLE, por diseño.
///   · Web Serial no existe en Android ni en iOS.
/// Comprobado con un dongle real: sale en los ajustes de Bluetooth del móvil y
/// NO aparece en el selector del navegador, por mucho que se emparejase.
/// Android nativo sí llega.
///
/// UN DETALLE QUE CONFUNDE: en los ajustes del móvil el dongle sale
/// "emparejado pero no conectado", y eso es NORMAL. El enlace RFCOMM solo se
/// abre cuando una app lo pide; hasta entonces no hay conexión que mostrar.
///
/// Y EL DONGLE SE ALIMENTA DEL COCHE: el pin 16 del conector OBD es +12 V de
/// la batería. Sin contacto no se enciende, no aparece y no contesta. No es
/// que falten datos: no hay aparato.
library;

import 'dart:async';
import 'dart:convert';

import 'protocolo.dart';

/// Lo que la capa de Bluetooth tiene que saber hacer. Se declara aquí como
/// interfaz para que el protocolo y las pantallas no dependan del paquete
/// concreto: si `flutter_classic_bluetooth` cambia o se abandona, se escribe
/// otra implementación de esto y no se toca nada más.
abstract class EnlaceSerie {
  Stream<List<int>> get entrada;
  Future<void> escribir(List<int> bytes);
  Future<void> cerrar();
}

class AparatoBluetooth {
  final String nombre;
  final String direccion;

  /// Si ya está vinculado con este móvil. Un aparato encontrado y NO
  /// emparejado se puede usar igual —la app lo empareja al conectar—, pero
  /// saberlo cambia lo que se le promete al usuario: con uno emparejado la
  /// conexión es directa; con uno nuevo va a salir el diálogo del PIN.
  final bool emparejado;

  /// Fuerza de la señal en dBm cuando viene de una búsqueda (-40 es pegado,
  /// -90 es al límite). Null en los emparejados, que no se están anunciando.
  final int? senal;

  const AparatoBluetooth(
    this.nombre,
    this.direccion, {
    this.emparejado = false,
    this.senal,
  });

  /// Los ELM327 se anuncian con nombres muy repetidos. No sirve para filtrar
  /// —hay clones que se llaman cualquier cosa— pero sí para ordenar la lista
  /// y que el suyo salga arriba.
  bool get pareceElm => RegExp(
        r'OBD|ELM|VLINK|VGATE|VEEPEAK|KONNWEI|ICAR|SCAN',
        caseSensitive: false,
      ).hasMatch(nombre);
}

/// El transporte: convierte un flujo de bytes en respuestas del ELM327.
class TransporteBluetooth implements Transporte {
  final EnlaceSerie enlace;
  final void Function(String)? avisar;

  final StringBuffer _pendiente = StringBuffer();
  StreamSubscription<List<int>>? _sub;
  bool _identificado = false;

  TransporteBluetooth(this.enlace, {this.avisar}) {
    _sub = enlace.entrada.listen((bytes) {
      // latin1 y no utf8: un byte suelto de basura no puede tirar el decodificador
      _pendiente.write(latin1.decode(bytes, allowInvalid: true));
    });
  }

  bool get identificado => _identificado;

  /// El ELM327 cierra cada respuesta con el prompt ">". Esperarlo no es un
  /// lujo: sin él la orden siguiente se manda a medias y las respuestas se
  /// cruzan, y el síntoma es que todo va desfasado una lectura.
  Future<String> _esperarPrompt(Duration tope) async {
    final limite = DateTime.now().add(tope);
    while (DateTime.now().isBefore(limite)) {
      final texto = _pendiente.toString();
      final i = texto.indexOf('>');
      if (i >= 0) {
        final r = texto.substring(0, i);
        _pendiente.clear();
        _pendiente.write(texto.substring(i + 1));
        return r.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    // Lo que haya llegado, aunque no venga el prompt: mejor eso que nada
    final r = _pendiente.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    _pendiente.clear();
    return r;
  }

  @override
  Future<String> enviar(String comando) async {
    _pendiente.clear();
    await enlace.escribir(latin1.encode('$comando\r'));
    // ATZ reinicia el chip y tarda bastante más que una lectura normal
    return _esperarPrompt(
      RegExp(r'^ATZ', caseSensitive: false).hasMatch(comando)
          ? const Duration(seconds: 7)
          : const Duration(seconds: 5),
    );
  }

  /// Despierta el adaptador y comprueba que al otro lado hay un ELM327.
  ///
  /// NO lanza excepción si no lo consigue: devuelve false y deja el enlace
  /// abierto. Con el enlace vivo todavía se le pueden mandar comandos a mano,
  /// que es justo lo único útil cuando el aparato no se identifica; morirse
  /// aquí quitaba la última información que quedaba.
  Future<bool> despertar() async {
    // Un retorno a secas y tirar la basura del arranque: muchos clones
    // escupen caracteres sueltos en el primer medio segundo.
    try {
      await enlace.escribir(latin1.encode('\r'));
    } catch (_) {/* da igual */}
    await _esperarPrompt(const Duration(milliseconds: 900));
    _pendiente.clear();

    // Tres intentos de ATZ: el primero se pierde a menudo
    for (var intento = 1; intento <= 3; intento++) {
      final r = await enviar('ATZ');
      avisar?.call('ATZ ($intento/3) → ${r.isEmpty ? "(nada)" : r}');
      if (RegExp(r'ELM|OBD|v\d', caseSensitive: false).hasMatch(r)) {
        _identificado = true;
        avisar?.call('Es un ELM327: $r');
        return true;
      }
    }
    avisar?.call(
      'Hay enlace pero no contesta como un ELM327. Puede ser un clon raro '
      'o que el coche no tenga el contacto dado.',
    );
    return false;
  }

  @override
  Future<void> cerrar() async {
    await _sub?.cancel();
    _sub = null;
    await enlace.cerrar();
  }
}

/// Adaptador simulado, para poder ver la app sin coche.
///
/// No devuelve valores bonitos: devuelve las mismas cadenas de hexadecimal
/// que devolvería un ELM327, para que todo el análisis se ejercite de verdad.
/// Y sus valores son INVENTADOS: quien lo use tiene que decirlo en pantalla y
/// no dejar guardar el resultado en el historial del coche.
class TransporteSimulado implements Transporte {
  final Duration retardo;
  final List<String> codigos;
  TransporteSimulado({
    this.retardo = const Duration(milliseconds: 90),
    this.codigos = const ['P0420', 'P0301'],
  });

  static const Map<int, List<int>> _crudos = {
    /// El testigo apagado y sin códigos. Los tres bytes siguientes son los
    /// monitores de a bordo, que aquí van a cero: el simulador no se inventa
    /// un estado de diagnóstico que no significaría nada.
    0x01: [0x00, 0x07, 0xE5, 0x00],
    0x03: [0x02, 0x00], // bucle cerrado, usando la sonda
    0x04: [0x2E],
    0x05: [0x7D], // 125 - 40 = 85 °C, un motor caliente
    0x0B: [0x63],
    0x0C: [0x1A, 0xF8], // (256*26 + 248)/4 = 1726 rpm
    0x0D: [0x00],
    0x0F: [0x3C],
    0x10: [0x01, 0x2C],
    0x11: [0x24],
    0x13: [0x33], // dos sondas por banco, las dos primeras de cada uno
    0x14: [0x8C, 0x80], // 0,70 V
    0x15: [0x1A, 0x80], // 0,13 V: la de detrás del catalizador, plana
    0x1C: [0x06], // EOBD, que es lo que lleva un coche europeo
    0x1F: [0x03, 0x84],
    0x21: [0x00, 0x00],
    0x2F: [0xB4],
    0x42: [0x30, 0x70], // 12400 mV = 12,4 V
    0x46: [0x3B],
    0x5C: [0x82], // 130 - 40 = 90 °C
    0x5E: [0x00, 0x14],
  };

  String _hex(int n) => n.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// El mapa de PID soportados se CALCULA de la tabla de arriba, no se
  /// escribe a mano: así el simulador nunca anuncia un dato que luego no da,
  /// que es justo el fallo que un simulador debe reproducir y no inventar.
  List<int>? _mapaSoportados(int base) {
    final mapa = [0, 0, 0, 0];
    var algo = false;
    for (final pid in _crudos.keys) {
      if (pid <= base || pid > base + 32) continue;
      final n = pid - base - 1;
      mapa[n ~/ 8] |= 0x80 >> (n % 8);
      algo = true;
    }
    if (_crudos.keys.any((p) => p > base + 32)) {
      mapa[3] |= 0x01;
      algo = true;
    }
    return algo ? mapa : null;
  }

  List<int> _dtcABytes(String codigo) {
    final sistema = ['P', 'C', 'B', 'U'].indexOf(codigo[0]);
    final primer = int.parse(codigo[1], radix: 16);
    final resto = int.parse(codigo.substring(2), radix: 16);
    final alto = (sistema << 6) | (primer << 4) | ((resto >> 8) & 0x0F);
    return [alto, resto & 0xFF];
  }

  String _responder(String comando) {
    final c = comando.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (c == 'ATZ' || c == 'ATI') return 'ELM327 v1.5';
    if (c == 'ATDPN') return 'A6'; // CAN 11 bits, 500 kbaudios
    if (c == 'ATRV') return '12.4V';
    if (c.startsWith('AT')) return 'OK';

    if (c.startsWith('01') && c.length >= 4) {
      final pid = int.parse(c.substring(2, 4), radix: 16);
      if ((pid & 0x1F) == 0) {
        final mapa = _mapaSoportados(pid);
        if (mapa == null) return 'NO DATA';
        return '41${_hex(pid)}${mapa.map(_hex).join()}';
      }
      final crudo = _crudos[pid];
      if (crudo == null) return 'NO DATA';
      return '41${_hex(pid)}${crudo.map(_hex).join()}';
    }

    if (c == '03' || c == '07') {
      final lista = c == '03' ? codigos : <String>[];
      if (lista.isEmpty) return '${c == '03' ? '43' : '47'}00';
      final cuerpo = lista.expand(_dtcABytes).toList();
      return '${c == '03' ? '43' : '47'}${_hex(lista.length)}'
          '${cuerpo.map(_hex).join()}';
    }

    if (c == '0902') {
      /// EN CINCO TRAMAS, como lo manda un coche de verdad: `49 02 NN` y
      /// cuatro bytes de datos, con la primera rellenada a ceros por delante.
      /// Antes devolvía el bastidor de una pieza, y por eso el simulador daba
      /// verde mientras el coche de verdad devolvía un bastidor corrupto: el
      /// analizador nunca llegaba a ver una cabecera de trama. Un simulador
      /// más fácil que la realidad no prueba nada.
      const vin = 'VF1RFA00567123456';
      final bytes = <int>[0, 0, 0, ...vin.codeUnits]; // 3 de relleno + 17 = 20
      final tramas = <String>[];
      for (var t = 0; t < 5; t++) {
        final trozo = bytes.sublist(t * 4, t * 4 + 4);
        tramas.add('4902${_hex(t + 1)}${trozo.map(_hex).join()}');
      }
      return tramas.join(' ');
    }
    return 'NO DATA';
  }

  @override
  Future<String> enviar(String comando) async {
    await Future<void>.delayed(retardo);
    return '${_responder(comando)}\r\r>';
  }

  @override
  Future<void> cerrar() async {}
}
