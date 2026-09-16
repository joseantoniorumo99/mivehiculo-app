/// EL TEMA: «sala de exposición», tal como lo fija el DESIGN.md de la web.
///
/// Suelo gris azulado, superficies blancas levantadas por sombra en vez de
/// borde, tinta pizarra y AZUL para la acción. El naranja queda solo como
/// estado de atención: en la versión anterior hacía dos trabajos a la vez
/// —botón principal y aviso— y el botón grande competía con el aviso que
/// tenía al lado. Se llegó aquí después de dos correcciones del dueño de la
/// app: «quiero una paleta más blanco negro» y luego «más suave, sensación de
/// concesionario no tan agresivo, con su azulito».
///
/// EL COLOR LEGISLA ESTADOS y nada más: teal = en regla, naranja = atención,
/// rojo = urgente, azul = esto se pulsa. Un color fuera de esa ley es ruido.
library;

import 'package:flutter/material.dart';

class Tono {
  static const suelo = Color(0xFFEEF2F7);
  static const sueloAlto = Color(0xFFF8FAFC);
  static const superficie = Color(0xFFFFFFFF);
  static const tinta = Color(0xFF1F2937);
  static const tintaSuave = Color(0xFF556275);
  static const tintaApagada = Color(0xFF5F6B7F);
  static const regla = Color(0x141F2D44);

  static const azul = Color(0xFF2B6CB0);
  static const azulTinta = Color(0xFF1F5B97);
  static const azulFilm = Color(0x1A2B6CB0);

  static const naranjaTinta = Color(0xFF8A5200);
  static const naranjaFilm = Color(0x1FFCA311);
  static const naranjaRegla = Color(0x57FCA311);

  static const tealTinta = Color(0xFF146170);
  static const tealFilm = Color(0x1A1F7A8C);

  static const rojoTinta = Color(0xFFB5272D);
  static const rojoFilm = Color(0x1AE5484D);

  /// La sombra es azul-negra, no negra: sobre un suelo azulado, una sombra
  /// pura negra se lee como gris sucio.
  static const alzado = Color(0x141A2740);
}

ThemeData temaMiVehiculo() {
  final base = ColorScheme.fromSeed(
    seedColor: Tono.azul,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: base.copyWith(
      primary: Tono.azul,
      onPrimary: Colors.white,
      surface: Tono.superficie,
      onSurface: Tono.tinta,
      onSurfaceVariant: Tono.tintaSuave,
      tertiary: Tono.naranjaTinta,
      tertiaryContainer: Tono.naranjaFilm,
      onTertiaryContainer: Tono.naranjaTinta,
      error: Tono.rojoTinta,
      outline: Tono.regla,
    ),
    scaffoldBackgroundColor: Tono.suelo,
    appBarTheme: const AppBarTheme(
      backgroundColor: Tono.suelo,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Tono.tinta,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Tono.tinta,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: Tono.superficie,
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
        /// comprometido: es lo que hace que un botón se toque con el dedo y
        /// no con la uña.
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Tono.azulTinta,
        side: const BorderSide(color: Tono.azul),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: Tono.azulTinta,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tono.superficie,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x261F2D44)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0x261F2D44)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Tono.azul, width: 1.5),
      ),
      labelStyle: const TextStyle(color: Tono.tintaSuave),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Tono.superficie,
      indicatorColor: Tono.azulFilm,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((estados) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: estados.contains(WidgetState.selected)
                ? Tono.azulTinta
                : Tono.tintaSuave,
          )),
      iconTheme: WidgetStateProperty.resolveWith((estados) => IconThemeData(
            color: estados.contains(WidgetState.selected)
                ? Tono.azulTinta
                : Tono.tintaSuave,
          )),
    ),
    dividerTheme: const DividerThemeData(color: Tono.regla, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Tono.tinta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Tono.tintaSuave,
      textColor: Tono.tinta,
    ),
  );
}

// ---------------------------------------------------------------
// Piezas que se repiten por toda la app
// ---------------------------------------------------------------

/// La superficie que sube: blanco sobre el suelo, levantada por sombra y no
/// por borde. Es la unidad básica de la sala de exposición.
class Tarjeta extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;

  const Tarjeta({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cuerpo = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? Tono.superficie,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Tono.alzado, blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? cuerpo
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: cuerpo),
            ),
    );
  }
}

