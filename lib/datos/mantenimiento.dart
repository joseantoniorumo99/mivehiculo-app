/// LO QUE LE TOCA AL COCHE. Todo lo de aquí se CALCULA; no hay una lista de
/// avisos escrita a mano en ningún sitio.
///
/// LA REGLA QUE MANDA EN TODO EL FICHERO: de un mantenimiento solo se avisa si
/// consta en el diario cuándo se hizo. Sin eso no hay desde dónde contar, y
/// adivinar sería mentir con pinta de dato. Un aviso inventado enseña a la
/// gente a ignorar los avisos, y entonces el día que uno es de verdad tampoco
/// lo mira.
///
/// La ITV es la excepción y no lo es: no se cuenta desde el diario sino desde
/// la fecha de matriculación, que es lo que dice la ley (RD 920/2017), y esa
/// fecha sí la sabemos.
library;

import 'modelo.dart';

const List<String> mesesCortos = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

const List<String> mesesLargos = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

enum Urgencia { alta, media, baja }

class Aviso {
  final String tipo;
  final String detalle;
  final Urgencia urgencia;

  /// La clave de `tiposMantenimiento` que atiende este aviso, para que al
  /// anotarlo venga ya elegido el tipo y para buscar talleres que lo hagan.
  final String clave;

  const Aviso(this.tipo, this.detalle, this.urgencia, this.clave);
}

class Intervalo {
  final String clave;
  final String texto;
  final int km;
  final int? meses;
  const Intervalo(this.clave, this.texto, this.km, [this.meses]);
}

/// Intervalos GENÉRICOS. Cada fabricante tiene los suyos y el libro del coche
/// manda; estos son los de andar por casa para que la app sirva desde el
/// primer día sin pedirle a nadie que teclee la tabla de su modelo.
const List<Intervalo> intervalos = [
  Intervalo('aceite', 'Cambio de aceite y filtro', 15000, 12),
  Intervalo('rueda', 'Revisar neumáticos', 40000),
  Intervalo('freno', 'Revisar frenos', 50000),
  Intervalo('correa', 'Correa de distribución', 120000),
];

class ProximaItv {
  final int anio;
  final int? mes; // 1-12, null cuando solo se sabe el año
  final int faltan; // años hasta que toque; <= 0 es "ya"
  final bool exacta;
  const ProximaItv(this.anio, this.mes, this.faltan, this.exacta);

  String get cuando =>
      exacta && mes != null ? '${mesesCortos[mes! - 1]} de $anio' : 'hacia $anio';

  String get corto =>
      exacta && mes != null ? '${mesesCortos[mes! - 1]} $anio' : '$anio';
}

/// Cuándo toca la ITV de un turismo particular en España.
///
/// La norma: primera a los 4 años, luego cada 2 hasta los 10, y a partir de
/// los 10 todos los años. Con la fecha de matriculación se dice el MES; sin
/// ella solo el año, y la app tiene que decir que es aproximado en vez de
/// fingir precisión que no tiene.
ProximaItv? proximaItv(int? anio, String matriculacion, {DateTime? hoyPara}) {
  final hoy = hoyPara ?? DateTime.now();
  final ahora = hoy.year;

  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(matriculacion);
  if (m != null) {
    final a0 = int.parse(m.group(1)!);
    final mes0 = int.parse(m.group(2)!);
    var toca = DateTime.utc(a0 + 4, mes0, 1);
    final limite = DateTime.utc(a0 + 10, mes0, 1);
    final hoyUtc = DateTime.utc(hoy.year, hoy.month, hoy.day);
    var vueltas = 0;
    while (toca.isBefore(hoyUtc) && vueltas++ < 100) {
      toca = DateTime.utc(
          toca.year + (toca.isBefore(limite) ? 2 : 1), toca.month, 1);
    }
    return ProximaItv(toca.year, toca.month, toca.year - ahora, true);
  }

  if (anio == null || anio <= 1900) return null;
  var toca = anio + 4;
  var vueltas = 0;
  while (toca < ahora && vueltas++ < 100) {
    toca += (toca < anio + 10) ? 2 : 1;
  }
  return ProximaItv(toca, null, toca - ahora, false);
}

