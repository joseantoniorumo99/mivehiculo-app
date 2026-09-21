/// LOS SITIOS DEL MAPA: talleres, gasolineras, lavaderos, recambios,
/// desguaces y estaciones de ITV.
///
/// Salen de OpenStreetMap, no de Google Places. Google cobra 17-40 $ por cada
/// mil llamadas y PROHÍBE guardar nombres, teléfonos y horarios —hay que
/// pedirlos en vivo con su atribución—, así que una app que quiera funcionar
/// en un garaje sin cobertura no puede apoyarse en ellos. Los datos de OSM son
/// ODbL: se pueden cachear, y se cachean.
///
/// Y no se piden a Overpass directamente, sino a `/api/lugares`, nuestra
/// propia función en Cloudflare. Medido: overpass-api.de contesta 406 a
/// cualquier User-Agent que no le guste, los otros espejos tardaban un
/// minuto, y la función además guarda la respuesta en el borde una semana,
/// así que el segundo que mire esa zona no espera nada. Los talleres no se
/// mueven.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// La web desde la que se sirve la función. Es la misma app, en su versión
/// de ordenador.
const String servidorLugares = 'https://motora-42w.pages.dev';

enum TipoLugar { taller, gasolinera, lavadero, repuestos, desguace }

const Map<TipoLugar, String> nombreTipoLugar = {
  TipoLugar.taller: 'Talleres',
  TipoLugar.gasolinera: 'Gasolineras',
  TipoLugar.lavadero: 'Lavaderos',
  TipoLugar.repuestos: 'Repuestos',
  TipoLugar.desguace: 'Desguaces',
};

/// Las etiquetas `service:vehicle:*` de OSM que un taller marca a "yes", y
/// cómo se llaman en la app. Es lo que permite buscar "talleres que hagan
/// frenos" para un aviso de frenos.
const Map<String, String> _serviciosOsm = {
  'service:vehicle:oil_change': 'Aceite',
  'service:vehicle:brake_repair': 'Frenos',
  'service:vehicle:tyres': 'Neumáticos',
  'service:vehicle:wheel_alignment': 'Alineado',
  'service:vehicle:air_conditioning': 'Aire acondicionado',
  'service:vehicle:diagnostics': 'Diagnosis OBD',
  'service:vehicle:electrical': 'Electricidad',
  'service:vehicle:painting': 'Chapa y pintura',
  'service:vehicle:body_repair': 'Chapa y pintura',
  'service:vehicle:battery': 'Batería',
  'service:vehicle:suspension_repair': 'Suspensión',
  'service:vehicle:engine_repair': 'Mecánica general',
  'service:vehicle:repairs': 'Mecánica general',
  'service:vehicle:inspection': 'Pre-ITV',
};

/// Qué servicio buscar en un taller para cada tipo de mantenimiento del
/// diario. "otro" no tiene servicio concreto: cualquier taller vale.
const Map<String, String> servicioParaTipo = {
  'aceite': 'Aceite',
  'rueda': 'Neumáticos',
  'freno': 'Frenos',
  'itv': 'ITV',
  'filtro': 'Mecánica general',
  'bateria': 'Batería',
  'correa': 'Mecánica general',
  'revision': 'Mecánica general',
};

/// La etiqueta con la que el servidor conoce a un taller: su id de
/// OpenStreetMap sin nada que no sea letra o número ("osm-node-11" →
/// "osmnode11"). Es la MISMA función que usa la Function de citas y la web;
/// si se separan, el móvil deja de encontrar la ficha del taller.
String etiquetaDeTaller(String lugarId) {
  final e = lugarId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  return e.length > 36 ? e.substring(0, 36) : e;
}

/// Un servicio tal y como lo publicó el taller: nombre, precio de partida
/// (o nada) y tiempo aproximado (o nada).
class ServicioPublicado {
  final String nombre;
  final double? precio;
  final String tiempo;
  const ServicioPublicado(this.nombre, this.precio, this.tiempo);
}

