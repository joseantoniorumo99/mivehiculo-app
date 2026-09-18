/// LA LECTURA DEL OBD EN SEGUNDO PLANO, sin gastar batería.
///
/// Dos disparadores, los dos apagados hasta que el dueño los enciende en
/// «Lectura automática»:
///
/// 1. EL BLUETOOTH DEL COCHE. Cuando el móvil se conecta al manos libres o a
///    la radio del coche, Android despierta a la app (receptor en Kotlin,
///    `ReceptorBluetooth.kt`), que encola una lectura para medio minuto
///    después. Es el disparador bueno: no cuesta nada mientras no se conduce,
///    porque no hay nada sondeando.
///
/// 2. CADA X TIEMPO. Un trabajo periódico de WorkManager (mínimo 15 minutos,
///    lo pone Android). Cada vez intenta abrir el lector con un tope corto;
///    si el coche está apagado, el lector no existe y el intento muere en
///    unos segundos. Cuesta algo de batería —unos segundos de radio por
///    intento— y por eso es opcional y se dice.
///
/// LO QUE NO ES: un servicio permanente escuchando. Eso gasta batería, coge
/// el puerto para cualquier otra app y el sistema acaba matándolo igual.
///
/// EN SEGUNDO PLANO NO SE EMPAREJA (saldría el diálogo del PIN sin nadie
/// mirando) y no se reintenta con calma: un intento por modo y a dormir.
///
/// TODO LO QUE PASA AQUÍ SE APUNTA en un registro que se lee desde «Lectura
/// automática». En segundo plano no hay pantalla donde ver un error, y sin
/// registro "no me funcionó" no se puede convertir en un fallo concreto.
library;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../datos/almacen.dart';
import '../datos/modelo.dart';
import '../datos/notificador.dart';
import 'enlace_classic.dart';
import 'lector_recordado.dart';
import 'protocolo.dart';
import 'transporte_bluetooth.dart';

/// El nombre de la tarea Dart. Tiene que coincidir LETRA POR LETRA con el que
/// encola `ReceptorBluetooth.kt`.
const String tareaLecturaObd = 'es.regislab.mivehiculo.lecturaObd';
const String _nombrePeriodica = 'lectura-obd-periodica';
const String _nombrePrueba = 'lectura-obd-prueba';

/// El registro de lo que hace el segundo plano. Lo escriben Dart (esta
/// tarea) y Kotlin (el receptor), en la misma clave de SharedPreferences
/// (`flutter.obd_fondo_registro`), una línea por suceso, las últimas 40.
class RegistroFondo {
  static const _clave = 'obd_fondo_registro';
  static const _maximo = 40;

  static Future<void> apuntar(String texto) async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final ahora = DateTime.now();
    final sello = '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')} '
        '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}:${ahora.second.toString().padLeft(2, '0')}';
    final lineas = (p.getString(_clave) ?? '').split('\n').where((l) => l.isNotEmpty).toList();
    lineas.add('$sello  $texto');
    while (lineas.length > _maximo) {
      lineas.removeAt(0);
    }
    await p.setString(_clave, lineas.join('\n'));
  }

  static Future<List<String>> leer() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return (p.getString(_clave) ?? '').split('\n').where((l) => l.isNotEmpty).toList().reversed.toList();
  }

  static Future<void> borrar() async =>
      (await SharedPreferences.getInstance()).remove(_clave);
}

/// Ajustes de la lectura automática. Viven en SharedPreferences porque el
/// receptor en Kotlin también tiene que leer cuál es "el coche".
class AjustesLecturaAutomatica {
  /// "MAC|nombre" del aparato Bluetooth del coche. La clave la lee Kotlin
  /// como `flutter.obd_coche_bt`: no cambiarla sin cambiarla allí.
  static const _claveCoche = 'obd_coche_bt';
  static const _claveCada = 'obd_cada_minutos';
  static const _claveUltima = 'obd_ultima_fondo';

