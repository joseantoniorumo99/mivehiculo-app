/// MEJORAS ACONSEJADAS: qué piezas o trabajos le vendrían bien a ESTE coche.
///
/// No son los avisos (lo que TOCA por kilómetros o por fecha): son las cosas
/// que mejoran el rendimiento, el consumo o la vida del coche y que casi
/// nadie sabe que existen hasta que un mecánico se lo cuenta. Se deducen de
/// lo que la app sabe del coche —combustible, edad, kilómetros, AdBlue— y de
/// lo que consta en el diario.
///
/// LAS REGLAS QUE MANDAN:
///  · Ningún consejo sin motivo escrito. Cada uno dice POR QUÉ aplica a este
///    coche; sin motivo sería publicidad.
///  · Ningún precio inventado: el precio lo pone cada taller en su ficha, y
///    el consejo lleva al mapa filtrado por el servicio para verlo.
///  · Orientativo, y se dice: el libro de mantenimiento del fabricante manda.
///  · Lo que ya consta hecho hace poco no se aconseja: un consejo de cambiar
///    las bujías el mes después de cambiarlas hace que se ignoren todos.
library;

import 'mantenimiento.dart';
import 'modelo.dart';

enum Beneficio { rendimiento, consumo, duracion, seguridad }

const Map<Beneficio, String> nombreBeneficio = {
  Beneficio.rendimiento: 'Rendimiento',
  Beneficio.consumo: 'Consumo',
  Beneficio.duracion: 'Vida del coche',
  Beneficio.seguridad: 'Seguridad',
};

class Consejo {
  final String titulo;

  /// Por qué aplica a este coche, en una frase.
  final String motivo;

  /// Qué gana el dueño, en una frase.
  final String gana;
  final Beneficio beneficio;

  /// El servicio con el que se busca en el mapa ("Mecánica general",
  /// "Neumáticos"…) — mismo vocabulario que `servicioParaTipo`.
  final String servicio;

  /// La clave del tipo de mantenimiento si al hacerlo se anota como tal.
  final String clave;

  /// 0 = lo más relevante. Sirve para ordenar y para quedarse con pocos.
  final int prioridad;

  const Consejo({
    required this.titulo,
    required this.motivo,
    required this.gana,
    required this.beneficio,
    this.servicio = 'Mecánica general',
    this.clave = 'otro',
    this.prioridad = 5,
  });
}