/// La última vez que se hizo algo de ese tipo.
///
/// Mira también el DESGLOSE, y es lo que lo hace útil: una factura con cinco
/// conceptos se etiqueta "Revisión general", pero si dentro llevaba el cambio
/// de aceite, el aviso del aceite tiene que darse por atendido. Sin esto la
/// app seguiría pidiendo un cambio que ya está hecho y pagado, que es la forma
/// más rápida de que alguien la desinstale.
Intervencion? ultimaDelTipo(List<Intervencion> diario, String clave) {
  final buscado = clave.toLowerCase();
  final lista = diario.where((d) => d.tiposTocados.contains(buscado)).toList();
  if (lista.isEmpty) return null;
  lista.sort((a, b) => b.fecha.compareTo(a.fecha));
  return lista.first;
}

/// Los avisos de un coche, ya ordenados por urgencia.
List<Aviso> avisosDe(Vehiculo? coche, List<Intervencion> diario,
    {DateTime? hoyPara}) {
  if (coche == null) return const [];
  final lista = <Aviso>[];
  final km = coche.km;

  final itv = proximaItv(coche.anioEfectivo, coche.matriculacion, hoyPara: hoyPara);
  if (itv != null) {
    final String detalle;
    if (itv.exacta) {
      detalle = 'Toca en ${itv.cuando}';
    } else if (itv.faltan <= 0) {
      detalle = 'Toca este año · fecha aproximada por el año de matriculación';
    } else {
      detalle =
          'Hacia ${itv.anio} · fecha aproximada por el año de matriculación';
    }
    lista.add(Aviso(
      'ITV',
      detalle,
      itv.faltan <= 0
          ? Urgencia.alta
          : itv.faltan == 1
              ? Urgencia.media
              : Urgencia.baja,
      'itv',
    ));
  }

  for (final i in intervalos) {
    final ultima = ultimaDelTipo(diario, i.clave);
    if (ultima == null || km == null) continue;

    /// Sin los km de aquella intervención no se puede restar. Antes que
    /// inventar un punto de partida, no se avisa: el diario dice cuándo, no
    /// cuánto, y esa diferencia es justo la que importa aquí.
    final desde = ultima.km;
    if (desde == null) continue;

    final recorridos = km - desde;
    final restantes = i.km - recorridos;
    if (restantes > i.km * 0.35) continue; // todavía lejos: no molesta
    lista.add(Aviso(
      i.texto,
      restantes <= 0
          ? 'Vencido por ${conMiles(restantes.abs())} km'
          : 'Te quedan ${conMiles(restantes)} km',
      restantes <= 0
          ? Urgencia.alta
          : restantes < i.km * 0.15
              ? Urgencia.media
              : Urgencia.baja,
      i.clave,
    ));
  }

  /// Rellenar el AdBlue es mantenimiento como cualquier otro, y a quien no
  /// sabe que su coche lo lleva le pilla en carretera con el coche sin
  /// arrancar y una grúa de por medio.
  if (estadoAdBlue(coche).lleva == 'si') {
    lista.add(const Aviso(
      'Rellenar AdBlue',
      'Cada 8.000-15.000 km · unos 10-20 € en una gasolinera',
      Urgencia.baja,
      'otro',
    ));
  }

  lista.sort((a, b) => a.urgencia.index.compareTo(b.urgencia.index));
  return lista;
}

class Adblue {
  final String lleva; // "si" | "no" | "quizas"
  final String texto;
  final String detalle;
  const Adblue(this.lleva, this.texto, this.detalle);
}