  static Future<({String direccion, String nombre})?> aparatoCoche() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_claveCoche);
    if (v == null || !v.contains('|')) return null;
    final i = v.indexOf('|');
    return (direccion: v.substring(0, i), nombre: v.substring(i + 1));
  }

  static Future<void> ponerAparatoCoche(String? direccion, String? nombre) async {
    final p = await SharedPreferences.getInstance();
    if (direccion == null) {
      await p.remove(_claveCoche);
      await RegistroFondo.apuntar('Ajuste: sin aparato del coche');
    } else {
      await p.setString(_claveCoche, '$direccion|${nombre ?? direccion}');
      await RegistroFondo.apuntar('Ajuste: el coche es ${nombre ?? direccion} ($direccion)');
    }
  }

  /// 0 = apagado. Android no baja de 15 minutos.
  static Future<int> cadaMinutos() async =>
      (await SharedPreferences.getInstance()).getInt(_claveCada) ?? 0;

  static Future<void> ponerCadaMinutos(int minutos) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_claveCada, minutos);
    if (minutos <= 0) {
      await Workmanager().cancelByUniqueName(_nombrePeriodica);
      await RegistroFondo.apuntar('Ajuste: lectura periódica apagada');
      return;
    }
    await Workmanager().registerPeriodicTask(
      _nombrePeriodica,
      tareaLecturaObd,
      frequency: Duration(minutes: minutos < 15 ? 15 : minutos),
      inputData: const {'motivo': 'periodica'},
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
    await RegistroFondo.apuntar('Ajuste: lectura periódica cada $minutos min');
  }

  static Future<DateTime?> ultimaLecturaDeFondo() async {
    final v = (await SharedPreferences.getInstance()).getString(_claveUltima);
    return v == null ? null : DateTime.tryParse(v);
  }

  static Future<void> _apuntarLecturaDeFondo() async =>
      (await SharedPreferences.getInstance())
          .setString(_claveUltima, DateTime.now().toUtc().toIso8601String());

  /// Encola una lectura para dentro de unos segundos, por el MISMO camino que
  /// usan el receptor de Bluetooth y la periódica. Es la forma de probar el
  /// segundo plano sin coche: pulsar, cerrar la app, esperar, y mirar el
  /// registro.
  static Future<void> probarAhora() async {
    await RegistroFondo.apuntar('Prueba: lectura encolada para dentro de ~10 s');
    await Workmanager().registerOneOffTask(
      _nombrePrueba,
      tareaLecturaObd,
      initialDelay: const Duration(seconds: 10),
      inputData: const {'motivo': 'prueba'},
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

/// Se llama UNA vez al arrancar la app: registra el despachador con el
/// sistema. Sin esto, el trabajo que encola Kotlin no sabe qué función Dart
/// ejecutar.
Future<void> prepararLecturaEnFondo() async {
  try {
    await Workmanager().initialize(despachadorDeFondo);
  } catch (e) {
    await RegistroFondo.apuntar('No se pudo registrar el segundo plano: $e');
  }
}

/// El punto de entrada del motor Dart sin pantalla. `vm:entry-point` evita
/// que el compilador lo tire por "no usado": lo usa Android, no la app.
@pragma('vm:entry-point')
void despachadorDeFondo() {
  Workmanager().executeTask((tarea, datos) async {
    // La comprobación de citas comparte despachador: WorkManager solo admite
    // uno por app. Va antes y aparte para no mezclar sus fallos con el OBD.
    if (tarea == tareaCitas) {
      try {
        await comprobarCitasEnFondo();
      } catch (e) {
        await RegistroFondo.apuntar('Citas: fallo: $e');
      }
      return true;
    }
    if (tarea != tareaLecturaObd) return true;
    final motivo = (datos?['motivo'] ?? '?').toString();
    try {
      await RegistroFondo.apuntar('Tarea arrancada (motivo: $motivo)');
      final ok = await leerYGuardarEnFondo(motivo: motivo);
      await RegistroFondo.apuntar(ok ? 'Lectura guardada' : 'Sin lectura');
    } catch (e) {
      // Lo que falle en segundo plano falla en silencio para el usuario, pero
      // NO para el registro: es lo único que permite saber qué pasó.
      await RegistroFondo.apuntar('Fallo: $e');
    }
    return true;
  });
}

/// Una lectura completa, guardada en las lecturas del coche. Devuelve false
/// si no había lector, coche, o datos.
Future<bool> leerYGuardarEnFondo({String motivo = ''}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final lector = await LectorRecordado.leer();
  if (lector == null) {
    await RegistroFondo.apuntar('No hay lector recordado: lee una vez a mano desde la pestaña OBD');
    return false;
  }

  /// Con dos disparadores puede caer una lectura encima de otra: si hace
  /// menos de diez minutos que se guardó una, no se repite. La prueba a mano
  /// se salta la espera: para eso es una prueba.
  final ultima = await AjustesLecturaAutomatica.ultimaLecturaDeFondo();
  if (motivo != 'prueba' &&
      ultima != null &&
      DateTime.now().toUtc().difference(ultima).inMinutes < 10) {
    await RegistroFondo.apuntar('Hace menos de 10 min de la última: no se repite');
    return false;
  }

  final almacen = Almacen();
  await almacen.cargar();
  final coche = almacen.coche;
  if (coche == null) {
    await RegistroFondo.apuntar('No hay coche dado de alta');
    return false;
  }

  await RegistroFondo.apuntar('Conectando con ${lector.nombre} (${lector.direccion})…');
  final enlace = await Bluetooth().conectar(lector.direccion, enSegundoPlano: true);
  final transporte = TransporteBluetooth(enlace);
  try {
    if (!await transporte.despertar()) {
      await RegistroFondo.apuntar('Enlace abierto pero no contesta como ELM327');
      return false;
    }
    final sesion = Sesion(transporte);
    if (!await sesion.iniciar()) {
      await RegistroFondo.apuntar('El adaptador no acepta los comandos de arranque');
      return false;
    }
    final lecturas = await sesion.leerLoQueHaya();
    final averias = await sesion.leerCodigos(3);
    final vin = await sesion.leerVin();
    if (lecturas.isEmpty && averias.isEmpty) {
      await RegistroFondo.apuntar('El coche no contesta (¿contacto dado?)');
      return false;
    }

    await almacen.guardarLectura(
        construirLecturaGuardada(coche.id, lecturas, averias, automatica: true));
    if (vin != null) await almacen.ponerBastidor(vin);
    await AjustesLecturaAutomatica._apuntarLecturaDeFondo();
    await RegistroFondo.apuntar('${lecturas.length} datos y ${averias.length} códigos guardados');
    return true;
  } finally {
    await transporte.cerrar();
  }
}

/// De lo leído a lo que se guarda. Lo usan la pantalla y el segundo plano,
/// para que una lectura sea la misma cosa venga de donde venga.
LecturaGuardada construirLecturaGuardada(
  String vehiculoId,
  List<Lectura> lecturas,
  List<Averia> averias, {
  bool automatica = false,
}) {
  int? km;
  final valores = <String, String>{};
  for (final l in lecturas) {
    if (l.pid == 0xA6 && l.valor != null) km = l.valor!.round();
    valores[l.nombre] = l.esNumero
        ? '${l.valor!.toStringAsFixed(decimalesDe(l.unidad))} ${l.unidad}'.trim()
        : (l.texto ?? '');
  }
  if (automatica) valores['Lectura'] = 'automática';
  return LecturaGuardada(
    vehiculoId: vehiculoId,
    cuando: DateTime.now().toUtc().toIso8601String(),
    km: km,
    codigos: averias.map((a) => a.codigo).toList(),
    valores: valores,
  );
}

/// Las revoluciones y los kilómetros no llevan decimales; los voltios, uno.
/// La tensión de una sonda lambda va a tres: su margen entero son 0,1 a 0,9
/// voltios, y con un decimal se pierde justo lo que se quería mirar.
int decimalesDe(String unidad) {
  if (unidad == 'V') return 3;
  if (unidad == 'L/h' || unidad == 'g/s' || unidad == 'h') return 1;
  return 0;
}
