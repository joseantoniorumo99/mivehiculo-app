/// El puente entre `flutter_classic_bluetooth` y nuestro `EnlaceSerie`.
///
/// Está aislado a propósito y es lo único de la app que sabe que ese paquete
/// existe. Si mañana se abandona —que es lo que le pasó a
/// `flutter_bluetooth_serial`, el que todo el mundo usaba— se reescribe este
/// fichero y no se toca ni el protocolo ni las pantallas.
///
/// El paquete es MIT, así que no contagia nada. Y NO es `flutter_blue_plus`,
/// que es el que sale primero en todas las búsquedas: ese solo habla BLE y
/// sería repetir en Flutter el callejón sin salida del navegador.
///
/// ---------------------------------------------------------------------
/// LO QUE COSTÓ QUE ESTO CONECTARA DE VERDAD (16/09/2026)
///
/// Con el lector enchufado y el contacto dado, la app daba:
///   BtcConnectionException(BtcConnectFailure.unreachable):
///   Connection failed: read failed, socket might closed or timeout, read ret: -1
///
/// Ese mensaje de Android no significa "no está ahí". Significa "abrí el
/// socket y al leer no había nadie al otro lado", y en un ELM327 eso tiene
/// tres causas, las tres contempladas ahora:
///
/// 1. LA BÚSQUEDA ESTABA EN MARCHA. Mientras Android hace discovery, la radio
///    va a saltos por todo el espectro y cualquier RFCOMM que se abra en ese
///    momento se cae. Es el fallo más común y el más invisible, porque la
///    búsqueda la había lanzado la propia pantalla para enseñar la lista. Por
///    eso ahora lo PRIMERO que hace `conectar` es parar la búsqueda.
///
/// 2. EL APARATO NO ESTABA EMPAREJADO. Un socket seguro exige vínculo; sin él
///    Android abre, no puede cifrar y cierra. Ahora se empareja desde la app
///    (PIN 1234 o 0000) en vez de mandar al usuario a los ajustes del sistema.
///
/// 3. EL SOCKET SEGURO NO SIRVE PARA ESE CLON. Muchos ELM327 chinos no
///    implementan el emparejamiento como Android espera y solo aceptan socket
///    INSEGURO. Por eso se prueban los dos, en ese orden.
///
/// Y una cuarta que no es de código y hay que decirle al usuario: estos
/// lectores aceptan UNA conexión a la vez. Si el dongle sigue enganchado a
/// otro móvil, el segundo recibe exactamente este error.
/// ---------------------------------------------------------------------
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import 'transporte_bluetooth.dart';

class EnlaceClassic implements EnlaceSerie {
  final BtcConnection _conexion;
  EnlaceClassic(this._conexion);

  @override
  Stream<List<int>> get entrada => _conexion.input.map((d) => d.toList());

  @override
  Future<void> escribir(List<int> bytes) =>
      _conexion.output.writeBytes(Uint8List.fromList(bytes));

  @override
  Future<void> cerrar() async {
    try {
      await _conexion.close();
    } catch (_) {/* si ya estaba cerrada, da igual */}
  }
}

/// Por qué no se pudo, dicho de forma que la pantalla sepa qué ofrecer.
enum FalloBluetooth {
  sinPermiso,
  permisoDenegadoParaSiempre,
  apagado,
  ubicacionApagada,
  noContesta,
  otro,
}

class ErrorBluetooth implements Exception {
  final FalloBluetooth causa;
  final String mensaje;

  /// Qué puede hacer la persona ahora mismo. Va aparte del mensaje porque la
  /// pantalla lo enseña con otro peso: primero qué pasa, luego qué hacer.
  final String? consejo;

  const ErrorBluetooth(this.causa, this.mensaje, [this.consejo]);
  @override
  String toString() => mensaje;
}

/// Lo que la pantalla necesita saber de Bluetooth, y nada más.
class Bluetooth {
  final _btc = FlutterClassicBluetooth();