/// La ficha que el taller publicó desde su panel. Es lo que manda sobre lo
/// que diga OpenStreetMap: lo escribió él.
class FichaTaller {
  /// El id de la fila, que es la etiqueta del taller ("osmnode123",
  /// "propio1789…"). Es lo que se manda como tallerId al pedir cita.
  final String id;
  final String nombre;
  final String telefono;
  final String direccion;
  final String web;
  final double? lat;
  final double? lon;

  /// Siete tramos de texto, lunes a domingo, como los guarda la web
  /// ("09:00-14:00,16:00-19:00"; vacío = cerrado).
  final List<String> horario;
  final List<ServicioPublicado> servicios;
  final List<String> extras;
  final String actualizado; // ISO-8601 o vacío
  const FichaTaller({
    this.id = '',
    this.nombre = '',
    this.telefono = '',
    this.direccion = '',
    this.web = '',
    this.lat,
    this.lon,
    this.horario = const [],
    this.servicios = const [],
    this.extras = const [],
    this.actualizado = '',
  });

  bool get conPunto => lat != null && lon != null;

  /// El taller publicado como un sitio del mapa, para los que no están en
  /// OpenStreetMap (dados de alta a mano con su dirección). Su id es la
  /// etiqueta, así que la cita que se pida le llega igual.
  Lugar comoLugar() => Lugar(
        id: id,
        tipo: TipoLugar.taller,
        nombre: nombre.isEmpty ? 'Taller' : nombre,
        lat: lat ?? 0,
        lon: lon ?? 0,
        direccion: direccion,
        telefono: telefono,
        web: web,
        horario: horarioDeTramos(horario),
        servicios: servicios.map((s) => s.nombre).toList(),
      );

  static FichaTaller deFila(Map<String, dynamic> d) {
    List<dynamic> lista(Object? v) {
      if (v is List) return v;
      if (v is String && v.trim().startsWith('[')) {
        try {
          final x = jsonDecode(v);
          if (x is List) return x;
        } catch (_) {}
      }
      return const [];
    }

    double? numero(Object? v) => v == null ? null : double.tryParse(v.toString());
    return FichaTaller(
      id: (d[r'$id'] ?? '').toString(),
      nombre: (d['nombre'] ?? '').toString(),
      telefono: (d['telefono'] ?? '').toString(),
      direccion: (d['direccion'] ?? '').toString(),
      web: (d['web'] ?? '').toString(),
      lat: numero(d['lat']),
      lon: numero(d['lon']),
      horario: lista(d['horario']).map((e) => e.toString()).toList(),
      servicios: lista(d['servicios'])
          .whereType<Map>()
          .map((s) => ServicioPublicado(
                (s['nombre'] ?? '').toString(),
                s['precio'] == null ? null : double.tryParse(s['precio'].toString()),
                (s['tiempo'] ?? '').toString(),
              ))
          .where((s) => s.nombre.isNotEmpty)
          .toList(),
      extras: lista(d['extras']).map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
      actualizado: (d['actualizado'] ?? '').toString(),
    );
  }
}