class TituloSeccion extends StatelessWidget {
  final String texto;
  final Widget? accion;
  const TituloSeccion(this.texto, {super.key, this.accion});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Tono.tinta,
                      letterSpacing: -0.2)),
            ),
            ?accion,
          ],
        ),
      );
}

enum TonoEstado { calma, atencion, urgente, neutro, accion }

/// El chip de estado. El color LEGISLA: teal en regla, naranja atención, rojo
/// urgente. Nunca se usa para decorar.
class ChipEstado extends StatelessWidget {
  final String texto;
  final TonoEstado tono;
  const ChipEstado(this.texto, {super.key, this.tono = TonoEstado.neutro});

  @override
  Widget build(BuildContext context) {
    final (fondo, tinta) = switch (tono) {
      TonoEstado.calma => (Tono.tealFilm, Tono.tealTinta),
      TonoEstado.atencion => (Tono.naranjaFilm, Tono.naranjaTinta),
      TonoEstado.urgente => (Tono.rojoFilm, Tono.rojoTinta),
      TonoEstado.accion => (Tono.azulFilm, Tono.azulTinta),
      TonoEstado.neutro => (const Color(0x121F2D44), Tono.tintaSuave),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: tinta)),
    );
  }
}

/// Un aviso en línea: qué pasa, y debajo qué hacer. Las dos cosas con peso
/// distinto; todo en negrita no es un aviso, es un grito.
class Recuadro extends StatelessWidget {
  final String texto;
  final String? consejo;
  final TonoEstado tono;
  final Widget? accion;
  const Recuadro(this.texto,
      {super.key, this.consejo, this.tono = TonoEstado.atencion, this.accion});

  @override
  Widget build(BuildContext context) {
    final (fondo, borde, tinta) = switch (tono) {
      TonoEstado.calma => (Tono.tealFilm, Tono.tealTinta, Tono.tealTinta),
      TonoEstado.urgente => (Tono.rojoFilm, Tono.rojoTinta, Tono.rojoTinta),
      TonoEstado.accion => (Tono.azulFilm, Tono.azul, Tono.azulTinta),
      _ => (Tono.naranjaFilm, Tono.naranjaRegla, Tono.naranjaTinta),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: borde.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto,
              style: TextStyle(fontWeight: FontWeight.w600, color: tinta)),
          if (consejo != null) ...[
            const SizedBox(height: 4),
            Text(consejo!, style: const TextStyle(color: Tono.tinta)),
          ],
          if (accion != null) ...[
            const SizedBox(height: 6),
            ?accion,
          ],
        ],
      ),
    );
  }
}

/// El estado vacío: dice qué no hay, por qué y qué hacer. Nunca una pantalla
/// en blanco, que parece un fallo.
class Vacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  final Widget? accion;
  const Vacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.texto,
    this.accion,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: Tono.azulFilm, shape: BoxShape.circle),
              child: Icon(icono, color: Tono.azulTinta, size: 30),
            ),
            const SizedBox(height: 14),
            Text(titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(texto,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Tono.tintaSuave, height: 1.4)),
            if (accion != null) ...[
              const SizedBox(height: 18),
              ?accion,
            ],
          ],
        ),
      );
}

/// Una fila etiqueta–valor, para fichas y expedientes.
class FilaDato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final bool monoespaciada;
  const FilaDato(this.etiqueta, this.valor,
      {super.key, this.monoespaciada = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Text(etiqueta,
                  style: const TextStyle(color: Tono.tintaSuave)),
            ),
            Expanded(
              child: Text(valor,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: monoespaciada ? 'monospace' : null,
                  )),
            ),
          ],
        ),
      );
}

/// El pozo azul del icono: el círculo tenue con el icono en tinta azul.
class PozoIcono extends StatelessWidget {
  final IconData icono;
  final double tamano;
  final Color? fondo;
  final Color? tinta;
  const PozoIcono(this.icono,
      {super.key, this.tamano = 40, this.fondo, this.tinta});

  @override
  Widget build(BuildContext context) => Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
            color: fondo ?? Tono.azulFilm, shape: BoxShape.circle),
        child: Icon(icono, color: tinta ?? Tono.azulTinta, size: tamano * 0.5),
      );
}

void avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Confirmación destructiva. Devuelve true solo si se pulsó la acción roja.
Future<bool> confirmar(BuildContext context,
    {required String titulo,
    required String texto,
    String accion = 'Borrar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: Tono.rojoTinta),
          child: Text(accion),
        ),
      ],
    ),
  );
  return r ?? false;
}
