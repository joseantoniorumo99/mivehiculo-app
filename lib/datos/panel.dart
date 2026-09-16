/// EL PANEL DEL INICIO: cuatro cifras y una gráfica de gasto.
///
/// La forma viene de una referencia que trajo José Manuel: rejilla 2x2 con un
/// chip de variación y barras agrupadas debajo. Lo que NO se copia de ninguna
/// referencia es inventarse el dato para que el hueco quede bonito.
///
/// DOS REGLAS QUE GOBIERNAN TODO LO DE ABAJO:
///
/// 1. El CHIP solo enseña un porcentaje cuando existen dos periodos que
///    comparar de verdad. "+12 %" sobre un mes con una sola factura no es un
///    dato, es un adorno con pinta de dato; y en el historial de un coche eso
///    es justo lo que no puede pasar. Cuando no hay comparación, el chip dice
///    el estado con palabras, o no hay chip.
///
/// 2. Una BARRA A CERO significa "ese mes no gastaste nada", no "no lo
///    sabemos". Con el diario vacío no se dibuja una gráfica plana: se dice
///    que todavía no hay nada que dibujar.
library;

import 'mantenimiento.dart';
import 'modelo.dart';

enum Periodo { seisMeses, anio, todo }

const Map<Periodo, String> nombrePeriodo = {
  Periodo.seisMeses: '6 meses',
  Periodo.anio: 'Este año',
  Periodo.todo: 'Todo',
};

const Map<Periodo, String> periodoEnFrase = {
  Periodo.seisMeses: 'en 6 meses',
  Periodo.anio: 'este año',
  Periodo.todo: 'en total',
};

class Grupo {
  final String etiqueta; // lo que va debajo de la barra
  final String nombre; // lo que se lee al tocarla
  final double actual;
  final double previo;
  final bool hayPrevio;
  const Grupo(this.etiqueta, this.nombre, this.actual, this.previo, this.hayPrevio);
}

class Serie {
  final List<Grupo> grupos;
  final String titulo;

  /// Cómo se llama el periodo con el que se compara, o null si no hay con qué
  /// comparar. Que sea null es la señal de "aquí no se pinta un porcentaje".
  final String? nombrePrevio;

  final double maximo;
  final double totalActual;
  final double totalPrevio;
  final bool vacia;

  const Serie(this.grupos, this.titulo, this.nombrePrevio, this.maximo,
      this.totalActual, this.totalPrevio, this.vacia);
}

String _clave(int anio, int mesCero) =>
    '$anio-${(mesCero + 1).toString().padLeft(2, '0')}';

/// El gasto del diario agrupado por mes: "2026-03" -> 712.
Map<String, double> gastoPorMes(List<Intervencion> diario) {
  final m = <String, double>{};
  for (final d in diario) {
    if (d.fecha.length < 7) continue;
    final k = d.fecha.substring(0, 7);
    m[k] = (m[k] ?? 0) + (d.coste ?? 0);
  }
  return m;
}