/// De los siete tramos de texto de la web ("09:00-14:00,16:00-19:00") al
/// horario del mapa (minutos desde medianoche por día). Null si no hay nada.
List<List<List<int>>>? horarioDeTramos(List<String> dias) {
  if (dias.length != 7) return null;
  int? minutos(String h) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(h.trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  var alguno = false;
  final salida = dias.map((dia) {
    final tramos = <List<int>>[];
    for (final t in dia.split(',')) {
      final partes = t.split('-');
      if (partes.length != 2) continue;
      final a = minutos(partes[0]), b = minutos(partes[1]);
      if (a == null || b == null || b <= a) continue;
      tramos.add([a, b]);
      alguno = true;
    }
    return tramos;
  }).toList();
  return alguno ? salida : null;
}

class Lugar {
  final String id;
  final TipoLugar tipo;
  final String nombre;
  final double lat;
  final double lon;
  final String direccion;
  final String telefono;
  final String web;

  /// Horario por día, lunes = 0. Cada día es una lista de tramos en minutos
  /// desde medianoche: [[540, 780], [960, 1200]]. Vacío = cerrado ese día.
  /// Null = no se ha podido interpretar (y entonces `horarioTexto` lleva el
  /// original de OSM tal cual).
  final List<List<List<int>>>? horario;
  final String horarioTexto;
  final List<String> servicios;
  final bool esItv;

  const Lugar({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.lat,
    required this.lon,
    this.direccion = '',
    this.telefono = '',
    this.web = '',
    this.horario,
    this.horarioTexto = '',
    this.servicios = const [],
    this.esItv = false,
  });

  bool get esTaller => tipo == TipoLugar.taller;

  /// El mismo sitio con otros servicios: los que publicó el taller mandan
  /// sobre los de OpenStreetMap al pedir cita.
  Lugar conServicios(List<String> nuevos) => Lugar(
        id: id,
        tipo: tipo,
        nombre: nombre,
        lat: lat,
        lon: lon,
        direccion: direccion,
        telefono: telefono,
        web: web,
        horario: horario,
        horarioTexto: horarioTexto,
        servicios: nuevos,
        esItv: esItv,
      );

  bool hace(String servicio) =>
      servicios.any((s) => s.toLowerCase() == servicio.toLowerCase());

  /// null = no se sabe. Un sitio sin horario en OSM no está "cerrado", está
  /// sin datos, y pintarlo cerrado un martes a las once hace desconfiar de
  /// todo lo demás.
  bool? abiertoAhora([DateTime? ahora]) {
    if (horario == null) return null;
    final h = ahora ?? DateTime.now();
    final tramos = horario![h.weekday - 1];
    final min = h.hour * 60 + h.minute;
    return tramos.any((t) => min >= t[0] && min < t[1]);
  }

  /// "Abierto · cierra a las 20:00" / "Cerrado · abre a las 9:00" / null.
  String? estadoAhora([DateTime? ahora]) {
    final abierto = abiertoAhora(ahora);
    if (abierto == null) return null;
    final h = ahora ?? DateTime.now();
    final min = h.hour * 60 + h.minute;
    final tramos = horario![h.weekday - 1];
    if (abierto) {
      final t = tramos.firstWhere((t) => min >= t[0] && min < t[1]);
      return 'Abierto · cierra a las ${_hora(t[1])}';
    }
    final luego = tramos.where((t) => t[0] > min).toList();
    if (luego.isNotEmpty) return 'Cerrado · abre a las ${_hora(luego.first[0])}';
    return 'Cerrado ahora';
  }

  Map<String, dynamic> aJson() => {
        'id': id,
        'tipo': tipo.name,
        'nombre': nombre,
        'lat': lat,
        'lon': lon,
        'direccion': direccion,
        'telefono': telefono,
        'web': web,
        'horario': horario,
        'horarioTexto': horarioTexto,
        'servicios': servicios,
        'esItv': esItv,
      };

  static Lugar deJson(Map<String, dynamic> j) => Lugar(
        id: j['id'] as String,
        tipo: TipoLugar.values.firstWhere((t) => t.name == j['tipo'],
            orElse: () => TipoLugar.taller),
        nombre: (j['nombre'] ?? '') as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        direccion: (j['direccion'] ?? '') as String,
        telefono: (j['telefono'] ?? '') as String,
        web: (j['web'] ?? '') as String,
        horario: j['horario'] == null
            ? null
            : (j['horario'] as List)
                .map((d) => (d as List)
                    .map((t) => (t as List).map((n) => (n as num).toInt()).toList())
                    .toList())
                .toList(),
        horarioTexto: (j['horarioTexto'] ?? '') as String,
        servicios: ((j['servicios'] ?? []) as List).map((s) => s.toString()).toList(),
        esItv: (j['esItv'] ?? false) as bool,
      );
}

String _hora(int min) {
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '$h:00' : '$h:${m.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------
// OSM → Lugar
// ---------------------------------------------------------------

TipoLugar? _tipoDesdeEtiquetas(Map<String, dynamic> t) {
  if (t['amenity'] == 'fuel') return TipoLugar.gasolinera;
  if (t['amenity'] == 'car_wash') return TipoLugar.lavadero;
  if (t['industrial'] == 'scrap_yard' || t['shop'] == 'scrap_yard') {
    return TipoLugar.desguace;
  }
  if (t['shop'] == 'car_parts') {
    return t['second_hand'] == 'only' ? TipoLugar.desguace : TipoLugar.repuestos;
  }
  if (t['shop'] == 'car_repair' || t['amenity'] == 'vehicle_inspection') {
    return TipoLugar.taller;
  }
  return null;
}

String _direccion(Map<String, dynamic> t) {
  final calle = [t['addr:street'], t['addr:housenumber']]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(' ');
  final pueblo = (t['addr:city'] ?? t['addr:town'] ?? t['addr:village'] ?? '') as String;
  return [calle, pueblo].where((s) => s.isNotEmpty).join(', ');
}

const Map<TipoLugar, String> _nombreDeCortesia = {
  TipoLugar.taller: 'Taller sin nombre',
  TipoLugar.gasolinera: 'Gasolinera',
  TipoLugar.lavadero: 'Lavadero',
  TipoLugar.repuestos: 'Tienda de recambios',
  TipoLugar.desguace: 'Desguace',
};

/// Un elemento de Overpass → un Lugar, o null si no es de los nuestros o no
/// tiene coordenadas.
Lugar? lugarDeOsm(Map<String, dynamic> elemento) {
  final t = Map<String, dynamic>.from((elemento['tags'] ?? {}) as Map);
  final tipo = _tipoDesdeEtiquetas(t);
  if (tipo == null) return null;
  final centro = elemento['center'] as Map?;
  final lat = (elemento['lat'] ?? centro?['lat']) as num?;
  final lon = (elemento['lon'] ?? centro?['lon']) as num?;
  if (lat == null || lon == null) return null;

  final servicios = <String>[];
  _serviciosOsm.forEach((clave, nombre) {
    if (t[clave] == 'yes' && !servicios.contains(nombre)) servicios.add(nombre);
  });

  /// Una estación de ITV hace ITV, y punto. Etiquetarla "Mecánica general" —
  /// que es lo que pasaba por caer en el mismo tipo que un taller— mentía en
  /// la lista y dejaba el aviso de ITV sin ningún sitio donde hacerla, porque
  /// el escaparate busca por servicio. Es el único aviso que tiene TODO
  /// usuario nuevo, así que ese callejón lo veía todo el mundo el primer día.
  final esItv = t['amenity'] == 'vehicle_inspection';
  if (esItv && !servicios.contains('ITV')) servicios.insert(0, 'ITV');
  if (tipo == TipoLugar.taller && !esItv && servicios.isEmpty) {
    servicios.add('Mecánica general');
  }

  final textoHorario = (t['opening_hours'] ?? '') as String;
  final horario = traducirOpeningHours(textoHorario);

  return Lugar(
    id: 'osm-${elemento['type']}-${elemento['id']}',
    tipo: tipo,
    nombre: (t['name'] ?? t['brand'] ?? t['operator'] ?? _nombreDeCortesia[tipo]!)
        as String,
    lat: lat.toDouble(),
    lon: lon.toDouble(),
    direccion: _direccion(t),
    telefono: (t['phone'] ?? t['contact:phone'] ?? '') as String,
    web: (t['website'] ?? t['contact:website'] ?? '') as String,
    horario: horario,
    horarioTexto: horario == null ? textoHorario : '',
    servicios: servicios,
    esItv: esItv,
  );
}

// ---------------------------------------------------------------
// opening_hours de OSM → tramos por día
// ---------------------------------------------------------------

const List<String> _diasOsm = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// Traduce el subconjunto habitual de `opening_hours`:
///   "Mo-Fr 09:00-13:00,16:00-20:00; Sa 09:00-13:00"
///   "Mo-Sa 08:00-20:00"    "24/7"    "Mo-Fr 08:00-18:00; PH off"
/// Lo que no entienda devuelve null, y entonces la ficha enseña el texto
/// original en vez de un horario inventado. Aquí adivinar es peor que
/// callarse: "cerrado" cuando está abierto manda a alguien a otro sitio.
List<List<List<int>>>? traducirOpeningHours(String texto) {
  final limpio = texto.trim();
  if (limpio.isEmpty) return null;
  if (limpio == '24/7') {
    return List.generate(7, (_) => [
          [0, 24 * 60]
        ]);
  }

  final salida = List<List<List<int>>>.generate(7, (_) => []);
  var algo = false;

  for (final reglaBruta in limpio.split(';')) {
    final regla = reglaBruta.trim();
    if (regla.isEmpty || regla.startsWith('PH') || regla.startsWith('SH')) {
      continue; // festivos: no sabemos cuándo caen, se ignoran
    }
    final m = RegExp(r'^([A-Za-z,\-\s]*?)\s*((?:\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}\s*,?\s*)+|off|closed)$')
        .firstMatch(regla);
    if (m == null) return null;

    final dias = _diasDe(m.group(1)!.trim());
    if (dias == null) return null;
    final horas = m.group(2)!.trim();
    if (horas == 'off' || horas == 'closed') {
      for (final d in dias) {
        salida[d] = [];
      }
      algo = true;
      continue;
    }
    final tramos = <List<int>>[];
    for (final tramo in horas.split(',')) {
      final h = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})').firstMatch(tramo.trim());
      if (h == null) return null;
      final desde = int.parse(h.group(1)!) * 60 + int.parse(h.group(2)!);
      var hasta = int.parse(h.group(3)!) * 60 + int.parse(h.group(4)!);
      if (hasta <= desde) hasta = 24 * 60; // "22:00-02:00": se corta a medianoche
      tramos.add([desde, hasta]);
    }
    for (final d in dias) {
      salida[d] = [...tramos];
    }
    algo = true;
  }
  return algo ? salida : null;
}