  /// En Android 12+ `BLUETOOTH_CONNECT` y `BLUETOOTH_SCAN` son permisos de
  /// TIEMPO DE EJECUCIÓN: declararlos en el manifiesto no basta, hay que
  /// pedírselos al usuario o la llamada revienta con un SecurityException. Se
  /// piden aquí, antes de listar nada, y no se deja que salten solos dentro de
  /// otra operación: un diálogo de permisos que aparece de la nada, sin que se
  /// entienda para qué, se deniega.
  Future<void> _asegurarPermisos() async {
    final estado = await _btc.requestPermissions();
    if (estado == BtcPermissionStatus.granted ||
        estado == BtcPermissionStatus.notRequired) {
      return;
    }
    if (estado == BtcPermissionStatus.permanentlyDenied) {
      throw const ErrorBluetooth(
        FalloBluetooth.permisoDenegadoParaSiempre,
        'Le has dicho al sistema que no vuelva a preguntar por el permiso de '
        'Bluetooth.',
        'Hay que dárselo a mano en los ajustes de la app.',
      );
    }
    throw const ErrorBluetooth(
      FalloBluetooth.sinPermiso,
      'Sin permiso de Bluetooth no se puede ver el lector.',
    );
  }

  /// El sistema tampoco puede encender el Bluetooth por su cuenta. Se
  /// comprueba antes para no acabar en "no hay ningún aparato emparejado",
  /// que es el mensaje equivocado y manda a buscar el problema donde no está.
  Future<void> _asegurarEncendido() async {
    if (!await _btc.isSupported()) {
      throw const ErrorBluetooth(
          FalloBluetooth.otro, 'Este móvil no tiene Bluetooth clásico.');
    }
    if (!await _btc.isEnabled()) {
      throw const ErrorBluetooth(FalloBluetooth.apagado,
          'El Bluetooth está apagado.', 'Enciéndelo y vuelve a intentarlo.');
    }
  }

  /// BUSCAR APARATOS EXIGE LA UBICACIÓN ENCENDIDA, y esto sorprende a todo el
  /// mundo. Android ata el descubrimiento Bluetooth al servicio de ubicación
  /// porque con una lista de aparatos cercanos se puede deducir dónde estás.
  /// Con la ubicación apagada, `scan` no falla: devuelve CERO aparatos, que es
  /// peor, porque parece que el lector no está.
  Future<void> _avisarSiUbicacionHaceFalta() async {
    try {
      if (await _btc.isLocationServiceRequired() &&
          !await _btc.isLocationServiceEnabled()) {
        throw const ErrorBluetooth(
          FalloBluetooth.ubicacionApagada,
          'Para BUSCAR aparatos, Android exige tener la ubicación encendida.',
          'Enciende la ubicación del móvil y vuelve a buscar. No es para saber '
              'dónde estás: es cómo funciona el sistema.',
        );
      }
    } on ErrorBluetooth {
      rethrow;
    } catch (_) {
      // Si el plugin no sabe contestar, no se bloquea la búsqueda por eso.
    }
  }

  /// Manda al usuario a los ajustes de la app: es la única salida cuando el
  /// permiso quedó denegado para siempre.
  Future<void> abrirAjustes() => _btc.openAppSettings();

  Future<void> abrirAjustesUbicacion() => _btc.openLocationSettings();

  /// Los EMPAREJADOS: los que ya están vinculados con este móvil.
  Future<List<AparatoBluetooth>> emparejados() async {
    await _asegurarPermisos();
    await _asegurarEncendido();
    final lista = await _btc.getPairedDevices();
    return _ordenar(lista.map(_aAparato).toList());
  }

