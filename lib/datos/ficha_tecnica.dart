/// LA FICHA TÉCNICA, leída de una foto.
///
/// La tarjeta ITV (ficha técnica) lleva los datos del coche con CÓDIGOS
/// europeos fijos, y eso es lo que la hace legible por una máquina aunque la
/// foto sea regular: no hace falta entender el documento, solo encontrar el
/// código y leer lo que viene detrás.
///
///   B    Fecha de primera matriculación
///   D.1  Marca
///   D.2  Tipo / variante / versión (el código del fabricante)
///   D.3  Denominación comercial (el modelo)
///   E    Número de bastidor (17 caracteres, sin I, O ni Q)
///   P.1  Cilindrada en cm³
///   P.2  Potencia neta máxima en kW
///   P.3  Tipo de combustible
///
/// Y la matrícula, que va arriba del todo. El texto lo saca el reconocedor
/// de ML Kit en el propio móvil (no sale de él); aquí solo se interpreta.
///
/// PROPONE, NO DECIDE: quien llame rellena los huecos vacíos del formulario
/// y deja lo que el dueño ya escribió. Un bastidor con una letra mal leída
/// metido a la fuerza es peor que ninguno: el bastidor se valida con las
/// reglas del VIN antes de darlo por bueno.
library;

class DatosFichaTecnica {
  String? matricula;
  String? marca;
  String? modelo;
  String? bastidor;
  String? combustible;

  /// "AAAA-MM-DD" de la primera matriculación (código B).
  String? matriculacion;
  int? cilindrada;
  int? potenciaKw;

  /// Qué se ha leído, en palabras, para decírselo al dueño.
  List<String> get leido => [
        if (matricula != null) 'matrícula',
        if (marca != null) 'marca',
        if (modelo != null) 'modelo',
        if (matriculacion != null) 'fecha de matriculación',
        if (combustible != null) 'combustible',
        if (cilindrada != null) 'cilindrada',
        if (potenciaKw != null) 'potencia',
        if (bastidor != null) 'bastidor',
      ];

  bool get hayAlgo => leido.isNotEmpty;
  int? get anio => matriculacion == null ? null : int.tryParse(matriculacion!.substring(0, 4));
  int? get potenciaCv => potenciaKw == null ? null : (potenciaKw! * 1.35962).round();
}