/// Los consejos para un coche. Devuelve los que aplican, ordenados por
/// prioridad. Con `hoyPara` se prueba sin depender del reloj.
List<Consejo> consejosPara(Vehiculo? coche, List<Intervencion> diario, {DateTime? hoyPara}) {
  if (coche == null) return const [];
  final hoy = hoyPara ?? DateTime.now();
  final anio = coche.anioEfectivo;
  final edad = anio == null ? null : hoy.year - anio;
  final km = coche.km;
  final comb = coche.combustible.toLowerCase();
  final diesel = comb.contains('diésel') || comb.contains('diesel');
  final gasolina = comb == 'gasolina' || comb == 'glp' || comb == 'gas natural';
  final hibrido = comb.contains('híbrido') || comb.contains('hibrido');
  final electrico = comb == 'eléctrico' || comb == 'electrico';
  final combustion = diesel || gasolina || hibrido;
  final adBlue = coche.adBlue == 'si' || (coche.adBlue == 'auto' && diesel && anio != null && anio >= 2019);

  /// Cuánto hace (en meses) que consta algo en el diario cuyo título o líneas
  /// hablan de eso. Null si nunca.
  int? mesesDesde(RegExp que) {
    String? ultima;
    for (final d in diario) {
      final texto = '${d.titulo} ${d.nota} ${d.lineas.map((l) => l.concepto).join(' ')}'.toLowerCase();
      if (que.hasMatch(texto) && (ultima == null || d.fecha.compareTo(ultima) > 0)) ultima = d.fecha;
    }
    if (ultima == null) return null;
    final f = DateTime.tryParse(ultima);
    if (f == null) return null;
    return (hoy.year - f.year) * 12 + (hoy.month - f.month);
  }

  bool recienHecho(RegExp que, int meses) {
    final m = mesesDesde(que);
    return m != null && m < meses;
  }

  final salida = <Consejo>[];

  // ---- Diésel ----
  if (diesel) {
    if ((km ?? 0) >= 60000 && !recienHecho(RegExp(r'fap|dpf|filtro de part|part[ií]culas'), 24)) {
      salida.add(const Consejo(
        titulo: 'Limpieza del filtro de partículas (FAP)',
        motivo: 'Un diésel con más de 60.000 km que hace trayectos cortos no llega a regenerar el filtro y se va obstruyendo.',
        gana: 'Recupera potencia, evita el testigo y una avería de más de 1.000 €.',
        beneficio: Beneficio.rendimiento,
        prioridad: 1,
      ));
    }
    if ((km ?? 0) >= 80000 && !recienHecho(RegExp(r'inyector'), 24)) {
      salida.add(const Consejo(
        titulo: 'Limpieza de inyectores',
        motivo: 'A partir de 80.000 km los inyectores diésel pierden pulverización y el motor tira peor y gasta más.',
        gana: 'Arranque en frío más limpio y algo menos de consumo.',
        beneficio: Beneficio.consumo,
        prioridad: 3,
      ));
    }
    if (adBlue) {
      salida.add(const Consejo(
        titulo: 'AdBlue de calidad, norma ISO 22241',
        motivo: 'Tu coche lleva AdBlue: uno barato o mal guardado cristaliza en el inyector y bloquea el arranque.',
        gana: 'Sin averías del sistema SCR, que son de las caras.',
        beneficio: Beneficio.duracion,
        prioridad: 4,
      ));
    }
  }

  // ---- Gasolina ----
  if (gasolina) {
    final mBujias = mesesDesde(RegExp(r'buj[ií]a'));
    if ((km ?? 0) >= 50000 && (mBujias == null || mBujias > 36)) {
      salida.add(const Consejo(
        titulo: 'Bujías nuevas',
        motivo: 'En un gasolina las bujías se gastan cada 50.000-60.000 km y no consta que se hayan cambiado.',
        gana: 'Arranque a la primera, ralentí estable y menos consumo.',
        beneficio: Beneficio.rendimiento,
        prioridad: 2,
      ));
    }
    if ((km ?? 0) >= 60000 && !recienHecho(RegExp(r'mariposa|admisi[oó]n|inyecci[oó]n|inyector'), 24)) {
      salida.add(const Consejo(
        titulo: 'Limpieza de la admisión e inyección',
        motivo: 'La carbonilla en la mariposa y las válvulas de admisión hace que el motor pierda respuesta con los años.',
        gana: 'Respuesta al acelerador y consumo como cuando era nuevo.',
        beneficio: Beneficio.rendimiento,
        prioridad: 4,
      ));
    }
  }

  // ---- Híbrido ----
  if (hibrido) {
    if (edad != null && edad >= 6 && !recienHecho(RegExp(r'bater[ií]a h[ií]brida|bater[ií]a de alta'), 24)) {
      salida.add(const Consejo(
        titulo: 'Revisión de la batería híbrida',
        motivo: 'Con más de seis años conviene medir el estado de las celdas: una celda floja se nota en consumo antes que en avisos.',
        gana: 'Saber cuánta vida le queda antes de vender o de que falle.',
        beneficio: Beneficio.duracion,
        prioridad: 2,
      ));
    }
    salida.add(const Consejo(
      titulo: 'Revisar frenos aunque no se gasten',
      motivo: 'Un híbrido frena con el motor eléctrico y las pastillas duran mucho, pero los discos se oxidan por falta de uso.',
      gana: 'Frenada uniforme y sin ruidos; se evita cambiar discos por óxido.',
      beneficio: Beneficio.seguridad,
      servicio: 'Frenos',
      clave: 'freno',
      prioridad: 5,
    ));
  }

  // ---- Eléctrico ----
  if (electrico) {
    salida.add(const Consejo(
      titulo: 'Informe de salud de la batería (SoH)',
      motivo: 'Es el dato que decide el valor de un eléctrico: un taller con el equipo lo mide en media hora.',
      gana: 'Un número objetivo para vender o para reclamar la garantía.',
      beneficio: Beneficio.duracion,
      prioridad: 1,
    ));
    salida.add(const Consejo(
      titulo: 'Neumáticos específicos para eléctrico',
      motivo: 'Pesa más y entrega el par de golpe: unos neumáticos normales se gastan antes y suenan más.',
      gana: 'Más kilómetros por juego y más autonomía por su menor resistencia.',
      beneficio: Beneficio.consumo,
      servicio: 'Neumáticos',
      clave: 'rueda',
      prioridad: 3,
    ));
  }

  // ---- Todos los de combustión ----
  if (combustion) {
    if (!recienHecho(RegExp(r'filtro de aire|filtro aire'), 18) && (km ?? 0) >= 20000) {
      salida.add(const Consejo(
        titulo: 'Filtro de aire del motor',
        motivo: 'Es barato y se olvida: un filtro sucio ahoga el motor y sube el consumo sin que se note de golpe.',
        gana: 'Algo más de potencia y de un 2 a un 5 % menos de consumo.',
        beneficio: Beneficio.consumo,
        clave: 'filtro',
        prioridad: 4,
      ));
    }
    if (anio != null && anio >= 2012 && !recienHecho(RegExp(r'bater[ií]a'), 36)) {
      salida.add(const Consejo(
        titulo: 'Batería AGM o EFB si lleva start-stop',
        motivo: 'Los coches con parada automática en semáforos castigan la batería; una convencional dura la mitad.',
        gana: 'Evitar la batería muerta en invierno y que el start-stop deje de funcionar.',
        beneficio: Beneficio.duracion,
        servicio: 'Batería',
        clave: 'bateria',
        prioridad: 5,
      ));
    }
    salida.add(const Consejo(
      titulo: 'Aceite con la norma exacta del fabricante',
      motivo: 'Cada motor pide una norma (ACEA, VW 507, PSA B71…); un aceite "que vale" acorta la vida de la distribución y el turbo.',
      gana: 'Menos desgaste y consumo; la garantía se mantiene.',
      beneficio: Beneficio.duracion,
      clave: 'aceite',
      prioridad: 6,
    ));
  }

  // ---- Todos ----
  if (edad != null && edad >= 2 && !recienHecho(RegExp(r'l[ií]quido de frenos'), 24)) {
    salida.add(const Consejo(
      titulo: 'Cambio del líquido de frenos',
      motivo: 'Absorbe humedad con los años y pierde eficacia: se cambia cada dos años y casi nadie lo hace.',
      gana: 'Frenada firme y sin sorpresas en una bajada larga.',
      beneficio: Beneficio.seguridad,
      servicio: 'Frenos',
      clave: 'freno',
      prioridad: 3,
    ));
  }
  if (!recienHecho(RegExp(r'alinea|paralelo'), 24)) {
    salida.add(const Consejo(
      titulo: 'Alineado y presiones',
      motivo: 'Un bache basta para desalinear: el coche tira a un lado y se come el neumático por dentro sin que se vea.',
      gana: 'Neumáticos que duran lo que deben y menos consumo.',
      beneficio: Beneficio.consumo,
      servicio: 'Neumáticos',
      clave: 'rueda',
      prioridad: 5,
    ));
  }
  if (edad != null && edad >= 8 && !recienHecho(RegExp(r'refrigerante|anticongelante'), 36)) {
    salida.add(const Consejo(
      titulo: 'Cambio del refrigerante',
      motivo: 'Con más de ocho años el anticongelante pierde sus aditivos y empieza a corroer el radiador y la bomba.',
      gana: 'Se evitan fugas y un sobrecalentamiento, que es la avería que más motores mata.',
      beneficio: Beneficio.duracion,
      prioridad: 6,
    ));
  }
  if (!recienHecho(RegExp(r'filtro de habit|habit[aá]culo|polen'), 12)) {
    salida.add(const Consejo(
      titulo: 'Filtro de habitáculo',
      motivo: 'Se cambia cada año y suele olvidarse: es el que decide qué aire respiras dentro.',
      gana: 'Menos vaho, menos olores y aire acondicionado con más fuerza.',
      beneficio: Beneficio.rendimiento,
      clave: 'filtro',
      prioridad: 7,
    ));
  }

  salida.sort((a, b) => a.prioridad.compareTo(b.prioridad));
  return salida;
}

/// El texto de cabecera: qué sabe la app del coche para aconsejar.
String resumenParaConsejos(Vehiculo coche) {
  final partes = <String>[];
  if (coche.combustible.isNotEmpty) partes.add(coche.combustible.toLowerCase());
  final a = coche.anioEfectivo;
  if (a != null) partes.add('de $a');
  if (coche.km != null) partes.add('con ${conMiles(coche.km!)} km');
  return partes.isEmpty ? 'Sin datos del coche todavía' : 'Para un ${partes.join(' ')}';
}
