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
enum FalloBluetooth { sinPermiso, permisoDenegadoParaSiempre, apagado, otro }

class ErrorBluetooth implements Exception {
  final FalloBluetooth causa;
  final String mensaje;
  const ErrorBluetooth(this.causa, this.mensaje);
  @override
  String toString() => mensaje;
}

/// Lo que la pantalla necesita saber de Bluetooth, y nada más.
class Bluetooth {
  final _btc = FlutterClassicBluetooth();

  /// En Android 12+ `BLUETOOTH_CONNECT` es un permiso de TIEMPO DE EJECUCIÓN:
  /// declararlo en el manifiesto no basta, hay que pedírselo al usuario o la
  /// llamada revienta con un SecurityException. Se pide aquí, antes de listar
  /// nada, y no se deja que salte solo dentro de otra operación: un diálogo de
  /// permisos que aparece de la nada, sin que se entienda para qué, se deniega.
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
        'Bluetooth. Hay que dárselo a mano en los ajustes de la app.',
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
          'El Bluetooth está apagado. Enciéndelo y vuelve a intentarlo.');
    }
  }

  /// Manda al usuario a los ajustes de la app: es la única salida cuando el
  /// permiso quedó denegado para siempre.
  Future<void> abrirAjustes() => _btc.openAppSettings();

  /// Los EMPAREJADOS, no los que se ven al buscar. Un ELM327 hay que
  /// emparejarlo antes desde los ajustes del móvil (PIN 1234 o 0000), y ahí
  /// aparece como "emparejado pero no conectado", que es lo normal: el enlace
  /// solo se abre cuando una app lo pide, y eso es justo lo que hace esto.
  Future<List<AparatoBluetooth>> emparejados() async {
    await _asegurarPermisos();
    await _asegurarEncendido();
    final lista = await _btc.getPairedDevices();
    // displayName no es nulo en este paquete, pero sí puede venir VACÍO: en
    // ese caso vale más la dirección MAC que una fila en blanco en la lista.
    final salida = lista
        .map((d) => AparatoBluetooth(
              d.displayName.isEmpty ? d.address : d.displayName,
              d.address,
            ))
        .toList();
    // Los que parecen un ELM327, primero: la lista de un móvil lleva auriculares,
    // el coche, la tele... y el lector se pierde en medio.
    salida.sort((a, b) {
      if (a.pareceElm == b.pareceElm) return a.nombre.compareTo(b.nombre);
      return a.pareceElm ? -1 : 1;
    });
    return salida;
  }

  Future<EnlaceClassic> conectar(String direccion) async {
    final c = await _btc.connect(
      address: direccion,
      // Sin uuid explícito el paquete usa el de SPP, que es el que hablan
      // estos lectores. Se deja el suyo en vez de fijarlo: hay clones que
      // anuncian un service class propio y el paquete ya lo resuelve.
      timeout: const Duration(seconds: 15),
    );
    return EnlaceClassic(c);
  }
}
