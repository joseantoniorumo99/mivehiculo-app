/// LOS AVISOS DEL TALLER en la bandeja del móvil: "ha confirmado tu cita",
/// "no puede ese día", "te ha mandado el informe".
///
/// SON AVISOS LOCALES, no push: los pone la propia app cuando sincroniza y ve
/// que el taller ha hecho algo con una cita. No hay servicio de
/// notificaciones de pago por medio ni ningún servidor que sepa cuándo está
/// el móvil encendido. Lo que hay es:
///
/// 1. Al abrir la app o volver a ella se sincroniza (ya pasaba) y, si hay
///    novedad, se avisa en ese momento.
/// 2. Una comprobación periódica con WorkManager (cada media hora, cuando hay
///    red y solo con sesión) que baja las citas y avisa. Es lo que hace que
///    el aviso llegue con la app cerrada. Android la agrupa con las demás y
///    la salta si el móvil está ahorrando: puede tardar más, nunca cuesta
///    batería de más.
///
/// UN AVISO SALE UNA VEZ. `Cita.avisado` guarda el último suceso avisado, así
/// que lo detecte el camino que lo detecte, el segundo lo ve ya avisado.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../obd/lectura_fondo.dart' show RegistroFondo;
import 'almacen.dart';
import 'modelo.dart';
import 'nube.dart';

/// El nombre de la tarea Dart de la comprobación de citas. El despachador de
/// `lectura_fondo.dart` la reconoce por este nombre.
const String tareaCitas = 'es.regislab.mivehiculo.citas';
const String _nombrePeriodica = 'citas-periodica';

class Notificador {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _lista = false;

  /// Adónde quiere ir el dueño al tocar un aviso ('citas'). Lo escucha la
  /// concha de la app y abre la pantalla.
  static final abrir = ValueNotifier<String?>(null);

  static Future<void> preparar() async {
    if (_lista) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) => abrir.value = r.payload ?? 'citas',
      );
      _lista = true;
    } catch (e) {
      await RegistroFondo.apuntar('No se pudieron preparar los avisos: $e');
    }
  }

  /// Si la app se abrió tocando un aviso, adónde iba. Null si se abrió sola.
  static Future<String?> destinoDeArranque() async {
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) {
        return d!.notificationResponse?.payload ?? 'citas';
      }
    } catch (_) {}
    return null;
  }

  /// Android 13+ pregunta al dueño. Se pide en el momento en que tiene
  /// sentido —al mandar una cita: "te avisaremos cuando conteste"—, no al
  /// abrir la app por primera vez sin motivo.
  static Future<bool> pedirPermiso() async {
    await preparar();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> avisar(NovedadCita n) async {
    await preparar();
    try {
      await _plugin.show(
        n.cita.id.hashCode & 0x7fffffff,
        n.titulo,
        n.cuerpo,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'citas',
            'Citas con el taller',
            channelDescription: 'Cuando el taller confirma, rechaza o manda el informe',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(''),
          ),
        ),
        payload: 'citas',
      );
      await RegistroFondo.apuntar('Aviso: ${n.titulo}');
    } catch (e) {
      await RegistroFondo.apuntar('No se pudo avisar: $e');
    }
  }
}

/// Programa la comprobación periódica. Se llama al arrancar con sesión y al
/// mandar una cita; `keep` hace que llamarla veinte veces sea una sola tarea.
Future<void> programarComprobacionDeCitas() async {
  try {
    await Workmanager().registerPeriodicTask(
      _nombrePeriodica,
      tareaCitas,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    await RegistroFondo.apuntar('No se pudo programar la comprobación de citas: $e');
  }
}

Future<void> pararComprobacionDeCitas() async {
  try {
    await Workmanager().cancelByUniqueName(_nombrePeriodica);
  } catch (_) {}
}

/// Lo que ejecuta la tarea periódica. Devuelve cuántos avisos ha puesto.
Future<int> comprobarCitasEnFondo() async {
  WidgetsFlutterBinding.ensureInitialized();
  final almacen = Almacen();
  await almacen.cargar();
  final nube = Nube();
  await nube.recuperarSesion();
  if (!nube.conSesion) {
    await RegistroFondo.apuntar('Citas: sin sesión, nada que comprobar');
    return 0;
  }
  final novedades = await nube.sincronizarCitas(almacen);
  for (final n in novedades) {
    await Notificador.avisar(n);
  }
  await RegistroFondo.apuntar('Citas comprobadas: ${novedades.length} novedades');
  return novedades.length;
}