/// Siempre SEIS grupos. Seis caben en la pantalla de un móvil sin que las
/// etiquetas se pisen y el ojo los compara de un golpe; lo que cambia con el
/// periodo es qué mide cada grupo, no cuántos hay.
Serie serieGasto(List<Intervencion> diario, Periodo periodo, {DateTime? hoyPara}) {
  final porMes = gastoPorMes(diario);
  final hoy = hoyPara ?? DateTime.now();
  final anio = hoy.year;
  double suma(List<String> meses) =>
      meses.fold(0.0, (s, k) => s + (porMes[k] ?? 0));
  final grupos = <Grupo>[];

  if (periodo == Periodo.seisMeses) {
    for (var i = 5; i >= 0; i--) {
      final f = DateTime(anio, hoy.month - i, 1);
      final k = _clave(f.year, f.month - 1);
      final kPrevio = _clave(f.year - 1, f.month - 1);
      grupos.add(Grupo(
        mesesCortos[f.month - 1],
        '${mesesLargos[f.month - 1]} de ${f.year}',
        porMes[k] ?? 0,
        porMes[kPrevio] ?? 0,
        porMes.containsKey(kPrevio),
      ));
    }
    return _cerrar(grupos, 'Últimos 6 meses', 'el mismo mes del año pasado');
  }

  if (periodo == Periodo.todo) {
    /// Sin nada anotado no hay historia; con algo, se empieza en el primer año
    /// que consta y no en uno inventado seis atrás.
    final anios = porMes.keys
        .map((k) => int.tryParse(k.substring(0, 4)))
        .whereType<int>()
        .toList();
    final desde = anios.isEmpty ? anio : anios.reduce((a, b) => a < b ? a : b);
    final primero = desde > anio - 5 ? desde : anio - 5;
    for (var a = primero; a <= anio; a++) {
      final meses = [for (var m = 0; m < 12; m++) _clave(a, m)];
      grupos.add(Grupo(
          a.toString().substring(2), 'el año $a', suma(meses), 0, false));
    }
    return _cerrar(grupos, 'Por años', null);
  }

  // "anio": seis bimestres, para que el año entero quepa en seis grupos
  for (var b = 0; b < 6; b++) {
    final m1 = b * 2, m2 = b * 2 + 1;
    grupos.add(Grupo(
      mesesCortos[m1],
      '${mesesCortos[m1]}-${mesesCortos[m2]} de $anio',
      suma([_clave(anio, m1), _clave(anio, m2)]),
      suma([_clave(anio - 1, m1), _clave(anio - 1, m2)]),
      porMes.containsKey(_clave(anio - 1, m1)) ||
          porMes.containsKey(_clave(anio - 1, m2)),
    ));
  }
  return _cerrar(grupos, '$anio', '${anio - 1}');
}

Serie _cerrar(List<Grupo> grupos, String titulo, String? nombrePrevio) {
  final hayPrevio = grupos.any((g) => g.hayPrevio);
  var maximo = 1.0;
  for (final g in grupos) {
    if (g.actual > maximo) maximo = g.actual;
    if (hayPrevio && g.previo > maximo) maximo = g.previo;
  }
  return Serie(
    grupos,
    titulo,
    hayPrevio ? nombrePrevio : null,
    maximo,
    grupos.fold(0.0, (s, g) => s + g.actual),
    grupos.fold(0.0, (s, g) => s + g.previo),
    grupos.every((g) => g.actual == 0 && g.previo == 0),
  );
}

/// Un tope redondo para el eje: con 712 € el eje sube a 800 y no a 712, que es
/// lo que hace que las marcas se puedan leer de un vistazo.
double topeRedondo(double n) {
  if (n <= 0) return 1;
  var orden = 1.0;
  while (orden * 10 <= n) {
    orden *= 10;
  }
  final paso = orden / 2;
  return (n / paso).ceil() * paso;
}

enum TonoChip { urgente, atencion, calma, sube }

class Chip {
  final String texto;
  final TonoChip tono;
  const Chip(this.texto, this.tono);
}

enum DestinoMetrica { editarCoche, expediente, avisos, diario }

class Metrica {
  final String etiqueta;
  final String valor;
  final String unidad;
  final Chip? chip;

  /// Lo que se dice cuando el dato es aproximado. Sale debajo de la cifra, no
  /// en una ayuda escondida: si la ITV es aproximada hay que verlo al mirarla.
  final String? nota;

  final DestinoMetrica destino;
  final String describe;

  const Metrica({
    required this.etiqueta,
    required this.valor,
    this.unidad = '',
    this.chip,
    this.nota,
    required this.destino,
    required this.describe,
  });
}