  /// BUSCA LOS QUE ESTÁN CERCA, emparejados o no.
  ///
  /// Esto es lo que faltaba: la app solo miraba los emparejados, así que un
  /// lector que el móvil VE pero con el que nunca se ha vinculado no aparecía
  /// por ningún lado, y desde la app no había forma de vincularlo. En un móvil
  /// donde el emparejamiento del sistema falla —pasa con clones baratos— eso
  /// dejaba a la app sin ninguna salida.
  ///
  /// Devuelve los emparejados SIEMPRE, aunque la búsqueda no encuentre nada:
  /// un lector ya vinculado que en este momento no se anuncia sigue siendo
  /// perfectamente conectable, y esconderlo sería un paso atrás.
  Future<List<AparatoBluetooth>> buscar({
    Duration durante = const Duration(seconds: 12),
  }) async {
    await _asegurarPermisos();
    await _asegurarEncendido();

    final porDireccion = <String, AparatoBluetooth>{};
    for (final d in await _btc.getPairedDevices()) {
      porDireccion[d.address] = _aAparato(d);
    }

    await _avisarSiUbicacionHaceFalta();

    try {
      for (final d in await _btc.scan(timeout: durante)) {
        final antes = porDireccion[d.address];
        final nuevo = _aAparato(d);
        // Una vista repetida a veces llega SIN nombre (solo refresca la
        // señal). Si ya teníamos uno bueno, no se pisa con la dirección MAC.
        porDireccion[d.address] = (antes != null &&
                antes.nombre != antes.direccion &&
                nuevo.nombre == nuevo.direccion)
            ? antes
            : nuevo;
      }
    } catch (e) {
      // Que falle la búsqueda no puede dejar sin lista a quien ya tiene el
      // lector emparejado: eso es quitarle lo que funcionaba.
      if (porDireccion.isEmpty) {
        throw ErrorBluetooth(FalloBluetooth.otro,
            'No se ha podido buscar aparatos cerca.', e.toString());
      }
    }

    return _ordenar(porDireccion.values.toList());
  }

  Future<void> pararBusqueda() async {
    try {
      await _btc.stopDiscovery();
    } catch (_) {/* si no había búsqueda, mejor */}
  }

  /// Empareja desde la app, sin mandar a nadie a los ajustes del sistema.
  ///
  /// El PIN de casi todos estos lectores es **1234** y en algunos **0000**; lo
  /// pide el propio Android en su diálogo, así que aquí solo se dispara y se
  /// espera. Devuelve false si el usuario lo cancela o el aparato lo rechaza.
  Future<bool> emparejar(String direccion,
      {Duration espera = const Duration(seconds: 45)}) async {
    await _asegurarPermisos();
    await _asegurarEncendido();

    /// Emparejar TAMBIÉN se estropea con la búsqueda en marcha, por lo mismo
    /// que conectar: la radio está saltando de canal.
    await pararBusqueda();

    final ya = await _btc.getPairedDevices();
    if (ya.any((d) => d.address == direccion)) return true;

    // Se escucha el estado ANTES de pedirlo: si se pide primero, un
    // emparejamiento rápido puede terminar antes de que nadie esté mirando.
    final vinculado = _btc
        .bondState(direccion)
        .firstWhere((e) => e == BtcBondState.bonded)
        .timeout(espera, onTimeout: () => BtcBondState.none);

    final lanzado = await _btc.bondDevice(direccion);
    if (!lanzado) return false;
    return await vinculado == BtcBondState.bonded;
  }

