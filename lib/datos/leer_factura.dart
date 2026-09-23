/// LEER UNA FACTURA: de un texto suelto a los campos del diario.
///
/// No lee imágenes: recibe el TEXTO de una factura (lo que saca el OCR de la
/// foto) y saca fecha, importe, taller, km, tipo y desglose. Es la misma
/// lógica que `assets/leer-factura.js` en la web, y tiene que seguir siéndolo:
/// una factura leída distinto en el móvil y en el PC es un historial distinto.
///
/// Una factura española tiene sus manías y ninguna librería genérica las
/// conoce:
///   - Los números van al revés que en inglés: 1.234,56 son mil doscientos.
///     Confundirlo convierte 1.234,56 € en 1,23 €.
///   - Las fechas son dd/mm/aaaa. 03/04/2026 es 3 de abril, no 4 de marzo.
///   - En la misma hoja hay BASE IMPONIBLE, IVA y TOTAL. El que vale es el
///     TOTAL, y es el que un buscador ingenuo confunde más veces.
///
/// Todo lo que no se lea con seguridad sale como null. Es mejor que el usuario
/// escriba un campo a que el historial se llene de datos inventados: esto se
/// acaba enseñando para vender el coche.
library;

class LineaLeida {
  final String concepto;
  final double importe;
  final String tipo; // clave de tiposMantenimiento o vacío
  const LineaLeida(this.concepto, this.importe, this.tipo);
}

class FacturaLeida {
  final String? fecha; // AAAA-MM-DD
  final double? importe; // el total, o la suma del desglose si no hay total
  final String? taller;
  final int? km;
  final String? tipo;
  final List<LineaLeida> lineas;

  /// 'sin' si el desglose va sin IVA (suma la base), 'con' si suma el total,
  /// null si no se sabe.
  final String? iva;

  const FacturaLeida({
    this.fecha,
    this.importe,
    this.taller,
    this.km,
    this.tipo,
    this.lineas = const [],
    this.iva,
  });

  bool get hayAlgo =>
      fecha != null || importe != null || taller != null || km != null || tipo != null || lineas.isNotEmpty;
}

class LecturaFactura {
  final FacturaLeida? datos;
  final String? error;
  const LecturaFactura.ok(this.datos) : error = null;
  const LecturaFactura.fallo(this.error) : datos = null;
  bool get ok => datos != null;
}

const _meses = {
  'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5, 'junio': 6,
  'julio': 7, 'agosto': 8, 'septiembre': 9, 'setiembre': 9, 'octubre': 10,
  'noviembre': 11, 'diciembre': 12,
};

const _tildes = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
  'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U',
};

String sinTildes(String t) {
  final b = StringBuffer();
  for (final r in t.runes) {
    final c = String.fromCharCode(r);
    b.write(_tildes[c] ?? c);
  }
  return b.toString();
}

String _plano(String t) => sinTildes(t).toLowerCase();

final _numeroSuelto = RegExp(r'-?[\d.,]*\d');
final _tresLetras = RegExp(r'[a-záéíóúñ]{3}', caseSensitive: false);