/// Si el coche lleva AdBlue, deducido de la normativa. Se deduce porque casi
/// nadie sabe contestarlo de memoria, y se deja corregir porque la deducción
/// falla en los años de frontera.
Adblue estadoAdBlue(Vehiculo? coche) {
  if (coche == null) return const Adblue('no', 'No lleva AdBlue', '');
  if (coche.adBlue == 'si' || coche.adBlue == 'no' || coche.adBlue == 'quizas') {
    final r = adBlueDeLaNorma(coche.combustible, coche.anioEfectivo);
    return Adblue(coche.adBlue, r.texto,
        coche.adBlue == r.lleva ? r.detalle : 'Lo has confirmado tú.');
  }
  return adBlueDeLaNorma(coche.combustible, coche.anioEfectivo);
}

Adblue adBlueDeLaNorma(String combustible, int? anio) {
  final esDiesel = RegExp('di[ée]sel', caseSensitive: false).hasMatch(combustible);
  final a = anio ?? 0;
  if (!esDiesel) {
    return const Adblue(
        'no', 'No lleva AdBlue', 'Solo lo usan los diésel modernos.');
  }
  if (a >= 2019) {
    return const Adblue('si', 'Lleva AdBlue',
        'Desde 2019 todos los diésel nuevos llevan SCR. Hay que rellenarlo cada 8.000-15.000 km.');
  }
  if (a >= 2015) {
    return const Adblue('quizas', 'Puede que lleve AdBlue',
        'Los diésel Euro 6 de esos años lo llevan o no según el motor. Mira si tienes un tapón azul junto al del gasóleo.');
  }
  return const Adblue(
      'no', 'No lleva AdBlue', 'Los diésel anteriores a 2015 no montaban SCR.');
}

/// Los años del coche que no tienen NI UNA anotación.
///
/// Es la pieza que hace que el expediente funcione: un coche de 2019 cuyo
/// diario empieza en 2026 tiene siete años sin documentar, y verlo escrito
/// motiva a subir las facturas viejas más que cualquier aviso, porque está
/// mirando un documento que quiere completo.
List<int> aniosSinDocumentar(Vehiculo? coche, List<Intervencion> diario,
    {DateTime? hoyPara}) {
  final desde = coche?.anioEfectivo;
  if (desde == null || desde <= 1900) return const [];
  final hasta = (hoyPara ?? DateTime.now()).year;
  final conAlgo = diario
      .map((d) => d.fecha.length >= 4 ? int.tryParse(d.fecha.substring(0, 4)) : null)
      .whereType<int>()
      .toSet();
  final huecos = <int>[];
  for (var a = desde; a <= hasta; a++) {
    if (!conAlgo.contains(a)) huecos.add(a);
  }
  return huecos;
}

/// 120000 -> "120.000". El separador de miles en España es el punto, y verlo
/// bien puesto es lo que distingue un kilometraje de un número de teléfono.
String conMiles(num n) {
  final negativo = n < 0;
  final s = n.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return negativo ? '-$b' : b.toString();
}

/// Euros a la española: 1.234,56 €. Sin decimales cuando son cero, porque
/// "700 €" se lee más rápido que "700,00 €" y en una rejilla de cifras eso se
/// nota.
String enEuros(num? n) {
  if (n == null) return '—';
  final entero = conMiles(n.abs().truncate());
  final centimos = ((n.abs() - n.abs().truncate()) * 100).round();
  final signo = n < 0 ? '-' : '';
  if (centimos == 0) return '$signo$entero €';
  return '$signo$entero,${centimos.toString().padLeft(2, '0')} €';
}

/// "2026-03-14" -> "14 mar 2026". Fecha corta y sin ambigüedad: 03/04 es el 3
/// de abril para un español y el 4 de marzo para medio internet.
String fechaCorta(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?').firstMatch(iso);
  if (m == null) return iso;
  final anio = m.group(1)!;
  final mes = mesesCortos[int.parse(m.group(2)!) - 1];
  final dia = m.group(3);
  return dia == null ? '$mes $anio' : '${int.parse(dia)} $mes $anio';
}

String hoyIso([DateTime? cuando]) {
  final d = cuando ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
