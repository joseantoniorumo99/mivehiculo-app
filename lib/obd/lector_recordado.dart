/// Recuerda con qué lector se habló la última vez.
///
/// Es lo que permite que al abrir la pantalla se lea sola sin preguntar nada,
/// y a la vez NO dejar el Bluetooth escuchando: se conecta, se lee, se cierra.
///
/// Por qué importa cerrar: un enlace RFCOMM abierto consume batería, deja el
/// puerto cogido —así que ninguna otra app puede usar el lector— y en un
/// móvil el sistema acaba matando el proceso igualmente. "Siempre escuchando"
/// suena a más funcionalidad y es menos: lo que se quiere es que el dato esté
/// fresco cuando miras, no que se lea cuando no miras.
library;

import 'package:shared_preferences/shared_preferences.dart';

class LectorRecordado {
  static const _clave = 'obd_ultimo_lector';

  /// Guarda dirección y nombre juntos: la dirección es lo que hace falta para
  /// conectar, y el nombre es lo que se le puede enseñar a una persona.
  static Future<void> guardar(String direccion, String nombre) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_clave, '$direccion|$nombre');
  }

  static Future<({String direccion, String nombre})?> leer() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_clave);
    if (v == null || !v.contains('|')) return null;
    final i = v.indexOf('|');
    return (direccion: v.substring(0, i), nombre: v.substring(i + 1));
  }

  static Future<void> olvidar() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_clave);
  }
}
