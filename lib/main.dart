/// MI VEHÍCULO — app nativa de Android. Versión 1.4.0: la vista del cliente.
///
/// Cinco pestañas: Inicio, Diario, OBD, Mapa y Perfil. Todo lo que sabe
/// hacer la web para el dueño del coche, más lo que la web no puede: hablar
/// con un ELM327 por Bluetooth clásico. Sin nada de talleres: el panel del
/// taller sigue en la web.
///
/// LAS REGLAS QUE MANDAN AQUÍ:
///
/// 1. El móvil es la verdad y la nube es la copia. La app arranca, funciona y
///    guarda sin cuenta y sin red. Con cuenta, cada cambio se sube en cuanto
///    hay red (con tres segundos de calma para no subir tecla a tecla), y al
///    entrar o al volver a la app se baja lo que haya de otros aparatos.
///
/// 2. El OBD se lee al ABRIR la app, una vez, y se cierra; en vivo solo
///    mientras se mira la pestaña; y en segundo plano solo si el dueño lo ha
///    encendido en «Lectura automática», que explica lo que cuesta. Nunca un
///    servicio permanente escuchando.
///
/// 3. La app se actualiza sola desde las releases de GitHub: comprueba con
///    calma (cada seis horas), avisa, y descarga e instala cuando se le dice.
///
/// 4. Lo que el taller hace con una cita (confirmar, rechazar, mandar el
///    informe) llega como aviso en la bandeja. Sin push de pago: lo detecta
///    la propia app al sincronizar, y una comprobación cada media hora con
///    la app cerrada. Un aviso sale una vez, lo vea quien lo vea.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos/actualizacion.dart';
import 'datos/almacen.dart';
import 'datos/modelo.dart';
import 'datos/notificador.dart';
import 'datos/nube.dart';
import 'estado.dart';
import 'obd/lectura_fondo.dart';
import 'pantalla_obd.dart';
import 'pantallas/acceso.dart';
import 'pantallas/citas.dart';
import 'pantallas/diario.dart';
import 'pantallas/inicio.dart';
import 'pantallas/mapa.dart';
import 'pantallas/perfil.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final almacen = Almacen();
  await almacen.cargar();
  // Registra con Android la función que ejecuta las lecturas en segundo
  // plano. Es solo el registro: no lee nada hasta que el dueño lo encienda.
  await prepararLecturaEnFondo();
  // El canal de avisos y quién atiende cuando se toca uno.
  await Notificador.preparar();
  runApp(MiVehiculoApp(almacen: almacen, nube: Nube(), actualizacion: Actualizacion()));
}

class MiVehiculoApp extends StatefulWidget {
  final Almacen almacen;
  final Nube nube;
  final Actualizacion actualizacion;
  const MiVehiculoApp({
    super.key,
    required this.almacen,
    required this.nube,
    required this.actualizacion,
  });

  @override
  State<MiVehiculoApp> createState() => _MiVehiculoAppState();
}

class _MiVehiculoAppState extends State<MiVehiculoApp> with WidgetsBindingObserver {
  Timer? _calma;
  StreamSubscription<void>? _escucha;
  StreamSubscription<NovedadCita>? _novedades;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.nube.recuperarSesion().then((_) {
      widget.nube.sincronizar(widget.almacen);
      // Con sesión, la comprobación de citas cada media hora queda programada
      // (si ya lo estaba, no se duplica). Sin sesión no hay nada que mirar.
      if (widget.nube.conSesion) programarComprobacionDeCitas();
    });
    widget.actualizacion.comprobar();
    // Cada novedad del taller que detecte la sincronización va a la bandeja.
    _novedades = widget.nube.novedades.listen(Notificador.avisar);
    // Cada cambio del usuario dispara una subida, con calma: escribir una
    // nota de tres frases no son tres subidas.
    _escucha = widget.almacen.cambios.listen((_) {
      _calma?.cancel();
      _calma = Timer(const Duration(seconds: 3), () => widget.nube.sincronizar(widget.almacen));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Al volver a la app se mira si hay algo nuevo en la cuenta, y —con la
    // calma de seis horas— si hay una versión nueva. También se recarga el
    // almacén por si una lectura en segundo plano guardó algo mientras tanto.
    if (estado == AppLifecycleState.resumed) {
      widget.almacen.recargar().then((_) => widget.nube.sincronizar(widget.almacen));
      widget.actualizacion.comprobar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calma?.cancel();
    _escucha?.cancel();
    _novedades?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Estado(
      almacen: widget.almacen,
      nube: widget.nube,
      actualizacion: widget.actualizacion,
      child: MaterialApp(
        title: 'Mi Vehículo',
        debugShowCheckedModeBanner: false,
        theme: temaMiVehiculo(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Concha(),
      ),
    );
  }
}

/// La concha: las cinco pestañas. `IndexedStack` para que cada una conserve
/// su estado al cambiar —y para que la pestaña del OBD arranque con la app y
/// haga su lectura automática aunque no se esté mirando—.
class Concha extends StatefulWidget {
  const Concha({super.key});
  @override
  State<Concha> createState() => _ConchaState();
}

class _ConchaState extends State<Concha> {
  int _pestana = 0;
  static const _nombres = ['inicio', 'diario', 'obd', 'mapa', 'perfil'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ofrecerCuentaLaPrimeraVez());
    // Tocar un aviso del taller abre las citas: con la app viva (escucha) o
    // si el aviso fue lo que la abrió (arranque).
    Notificador.abrir.addListener(_alTocarAviso);
    Notificador.destinoDeArranque().then((d) {
      if (d != null) Notificador.abrir.value = d;
    });
  }

  @override
  void dispose() {
    Notificador.abrir.removeListener(_alTocarAviso);
    super.dispose();
  }

  void _alTocarAviso() {
    final destino = Notificador.abrir.value;
    if (destino == null || !mounted) return;
    Notificador.abrir.value = null;
    if (destino == 'citas') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaCitas()));
    }
  }

  /// La primera vez que se abre la app —sin coche y sin cuenta— se ofrece
  /// entrar. Una sola vez: se apunta que ya se vio, y quien diga "sin cuenta"
  /// no vuelve a verlo salvo que lo busque en el perfil.
  Future<void> _ofrecerCuentaLaPrimeraVez() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('acceso_visto') ?? false) return;
    await p.setBool('acceso_visto', true);
    if (!mounted) return;
    final nube = context.nube;
    final almacen = context.almacen;
    if (!nube.arrancada) await nube.recuperarSesion();
    if (nube.conSesion || almacen.hayCoche || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaAcceso()));
  }

  void _irA(String destino) {
    final i = _nombres.indexOf(destino);
    if (i >= 0) setState(() => _pestana = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _pestana,
        children: [
          PantallaInicio(irA: _irA),
          const PantallaDiario(),
          // La pestaña del OBD sabe si se la está mirando: en vivo solo entonces.
          PantallaObd(activa: _pestana == 2),
          const PantallaMapa(),
          const PantallaPerfil(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Diario'),
          NavigationDestination(icon: Icon(Icons.bluetooth_searching), selectedIcon: Icon(Icons.bluetooth_connected), label: 'OBD'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