  /// Abre el enlace. Es aquí donde estaba el fallo que dejaba la pantalla en
  /// el mensaje de "unreachable"; el porqué de cada paso está arriba del todo.
  Future<EnlaceClassic> conectar(
    String direccion, {
    void Function(String)? avisar,

    /// En segundo plano NO se empareja (saldría el diálogo del PIN sin nadie
    /// mirando), no se pide permiso (no hay pantalla donde pedirlo) y se hace
    /// UN intento por modo con tope corto: si el coche está apagado el lector
    /// no existe, y cada segundo de espera es batería.
    bool enSegundoPlano = false,
  }) async {
    if (!enSegundoPlano) {
      await _asegurarPermisos();
      await _asegurarEncendido();
    } else if (!await _btc.isEnabled()) {
      throw const ErrorBluetooth(FalloBluetooth.apagado, 'El Bluetooth está apagado.');
    }

    // 1. Parar la búsqueda. Sin esto, lo demás da igual.
    await pararBusqueda();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (enSegundoPlano) {
      Object? ultimo;
      for (final seguro in [true, false]) {
        try {
          final c = await _btc.connect(
            address: direccion,
            secure: seguro,
            timeout: const Duration(seconds: 8),
          );
          return EnlaceClassic(c);
        } catch (e) {
          ultimo = e;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      throw ErrorBluetooth(
          FalloBluetooth.noContesta, 'El lector no contesta.', '$ultimo');
    }

    // 2. Emparejar si hace falta. Un socket seguro sin vínculo no va.
    final emparejadosYa = await _btc.getPairedDevices();
    if (!emparejadosYa.any((d) => d.address == direccion)) {
      avisar?.call('Emparejando con el lector (PIN 1234 o 0000)…');
      final ok = await emparejar(direccion);
      if (!ok) {
        throw const ErrorBluetooth(
          FalloBluetooth.noContesta,
          'No se ha podido emparejar con el lector.',
          'El PIN de casi todos es 1234, y en algunos 0000. Si el móvil no '
              'llega a preguntarlo, desenchufa el lector del coche, vuelve a '
              'enchufarlo y prueba otra vez.',
        );
      }
    }

    // 3. Seguro primero; inseguro después. Muchos clones solo aceptan el
    //    segundo, y probarlo cuesta dos segundos.
    Object? ultimo;
    for (final seguro in [true, false]) {
      for (var intento = 1; intento <= 2; intento++) {
        try {
          avisar?.call(seguro
              ? 'Abriendo el enlace…'
              : 'Probando el modo que aceptan los lectores más sencillos…');
          final c = await _btc.connect(
            address: direccion,
            secure: seguro,
            timeout: const Duration(seconds: 12),
          );
          return EnlaceClassic(c);
        } catch (e) {
          ultimo = e;
          // Un respiro entre intentos: el chip del lector tarda en soltar el
          // socket anterior y el segundo intento inmediato falla siempre.
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }

    throw ErrorBluetooth(
      FalloBluetooth.noContesta,
      'El lector está ahí pero no abre la conexión.',
      'Tres cosas, en este orden: (1) estos lectores aceptan UN móvil a la '
          'vez, así que quita el Bluetooth del otro teléfono si lo tuviste '
          'conectado; (2) desenchufa el lector del conector OBD y vuelve a '
          'enchufarlo, con el contacto dado; (3) si sigue igual, en los '
          'ajustes de Bluetooth del móvil olvida el aparato y vuelve a '
          'emparejarlo desde aquí.\n\nDetalle técnico: $ultimo',
    );
  }

  AparatoBluetooth _aAparato(BtcDevice d) => AparatoBluetooth(
        // displayName no es nulo en este paquete, pero sí puede venir VACÍO:
        // en ese caso vale más la dirección MAC que una fila en blanco.
        d.displayName.isEmpty ? d.address : d.displayName,
        d.address,
        emparejado: d.bondState == BtcBondState.bonded,
        senal: d.rssi,
      );

  /// Los que parecen un ELM327, primero: la lista de un móvil lleva
  /// auriculares, el coche, la tele... y el lector se pierde en medio. Entre
  /// dos que lo parecen, antes el ya emparejado, que conecta sin preguntar.
  List<AparatoBluetooth> _ordenar(List<AparatoBluetooth> lista) {
    lista.sort((a, b) {
      if (a.pareceElm != b.pareceElm) return a.pareceElm ? -1 : 1;
      if (a.emparejado != b.emparejado) return a.emparejado ? -1 : 1;
      return a.nombre.compareTo(b.nombre);
    });
    return lista;
  }
}