/// "Mo-Fr" → [0..4]; "Mo,We,Fr" → [0,2,4]; "" → todos los días.
List<int>? _diasDe(String texto) {
  if (texto.isEmpty) return List.generate(7, (i) => i);
  final dias = <int>[];
  for (final trozo in texto.split(',')) {
    final t = trozo.trim();
    if (t.contains('-')) {
      final partes = t.split('-');
      final a = _diasOsm.indexOf(partes[0].trim());
      final b = _diasOsm.indexOf(partes[1].trim());
      if (a < 0 || b < 0) return null;
      var d = a;
      while (true) {
        dias.add(d);
        if (d == b) break;
        d = (d + 1) % 7;
      }
    } else {
      final a = _diasOsm.indexOf(t);
      if (a < 0) return null;
      dias.add(a);
    }
  }
  return dias;
}

// ---------------------------------------------------------------
// Distancias
// ---------------------------------------------------------------

/// Haversine, en kilómetros. Con esto y no con Pitágoras: en Sevilla el
/// error de Pitágoras es pequeño, pero en cuanto uno mira un mapa de Canarias
/// desde la península deja de serlo.
double distanciaKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// "a 249 m" / "a 3,4 km". Las distancias se miden SIEMPRE desde donde está
/// la persona, mire donde mire en el mapa: "a 249 m" tiene que significar de
/// ti, o no significa nada.
String textoDistancia(double km) {
  if (km < 1) return 'a ${(km * 1000).round()} m';
  if (km < 10) return 'a ${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  return 'a ${km.round()} km';
}