/// Interpreta el texto de una ficha técnica. `marcasConocidas` (las del
/// catálogo) ayuda cuando el código D.1 no se lee pero la marca sí aparece.
DatosFichaTecnica leerFichaTecnica(String texto, {List<String> marcasConocidas = const []}) {
  final d = DatosFichaTecnica();
  final limpio = texto.replaceAll('\r', '');
  final lineas = limpio.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final mayus = limpio.toUpperCase();

  // ---- Matrícula: 1234 ABC (sin vocales ni Ñ ni Q en las letras) ----
  final m = RegExp(r'\b(\d{4})[\s\-]?([BCDFGHJKLMNPRSTVWXYZ]{3})\b').firstMatch(mayus);
  if (m != null) d.matricula = '${m.group(1)} ${m.group(2)}';

  // ---- Bastidor: 17 caracteres válidos de VIN, con letras y números ----
  for (final cand in RegExp(r'[A-Z0-9]{17}').allMatches(mayus.replaceAll(RegExp(r'[\s\-]'), ' '))) {
    final v = _corregirVin(cand.group(0)!);
    if (v != null) {
      d.bastidor = v;
      break;
    }
  }

  // ---- Los códigos: lo que viene detrás de cada uno ----
  String? trasCodigo(String codigo) {
    // "D.1 CITROEN", "D1: CITROEN", "(D.1) CITROEN" y también en la línea siguiente
    final re = RegExp(r'(?:^|[\s(\[])' + codigo.replaceAll('.', r'\.?') + r'[\)\]]?\s*[:\-]?\s*(.*)$', multiLine: true);
    for (var i = 0; i < lineas.length; i++) {
      final mm = re.firstMatch(lineas[i].toUpperCase());
      if (mm == null) continue;
      final resto = mm.group(1)!.trim();
      if (resto.isNotEmpty && !_esOtroCodigo(resto)) return _sinOtroCodigo(resto);
      if (i + 1 < lineas.length && !_empiezaPorCodigo(lineas[i + 1])) return lineas[i + 1].trim();
    }
    return null;
  }

  final marcaLeida = trasCodigo('D.1');
  if (marcaLeida != null && marcaLeida.length >= 2 && marcaLeida.length <= 30) {
    d.marca = _bonito(marcaLeida);
  }
  if (d.marca == null && marcasConocidas.isNotEmpty) {
    // Sin código legible, la marca que aparezca en el texto
    for (final marca in marcasConocidas) {
      final re = RegExp(r'\b' + RegExp.escape(_sinTildes(marca).toUpperCase()) + r'\b');
      if (re.hasMatch(_sinTildes(mayus))) {
        d.marca = marca;
        break;
      }
    }
  } else if (d.marca != null && marcasConocidas.isNotEmpty) {
    // Con el nombre del catálogo, escrito como en el catálogo
    for (final marca in marcasConocidas) {
      if (_sinTildes(marca).toUpperCase() == _sinTildes(d.marca!).toUpperCase()) d.marca = marca;
    }
  }

  final modeloLeido = trasCodigo('D.3');
  if (modeloLeido != null && modeloLeido.isNotEmpty && modeloLeido.length <= 40) {
    var mod = modeloLeido;
    // "CITROEN C3" → "C3"
    if (d.marca != null) {
      final pref = RegExp('^${RegExp.escape(_sinTildes(d.marca!).toUpperCase())}\\s+');
      mod = _sinTildes(mod).toUpperCase().replaceFirst(pref, '');
    }
    d.modelo = _bonito(mod);
  }

  // ---- Cilindrada (P.1) y potencia (P.2) ----
  final cil = trasCodigo('P.1');
  final nCil = _numero(cil);
  if (nCil != null && nCil >= 50 && nCil <= 9000) d.cilindrada = nCil;
  if (d.cilindrada == null) {
    final mc = RegExp(r'(\d{3,4})\s*(?:CM3|CM³|CC)\b').firstMatch(mayus);
    if (mc != null) d.cilindrada = int.parse(mc.group(1)!);
  }
  final pot = trasCodigo('P.2');
  final nPot = _numero(pot);
  if (nPot != null && nPot >= 10 && nPot <= 800) d.potenciaKw = nPot;

  // ---- Combustible (P.3 o por palabra) ----
  final comb = (trasCodigo('P.3') ?? '').toUpperCase();
  d.combustible = _combustibleDe(comb.isNotEmpty ? comb : mayus);

  // ---- Fecha de primera matriculación (B) ----
  final fechaB = trasCodigo('B');
  d.matriculacion = _fechaIso(fechaB);
  if (d.matriculacion == null) {
    // La fecha más antigua que parezca de matriculación (las de ITV son posteriores)
    String? mejor;
    for (final f in RegExp(r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})\b').allMatches(mayus)) {
      final iso = _fechaIso(f.group(0));
      if (iso == null) continue;
      if (mejor == null || iso.compareTo(mejor) < 0) mejor = iso;
    }
    d.matriculacion = mejor;
  }

  return d;
}

// ---------------------------------------------------------------- ayudas

const _codigos = ['A', 'B', 'D.1', 'D.2', 'D.3', 'E', 'F.1', 'F.2', 'G', 'I', 'J', 'K', 'L', 'P.1', 'P.2', 'P.3', 'P.5', 'Q', 'S.1', 'S.2', 'U.1', 'U.2', 'V.7', 'V.9'];

bool _empiezaPorCodigo(String linea) {
  final l = linea.toUpperCase().trim();
  return _codigos.any((c) => RegExp('^[(\\[]?${c.replaceAll('.', r'\.?')}[\\)\\]]?(\\s|:|\$)').hasMatch(l));
}

