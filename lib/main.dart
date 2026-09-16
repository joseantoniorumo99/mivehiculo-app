/// MI VEHÍCULO — app nativa de Android. Versión 1.0.0: la vista del cliente.
///
/// Cinco pestañas: Inicio, Diario, OBD, Mapa y Perfil. Todo lo que sabe
/// hacer la web para el dueño del coche, más lo que la web no puede: hablar
/// con un ELM327 por Bluetooth clásico. Sin nada de talleres: el panel del
/// taller sigue en la web.
///
/// LAS DOS REGLAS QUE MANDAN AQUÍ:
///
/// 1. El móvil es la verdad y la nube es la copia. La app arranca, funciona y
///    guarda sin cuenta y sin red. Con cuenta, cada cambio se sube en cuanto
///    hay red (con tres segundos de calma para no subir tecla a tecla), y al
///    entrar o al volver a la app se baja lo que haya de otros aparatos.
///
/// 2. El OBD se lee al ABRIR la app, una vez, y se cierra. Si el lector
///    contesta es que estás en el coche con el contacto dado —el lector se
///    alimenta del propio conector—, y esa lectura se guarda sola en las
///    lecturas. Eso es "saber cuándo conduces" sin dejar nada escuchando en
///    segundo plano, que gasta batería y coge el puerto para todo el mundo.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos/almacen.dart';
import 'datos/nube.dart';
import 'estado.dart';
import 'pantalla_obd.dart';
import 'pantallas/acceso.dart';
import 'pantallas/diario.dart';
import 'pantallas/inicio.dart';
import 'pantallas/mapa.dart';
import 'pantallas/perfil.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final almacen = Almacen();
  await almacen.cargar();
  runApp(MiVehiculoApp(almacen: almacen, nube: Nube()));
}

class MiVehiculoApp extends StatefulWidget {
  final Almacen almacen;
  final Nube nube;
  const MiVehiculoApp({super.key, required this.almacen, required this.nube});

  @override
  State<MiVehiculoApp> createState() => _MiVehiculoAppState();
}

class _MiVehiculoAppState extends State<MiVehiculoApp> with WidgetsBindingObserver {
  Timer? _calma;
  StreamSubscription<void>? _escucha;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.nube.recuperarSesion().then((_) => widget.nube.sincronizar(widget.almacen));
    // Cada cambio del usuario dispara una subida, con calma: escribir una
    // nota de tres frases no son tres subidas.
    _escucha = widget.almacen.cambios.listen((_) {
      _calma?.cancel();
      _calma = Timer(const Duration(seconds: 3), () => widget.nube.sincronizar(widget.almacen));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Al volver a la app se mira si hay algo nuevo en la cuenta.
    if (estado == AppLifecycleState.resumed) widget.nube.sincronizar(widget.almacen);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calma?.cancel();
    _escucha?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Estado(
      almacen: widget.almacen,
      nube: widget.nube,
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
          const PantallaObd(),
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