// ---------------------------------------------------------------
// La llamada
// ---------------------------------------------------------------

class ResultadoLugares {
  final List<Lugar> lista;

  /// Distinto de "no hay sitios": la función no pudo preguntar a ningún
  /// espejo. Se pintan distinto, porque uno es un dato y el otro un fallo.
  final String? error;
  const ResultadoLugares(this.lista, [this.error]);
}

Future<ResultadoLugares> buscarLugares(double lat, double lon,
    {int radio = 5000}) async {
  final uri = Uri.parse('$servidorLugares/api/lugares').replace(queryParameters: {
    'lat': lat.toStringAsFixed(4),
    'lon': lon.toStringAsFixed(4),
    'radio': '$radio',
  });
  try {
    final r = await http.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      return ResultadoLugares(const [], 'El servidor ha contestado ${r.statusCode}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final elementos = (j['elements'] ?? []) as List;
    final vistos = <String>{};
    final lista = <Lugar>[];
    for (final e in elementos) {
      final l = lugarDeOsm(Map<String, dynamic>.from(e as Map));
      if (l != null && vistos.add(l.id)) lista.add(l);
    }
    return ResultadoLugares(lista, j['error'] as String?);
  } catch (e) {
    return ResultadoLugares(const [], 'Sin conexión: $e');
  }
}