bool _esOtroCodigo(String resto) => _empiezaPorCodigo(resto) && resto.trim().length <= 4;

/// "CITROEN D.3 C3" → "CITROEN": corta donde empieza el siguiente código.
String _sinOtroCodigo(String resto) {
  final mm = RegExp(r'\s[(\[]?(?:[A-Z]\.?\d|[A-Z])[\)\]]?\s*[:\-]?\s').firstMatch(' $resto ');
  if (mm != null && mm.start > 0) {
    final corte = resto.substring(0, mm.start).trim();
    if (corte.isNotEmpty) return corte;
  }
  return resto.trim();
}

int? _numero(String? t) {
  if (t == null) return null;
  final mm = RegExp(r'\d{2,5}').firstMatch(t.replaceAll('.', '').replaceAll(',', ''));
  return mm == null ? null : int.tryParse(mm.group(0)!);
}

String? _fechaIso(String? t) {
  if (t == null) return null;
  final mm = RegExp(r'(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})').firstMatch(t);
  if (mm == null) return null;
  final dia = int.parse(mm.group(1)!), mes = int.parse(mm.group(2)!), anio = int.parse(mm.group(3)!);
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  if (anio < 1970 || anio > DateTime.now().year) return null;
  return '$anio-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
}

String? _combustibleDe(String t) {
  if (RegExp(r'H[IÍ]BRIDO.*DI[EÉ]SEL|DI[EÉ]SEL.*H[IÍ]BRIDO').hasMatch(t)) return 'Híbrido diésel';
  if (RegExp(r'H[IÍ]BRIDO|HYBRID|ENCHUFABLE|PHEV').hasMatch(t)) return 'Híbrido';
  if (RegExp(r'EL[EÉ]CTRICO|ELECTRIC|BEV').hasMatch(t)) return 'Eléctrico';
  if (RegExp(r'GAS[OÓ]LEO|DI[EÉ]SEL|GASOIL').hasMatch(t)) return 'Diésel';
  if (RegExp(r'\bGLP\b|\bLPG\b').hasMatch(t)) return 'GLP';
  if (RegExp(r'\bGNC\b|\bCNG\b|GAS NATURAL').hasMatch(t)) return 'Gas natural';
  if (RegExp(r'GASOLINA|PETROL').hasMatch(t)) return 'Gasolina';
  return null;
}

/// Un VIN no lleva I, O ni Q. Si el reconocedor las puso, casi seguro eran
/// 1, 0 y 0; si tras corregir sigue sin cuadrar, no es un bastidor.
String? _corregirVin(String v) {
  final c = v.replaceAll('I', '1').replaceAll('O', '0').replaceAll('Q', '0');
  if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(c)) return null;
  final letras = RegExp(r'[A-Z]').allMatches(c).length;
  final numeros = RegExp(r'\d').allMatches(c).length;
  if (letras < 3 || numeros < 4) return null; // 17 letras seguidas no es un VIN
  // El WMI (tres primeros) siempre empieza por letra o número; los últimos
  // seis son el número de serie y son dígitos en casi todos los fabricantes.
  if (!RegExp(r'\d{4}$').hasMatch(c)) return null;
  return c;
}

String _sinTildes(String t) => t
    .replaceAll(RegExp('[áàä]'), 'a')
    .replaceAll(RegExp('[éèë]'), 'e')
    .replaceAll(RegExp('[íìï]'), 'i')
    .replaceAll(RegExp('[óòö]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll(RegExp('[ÁÀÄ]'), 'A')
    .replaceAll(RegExp('[ÉÈË]'), 'E')
    .replaceAll(RegExp('[ÍÌÏ]'), 'I')
    .replaceAll(RegExp('[ÓÒÖ]'), 'O')
    .replaceAll(RegExp('[ÚÙÜ]'), 'U');

String _bonito(String t) => t
    .trim()
    .split(RegExp(r'\s+'))
    .map((p) => p.length <= 2 || RegExp(r'^\d').hasMatch(p) ? p : p[0].toUpperCase() + p.substring(1).toLowerCase())
    .join(' ');
