/// MI VEHÍCULO — app nativa de Android.
///
/// La primera rebanada es SOLO el OBD, y a propósito: es lo único que no se
/// puede hacer de ninguna otra forma. Los ELM327 corrientes hablan Bluetooth
/// clásico (SPP), y eso ningún navegador lo alcanza — Web Bluetooth solo habla
/// BLE y Web Serial no existe en móvil. Android nativo sí.
///
/// El resto de la app (diario, expediente, mapa, citas) sigue viviendo en la
/// versión web mientras tanto, y se irá portando pantalla a pantalla.
library;

import 'package:flutter/material.dart';

import 'pantalla_obd.dart';

void main() => runApp(const MiVehiculoApp());

/// El tema sale de DESIGN.md de la versión web: «sala de exposición». Suelo
/// gris azulado, superficies blancas levantadas por sombra en vez de borde,
/// tinta pizarra y AZUL para la acción. El naranja queda solo como estado de
/// atención: hacía dos trabajos a la vez y el botón grande competía con el
/// aviso que tenía al lado.
class MiVehiculoApp extends StatelessWidget {
  const MiVehiculoApp({super.key});

  static const _suelo = Color(0xFFEEF2F7);
  static const _tinta = Color(0xFF1F2937);
  static const _azul = Color(0xFF2B6CB0);

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: _azul,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Mi Vehículo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: base.copyWith(
          primary: _azul,
          surface: Colors.white,
          onSurface: _tinta,
        ),
        scaffoldBackgroundColor: _suelo,
        appBarTheme: const AppBarTheme(
          backgroundColor: _suelo,
          surfaceTintColor: Colors.transparent,
          foregroundColor: _tinta,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x0E1F2D44)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            /// 48 px de alto, por encima del suelo de 44 que la web tiene
            /// comprometido: es lo que hace que un botón se toque con el dedo
            /// y no con la uña.
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: const Color(0xFF1F5B97),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const PantallaObd(),
    );
  }
}
