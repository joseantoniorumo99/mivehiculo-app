/// EL CATÁLOGO DE COCHES: 52 marcas, 955 modelos y 3.905 motorizaciones.
///
/// GENERADO, no escrito a mano. Sale de las matriculaciones REALES en España
/// que publica la Agencia Europea de Medio Ambiente en su base de vigilancia
/// de CO2: datos abiertos, gratis y sin clave. El fichero vive en
/// `assets/catalogo.json` y lo regenera la herramienta de la web.
///
/// POR QUÉ NO SE PIDE POR RED: son 99 KB. Bajarlos cuesta más que llevarlos
/// dentro, y llevarlos dentro hace que dar de alta un coche funcione en un
/// aparcamiento sin cobertura, que es exactamente donde uno está cuando
/// decide apuntar su coche en una app de coches.
///
/// LO QUE ESTE CATÁLOGO NO CUBRE: años anteriores a 2010 ni posteriores a
/// 2022, porque la fuente se queda ahí. Eso no es un fallo que se arregle con
/// código: es hasta dónde llegan los datos publicados. Un coche fuera de ese
/// rango cae al selector de combustible a mano, y la pantalla lo dice en vez
/// de dejar al usuario buscando su modelo en una lista donde no está.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Una motorización: [combustible, cm3, CV, primerAño, últimoAño].
class Motor {
  final String combustible;
  final int cilindrada;
  final int cv;
  final int desde;
  final int hasta;
  const Motor(this.combustible, this.cilindrada, this.cv, this.desde, this.hasta);

  /// Lo que se lee en la lista. Los ceros de la fuente significan "no consta",
  /// así que no se escriben: "1.6 Diésel" es mejor que "1.6 Diésel 0 CV".
  String get etiqueta {
    final partes = <String>[];
    if (cilindrada > 0) partes.add((cilindrada / 1000).toStringAsFixed(1));
    partes.add(combustible);
    if (cv > 0) partes.add('$cv CV');
    return partes.join(' ');
  }

  /// "2016–2019" o "2019". Va a la vista para que el dueño vea si el motor
  /// cuadra con su año, en vez de que la app decida por él y se equivoque.
  String get anios => desde == hasta ? '$desde' : '$desde–$hasta';

  /// La etiqueta con los años: es la que identifica una motorización sin
  /// ambigüedad en un desplegable (dos "1.6 Diésel" con años distintos son
  /// dos entradas distintas de la fuente).
  String get etiquetaLarga => '$etiqueta · $anios';

  /// Los cm³ exactos. Es lo que permite reconocer un motor por su nombre
  /// comercial cuando la fuente no lo trae: 1.560 cm³ en un PSA es el HDi.
  String get detalle {
    final partes = <String>[];
    if (cilindrada > 0) partes.add('${_miles(cilindrada)} cm³');
    if (cv == 0) partes.add('potencia no consta en la fuente');
    return partes.join(' · ');
  }

  static String _miles(int n) {
    final s = n.toString();
    return s.length > 3 ? '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}' : s;
  }

  bool cubre(int anio) => anio >= desde && anio <= hasta;
}

class Catalogo {
  final List<String> combustibles;
  final Map<String, Map<String, List<Motor>>> marcas;
  const Catalogo(this.combustibles, this.marcas);

  static Catalogo? _cargado;
  static Catalogo? get cargado => _cargado;

  /// Primer y último año que cubre la fuente. Se calculan del propio catálogo
  /// y no se escriben a mano: si algún día se regenera con datos más nuevos,
  /// el texto de la pantalla se actualiza solo en vez de mentir.
  int get primerAnio {
    var min = 9999;
    for (final m in marcas.values) {
      for (final ms in m.values) {
        for (final x in ms) {
          if (x.desde < min) min = x.desde;
        }
      }
    }
    return min;
  }

  int get ultimoAnio {
    var max = 0;
    for (final m in marcas.values) {
      for (final ms in m.values) {
        for (final x in ms) {
          if (x.hasta > max) max = x.hasta;
        }
      }
    }
    return max;
  }

  List<String> get listaMarcas => marcas.keys.toList()..sort();

  List<String> modelosDe(String marca) {
    final m = marcas[marca];
    if (m == null) return const [];
    return m.keys.toList()..sort();
  }

  /// Las motorizaciones de un modelo, TODAS, ordenadas: primero las que se
  /// vendían el año dado, luego las más cercanas a ese año.
  ///
  /// Antes se FILTRABAN por año y se escondían las demás, y eso se comió el
  /// 1.6 HDi de un C3 real: la matrícula había datado el coche en 2020, ese
  /// motor se vendió hasta 2019, y como otros motores sí cubrían 2020 la lista
  /// salía sin él. Un año mal puesto no puede borrar el motor de verdad; se
  /// ordena y se enseña el rango de años para que el dueño decida.
  List<Motor> motoresDe(String marca, String modelo, {int? anio}) {
    final lista = [...(marcas[marca]?[modelo] ?? const <Motor>[])];
    if (anio == null) return lista;
    int distancia(Motor m) =>
        m.cubre(anio) ? 0 : (anio < m.desde ? m.desde - anio : anio - m.hasta);
    lista.sort((a, b) {
      final d = distancia(a).compareTo(distancia(b));
      if (d != 0) return d;
      final c = a.cilindrada.compareTo(b.cilindrada);
      return c != 0 ? c : a.cv.compareTo(b.cv);
    });
    return lista;
  }

  /// Los años en que se vendió ese modelo, de más nuevo a más viejo.
  List<int> aniosDe(String marca, String modelo) {
    final lista = marcas[marca]?[modelo] ?? const <Motor>[];
    final anios = <int>{};
    for (final m in lista) {
      for (var a = m.desde; a <= m.hasta; a++) {
        anios.add(a);
      }
    }
    final orden = anios.toList()..sort((a, b) => b.compareTo(a));
    return orden;
  }

  /// Carga el catálogo una sola vez. Si falla devuelve null y quien llama
  /// tiene que seguir funcionando: el alta con campos de texto a mano es peor
  /// experiencia, pero es una experiencia; una pantalla rota no lo es.
  static Future<Catalogo?> cargar() async {
    if (_cargado != null) return _cargado;
    try {
      final texto = await rootBundle.loadString('assets/catalogo.json');
      final j = jsonDecode(texto) as Map<String, dynamic>;
      final combustibles =
          (j['combustibles'] as List).map((c) => c.toString()).toList();
      final marcas = <String, Map<String, List<Motor>>>{};
      (j['marcas'] as Map<String, dynamic>).forEach((marca, modelos) {
        final m = <String, List<Motor>>{};
        (modelos as Map<String, dynamic>).forEach((modelo, motores) {
          m[modelo] = (motores as List).map((x) {
            final f = (x as List).map((n) => (n as num).toInt()).toList();
            return Motor(
              f[0] < combustibles.length ? combustibles[f[0]] : 'Gasolina',
              f[1],
              f[2],
              f[3],
              f[4],
            );
          }).toList();
        });
        marcas[marca] = m;
      });
      _cargado = Catalogo(combustibles, marcas);
      return _cargado;
    } catch (_) {
      return null;
    }
  }
}