/// Las cuatro cifras del inicio.
List<Metrica> metricasDe(
  Vehiculo? coche,
  List<Intervencion> diario,
  Periodo periodo, {
  DateTime? hoyPara,
}) {
  final hoy = hoyPara ?? DateTime.now();
  final serie = serieGasto(diario, periodo, hoyPara: hoy);
  final avisos = avisosDe(coche, diario, hoyPara: hoy);
  final urgentes = avisos.where((a) => a.urgencia == Urgencia.alta).length;
  final pronto = avisos.where((a) => a.urgencia == Urgencia.media).length;
  final itv = proximaItv(coche?.anioEfectivo, coche?.matriculacion ?? '',
      hoyPara: hoy, ultimaItv: ultimaDelTipo(diario, 'itv')?.fecha);

  /// Los km recorridos salen de la diferencia entre el cuentakilómetros de hoy
  /// y el de la anotación más antigua del periodo. Sin una anotación dentro
  /// del periodo no hay desde dónde restar, y entonces NO HAY CHIP: poner
  /// "+0 km" diría que el coche no se ha movido, que es una afirmación, no un
  /// hueco.
  final desde = periodo == Periodo.todo
      ? '0000'
      : '${hoy.year - (periodo == Periodo.seisMeses ? 1 : 0)}';
  final enPeriodo = diario
      .where((d) => d.fecha.compareTo(desde) >= 0 && (d.km ?? 0) > 0)
      .toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  final km = coche?.km;
  final recorridos =
      (enPeriodo.isNotEmpty && km != null) ? km - enPeriodo.first.km! : null;

  return [
    Metrica(
      etiqueta: 'Kilómetros',
      valor: km == null ? '—' : conMiles(km),
      unidad: km == null ? '' : 'km',
      chip: (recorridos != null && recorridos > 0)
          ? Chip('+${conMiles(recorridos)} km', TonoChip.calma)
          : null,
      destino: DestinoMetrica.editarCoche,
      describe: 'Corregir los kilómetros',
    ),
    Metrica(
      etiqueta: 'Gasto ${periodoEnFrase[periodo]}',
      valor: enEuros(serie.totalActual),
      chip: _chipDeGasto(serie),
      destino: DestinoMetrica.expediente,
      describe: 'Ver el expediente completo',
    ),
    Metrica(
      etiqueta: 'Próxima ITV',
      valor: itv?.corto ?? '—',
      chip: itv == null
          ? null
          : itv.vencida
              ? const Chip('Caducada', TonoChip.urgente)
              : itv.faltan <= 0
                  ? const Chip('Toca ya', TonoChip.urgente)
                  : itv.faltan == 1
                      ? const Chip('El año que viene', TonoChip.atencion)
                      : const Chip('En regla', TonoChip.calma),
      nota: itv == null
          ? null
          : itv.desdeUltima
              ? 'Desde tu última ITV'
              : !itv.exacta
                  ? 'Aproximada por el año'
                  : null,
      destino: DestinoMetrica.avisos,
      describe: 'Ver los avisos',
    ),
    Metrica(
      etiqueta: 'Avisos abiertos',
      valor: '${avisos.length}',
      chip: urgentes > 0
          ? Chip('$urgentes urgente${urgentes > 1 ? 's' : ''}', TonoChip.urgente)
          : pronto > 0
              ? Chip('$pronto pronto', TonoChip.atencion)
              : avisos.isNotEmpty
                  ? const Chip('Sin prisa', TonoChip.calma)
                  : null,
      destino: DestinoMetrica.avisos,
      describe: 'Ver todos los avisos',
    ),
  ];
}

Chip? _chipDeGasto(Serie serie) {
  // Sin periodo anterior no hay porcentaje que calcular, y punto.
  if (serie.nombrePrevio == null || serie.totalPrevio == 0) return null;
  final variacion =
      ((serie.totalActual - serie.totalPrevio) / serie.totalPrevio) * 100;
  if (variacion.abs() < 1) return const Chip('Igual que antes', TonoChip.calma);
  final sube = variacion > 0;
  // Gastar más en el coche no es un logro: sube en rojo, baja en calma.
  return Chip('${sube ? '↑' : '↓'} ${variacion.abs().round()} %',
      sube ? TonoChip.sube : TonoChip.calma);
}