/// Un número español a número de verdad. Si hay coma, la coma es el decimal
/// y los puntos son miles. Si no hay coma pero hay UN punto con una o dos
/// cifras detrás, es un decimal escrito a la inglesa (tiques de programas mal
/// configurados). Cualquier otro punto son miles.
double? aNumero(String? texto) {
  var t = (texto ?? '').replaceAll(RegExp(r'[^\d.,-]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceFirst(',', '.');
  } else {
    final puntos = '.'.allMatches(t).length;
    final decimalIngles = puntos == 1 && RegExp(r'\.\d{1,2}$').hasMatch(t);
    if (!decimalIngles) t = t.replaceAll('.', '');
  }
  final n = double.tryParse(t);
  return n != null && n.isFinite ? n : null;
}

double _redondear(double n) => (n * 100).round() / 100;

String? _fechaValida(int a, int m, int d, {DateTime? hoy}) {
  if (a < 1990 || a > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final f = DateTime.utc(a, m, d);
  if (f.day != d || f.month != m) return null; // 31 de febrero, no
  final iso = '$a-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  final limite = (hoy ?? DateTime.now()).toIso8601String().substring(0, 10);
  if (iso.compareTo(limite) > 0) return null; // una factura del futuro es un error de lectura
  return iso;
}

class _FechaEn {
  final String iso;
  final int en;
  _FechaEn(this.iso, this.en);
}

/// Todas las fechas del texto, con su posición, para poder preferir la que
/// esté junto a la palabra "fecha". Un albarán trae varias: emisión,
/// vencimiento, próxima revisión…
List<_FechaEn> _fechas(String texto, {DateTime? hoy}) {
  final encontradas = <_FechaEn>[];
  for (final m in RegExp(r'\b(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{2,4})\b').allMatches(texto)) {
    var a = int.parse(m[3]!);
    if (a < 100) a += a > 70 ? 1900 : 2000; // 26 → 2026, 98 → 1998
    final iso = _fechaValida(a, int.parse(m[2]!), int.parse(m[1]!), hoy: hoy);
    if (iso != null) encontradas.add(_FechaEn(iso, m.start));
  }
  for (final m in RegExp(r'\b(\d{1,2})\s+de\s+([a-zA-ZáéíóúÁÉÍÓÚ]+)\s+de\s+(\d{4})\b').allMatches(texto)) {
    final mes = _meses[_plano(m[2]!)];
    if (mes == null) continue;
    final iso = _fechaValida(int.parse(m[3]!), mes, int.parse(m[1]!), hoy: hoy);
    if (iso != null) encontradas.add(_FechaEn(iso, m.start));
  }
  // ISO ya escrita, que sale en facturas generadas por programas
  for (final m in RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').allMatches(texto)) {
    final iso = _fechaValida(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), hoy: hoy);
    if (iso != null) encontradas.add(_FechaEn(iso, m.start));
  }
  return encontradas;
}

String? fechaDeFactura(String texto, {DateTime? hoy}) {
  final todas = _fechas(texto, hoy: hoy);
  if (todas.isEmpty) return null;
  // Si alguna está pegada a la palabra "fecha" (y no a "vencimiento" ni
  // "próxima"), esa es la de emisión. Se mira lo que hay justo antes.
  final plano = _plano(texto);
  for (final f in todas) {
    final antes = plano.substring(f.en - 40 < 0 ? 0 : f.en - 40, f.en);
    if (RegExp(r'fecha|emision|expedicion').hasMatch(antes) &&
        !RegExp(r'vencimiento|proxima|caducidad|proximo').hasMatch(antes)) {
      return f.iso;
    }
  }
  // Si no, la más reciente que no sea futura: las otras suelen ser vencimientos pasados
  final isos = todas.map((f) => f.iso).toList()..sort();
  return isos.last;
}

Iterable<String> _lineasDe(String texto) => texto.split(RegExp(r'[\r\n]+'));

List<double> _valoresDe(String linea, {double max = 1000000}) => _numeroSuelto
    .allMatches(linea)
    .map((m) => aNumero(m[0]))
    .whereType<double>()
    .where((n) => n > 0 && n < max)
    .toList();

/// El importe total. Se buscan las líneas que hablan de total y se coge el
/// número de esa línea; si hay varias (TOTAL y TOTAL FACTURA), gana la más
/// específica, y a igualdad, la mayor. Sin ninguna, se descarta: mejor null
/// que el precio de un filtro de aire tomado por el total.
double? importeDeFactura(String texto) {
  final candidatos = <({int peso, double valor})>[];
  for (final linea in _lineasDe(texto)) {
    final plano = _plano(linea);
    if (!RegExp(r'total|importe|a\s*pagar|suma').hasMatch(plano)) continue;
    // Estas líneas llevan número pero NO son el total
    if (RegExp(r'base\s*imponible|subtotal|base\b|iva|i\.v\.a|impuesto|descuento|retencion|entrega')
        .hasMatch(plano)) {
      continue;
    }
    final valores = _valoresDe(linea);
    if (valores.isEmpty) continue;
    var peso = 1;
    if (RegExp(r'total\s*(factura|a\s*pagar|general)').hasMatch(plano)) {
      peso = 3;
    } else if (RegExp(r'^\s*total').hasMatch(plano) || RegExp(r'a\s*pagar').hasMatch(plano)) {
      peso = 2;
    }
    // El total es el número de más a la derecha de su línea
    candidatos.add((peso: peso, valor: valores.last));
  }
  if (candidatos.isEmpty) return null;
  candidatos.sort((a, b) => b.peso != a.peso ? b.peso - a.peso : b.valor.compareTo(a.valor));
  return _redondear(candidatos.first.valor);
}

/// Los kilómetros. Se exige que el número esté pegado a una palabra de
/// cuentakilómetros: en una factura hay muchos números y casi ninguno es un
/// kilometraje.
int? kmDeFactura(String texto) {
  final plano = _plano(texto);
  final patrones = [
    RegExp(r'(?:kilometraje|kilometros|cuentakilometros|lectura|odometro)\s*[:.\-]?\s*([\d.,]*\d)'),
    RegExp(r'\b(?:km|kms)\s*[:.\-]?\s*([\d.,]*\d)'),
    RegExp(r'([\d.,]*\d)\s*(?:km|kms)\b'),
  ];
  for (final p in patrones) {
    final m = p.firstMatch(plano);
    if (m == null) continue;
    final n = aNumero(m[1]);
    // Menos de 100 km es una pieza o una distancia, no un cuentakilómetros
    if (n != null && n >= 100 && n < 2000000) return n.round();
  }
  return null;
}

/// Qué se hizo. Por palabras, en orden de concreción: "filtro de aceite" es
/// un cambio de aceite, no un cambio de filtros.
final _pistas = <(String, RegExp)>[
  ('aceite', RegExp(r'aceite|lubricante|5w30|5w-30|10w40|10w-40|filtro\s*de\s*aceite')),
  ('correa', RegExp(r'correa\s*(de\s*)?(distribucion|reparto)|kit\s*(de\s*)?distribucion')),
  ('freno', RegExp(r'freno|pastilla|disco\s*de\s*freno|latiguillo|liquido\s*de\s*frenos')),
  ('rueda', RegExp(r'neumatico|neumaticos|rueda|ruedas|cubierta|equilibrado|michelin|bridgestone|pirelli|continental')),
  ('itv', RegExp(r'\bitv\b|inspeccion\s*tecnica')),
  ('bateria', RegExp(r'bateria|alternador|arranque')),
  ('filtro', RegExp(r'filtro\s*(de\s*)?(aire|habitaculo|polen|combustible)')),
  ('revision', RegExp(r'revision|mantenimiento|puesta\s*a\s*punto')),
];

String? tipoDeFactura(String texto) {
  final plano = _plano(texto);
  for (final p in _pistas) {
    if (p.$2.hasMatch(plano)) return p.$1;
  }
  return null;
}

final _noEsLinea = RegExp(
    r'total|base\s*imponible|subtotal|iva|i\.v\.a|impuesto|descuento|retencion|a\s*pagar|forma\s*de\s*pago|vencimiento|^\s*(concepto|descripcion|cant|cantidad|precio|importe|udes|uds|ref|referencia)\b');
final _noEsConcepto = RegExp(
    r'^(factura|presupuesto|albaran|ticket|tique|recibo|cliente|vehiculo|matricula|fecha|cif|nif|tel|telefono|email|www|http|c/|calle|avda|avenida|plaza|pol\.|poligono|kilometraje|kilometros|km|kms|lectura|odometro|cuentakilometros|bastidor|chasis|marca|modelo)');

/// El desglose. Las líneas suelen ir CONCEPTO … CANTIDAD PRECIO IMPORTE, así
/// que el importe es el último número de la línea y el concepto, lo que hay
/// antes del primero. Con una sola línea no hay desglose que enseñar.
List<LineaLeida> lineasDeFactura(String texto) {
  final encontradas = <LineaLeida>[];
  for (final cruda in _lineasDe(texto)) {
    final l = cruda.trim();
    if (l.length < 6) continue;
    final plano = _plano(l);
    if (_noEsLinea.hasMatch(plano) || _noEsConcepto.hasMatch(plano)) continue;
    final numeros = _numeroSuelto.allMatches(l).toList();
    if (numeros.isEmpty) continue;
    final concepto = l.substring(0, numeros.first.start).replaceAll(RegExp(r'[\s.·:\-|]+$'), '').trim();
    // Sin al menos tres letras seguidas es un código o una fila de números
    if (!_tresLetras.hasMatch(concepto) || concepto.length < 4 || concepto.length > 80) continue;
    final importe = aNumero(numeros.last[0]);
    if (importe == null || importe <= 0 || importe >= 100000) continue;
    encontradas.add(LineaLeida(
      concepto.length > 80 ? concepto.substring(0, 80) : concepto,
      _redondear(importe),
      tipoDeFactura(concepto) ?? '',
    ));
  }
  return encontradas.length >= 2 ? encontradas : const [];
}

/// Conceptos que salen en CUALQUIER factura y no dicen qué se ha hecho.
final _accesorios = RegExp(
    r'mano\s*de\s*obra|diagnosis|diagnostico|desplazamiento|gestion\s*de\s*residuos|residuos|material\s*vario|consumibles|lavado');

/// Con varias cosas distintas en la misma factura, la etiqueta honrada es
/// "Revisión general": poner "batería" porque aparece un motor de arranque
/// escondería el brazo de suspensión. Un solo tipo Y que explique la MAYORÍA
/// estricta de lo sustancial: aceite + filtro de aceite es un cambio de
/// aceite; un arranque y un brazo de suspensión, empate, es una revisión.
String tipoDeVarias(List<LineaLeida> desglose, String textoEntero) {
  final sustanciales = desglose.where((l) => !_accesorios.hasMatch(_plano(l.concepto))).toList();
  if (sustanciales.isEmpty) return tipoDeFactura(textoEntero) ?? 'revision';
  final tipos = sustanciales.map((l) => l.tipo).where((t) => t.isNotEmpty).toList();
  final distintos = tipos.toSet();
  if (distintos.length == 1 && tipos.length * 2 > sustanciales.length) return distintos.first;
  return 'revision';
}

/// La base imponible, para poder decir si el desglose lleva IVA o no.
double? baseDeFactura(String texto) {
  for (final linea in _lineasDe(texto)) {
    final plano = _plano(linea);
    if (!RegExp(r'base\s*imponible|subtotal').hasMatch(plano)) continue;
    final valores = _valoresDe(linea, max: double.infinity);
    if (valores.isNotEmpty) return _redondear(valores.last);
  }
  return null;
}

final _noEsNombre = RegExp(
    r'^(factura|presupuesto|albaran|ticket|tique|recibo|n[ºo°]|num|numero|fecha|cliente|c/|calle|avda|avenida|plaza|pol\.|poligono|cif|nif|tel|telefono|movil|email|correo|www|http)');

/// El nombre del taller. Está arriba del todo, y la primera línea con letras
/// que no sea una dirección, un CIF ni un encabezado suele ser él.
String? tallerDeFactura(String texto) {
  final lineas = _lineasDe(texto).map((l) => l.trim()).where((l) => l.isNotEmpty).take(12);
  for (final l in lineas) {
    final plano = _plano(l);
    if (_noEsNombre.hasMatch(plano)) continue;
    if (!_tresLetras.hasMatch(l)) continue; // tiene que tener palabras
    if (RegExp(r'\d').allMatches(l).length > l.length / 3) continue; // demasiados números: es un código
    if (l.length < 3 || l.length > 60) continue;
    // Se limpia la forma jurídica, que no aporta y afea la lista del diario
    final limpio = l
        .replaceAll(RegExp(r'[,.\s]*(s\.?l\.?u?\.?|s\.?a\.?|c\.?b\.?|s\.?c\.?)\s*$', caseSensitive: false), '')
        .trim();
    return limpio.length > 120 ? limpio.substring(0, 120) : limpio;
  }
  return null;
}

/// ¿Esto es siquiera una factura? Sin al menos dos señales, no se propone
/// nada: es preferible decir "no la hemos entendido" a rellenar el diario con
/// lo que pusiera un folleto.
bool pareceFactura(String texto) {
  final plano = _plano(texto);
  final senales = [
    RegExp(r'factura|tique|ticket|albaran|recibo|presupuesto'),
    RegExp(r'total|importe|a\s*pagar'),
    RegExp(r'iva|i\.v\.a|base\s*imponible'),
    RegExp(r'\bcif\b|\bnif\b'),
    RegExp(r'taller|automocion|neumatic|motor|garaje|itv|revision|aceite'),
    RegExp(r'€|eur\b|euros'),
  ];
  return senales.where((r) => r.hasMatch(plano)).length >= 2;
}

double? sumarLineas(List<LineaLeida> desglose) {
  if (desglose.isEmpty) return null;
  final s = desglose.fold(0.0, (a, l) => a + l.importe);
  return s > 0 ? _redondear(s) : null;
}

LecturaFactura leerFactura(String texto, {DateTime? hoy}) {
  final t = texto;
  if (t.replaceAll(RegExp(r'\s'), '').length < 20) {
    return const LecturaFactura.fallo('No se ha encontrado texto en la foto.');
  }
  if (!pareceFactura(t)) {
    return const LecturaFactura.fallo('Eso no parece una factura de taller. ¿Seguro que es la foto correcta?');
  }
  final desglose = lineasDeFactura(t);
  final total = importeDeFactura(t);
  final suma = sumarLineas(desglose);
  final imponible = baseDeFactura(t);

  // ¿El desglose lleva IVA dentro o no? Se compara su suma con la base
  // imponible y con el total. Decirlo evita que el usuario crea que la
  // lectura ha fallado cuando las cifras no cuadran a simple vista.
  bool cerca(double? a, double? b) =>
      a != null && b != null && (a - b).abs() < (b * 0.02 > 1 ? b * 0.02 : 1);
  String? iva;
  if (suma != null) {
    if (cerca(suma, imponible) || (total != null && suma < total * 0.95)) {
      iva = 'sin';
    } else if (cerca(suma, total)) {
      iva = 'con';
    }
  }

  return LecturaFactura.ok(FacturaLeida(
    fecha: fechaDeFactura(t, hoy: hoy),
    // Sin línea de total, la suma del desglose es la mejor respuesta que hay
    importe: total ?? suma,
    taller: tallerDeFactura(t),
    km: kmDeFactura(t),
    tipo: desglose.isNotEmpty ? tipoDeVarias(desglose, t) : tipoDeFactura(t),
    lineas: desglose,
    iva: iva,
  ));
}
