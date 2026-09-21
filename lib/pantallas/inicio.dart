/// EL INICIO: cuatro cifras, una gráfica y lo que toca.
///
/// La forma viene de una referencia que trajo el dueño de la app: rejilla 2x2
/// de cifras con chip de variación y barras agrupadas debajo, con el selector
/// de periodo arriba. Las reglas que la gobiernan están en `datos/panel.dart`
/// y son lo que hace fiable al panel: ningún porcentaje sin dos periodos
/// comparables, y ninguna gráfica plana fingiendo ser un dato.
///
/// LOS RÓTULOS DE LA GRÁFICA SON WIDGETS, NO DIBUJO. En la web se aprendió a
/// golpes: un texto dentro de un lienzo escalado mide distinto en cada móvil y
/// a 320 px caía por debajo de los 12 px legibles. Aquí el lienzo dibuja solo
/// barras; las letras van fuera, en Text normal, y miden lo que miden.
library;

import 'package:flutter/material.dart';

import '../datos/consejos.dart';
import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../datos/panel.dart';
import '../estado.dart';
import '../tema.dart';
import 'alta_vehiculo.dart';
import 'avisos.dart';
import 'citas.dart';
import 'editar_intervencion.dart';
import 'elegir_taller.dart';
import 'expediente.dart';
import 'garaje.dart';
import 'mejoras.dart';
import 'ofertas.dart';

class PantallaInicio extends StatefulWidget {
  /// Para saltar a otra pestaña ('diario', 'obd', 'mapa', 'perfil').
  final void Function(String destino) irA;
  const PantallaInicio({super.key, required this.irA});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  Periodo _periodo = Periodo.anio;
  int? _grupoTocado;

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return ListenableBuilder(
      listenable: almacen,
      builder: (context, _) {
        final coche = almacen.coche;
        if (coche == null) return _sinCoche(context);

        final diario = almacen.diarioDelCoche;
        final metricas = metricasDe(coche, diario, _periodo);
        final serie = serieGasto(diario, _periodo);
        final avisos = avisosDe(coche, diario);

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _cabecera(context, coche.nombre, coche.matricula, almacen.variosVehiculos,
                    verificado: coche.verificado),
                const SizedBox(height: 14),
                if (!coche.verificado) _verificacionCoche(context, coche),
                _ofertasCerca(context),
                // Si hay versión nueva, se dice aquí, donde se mira. Instalar
                // vive en el perfil: un botón de descarga en la portada es
                // demasiado fácil de tocar sin querer.
                ListenableBuilder(
                  listenable: context.actualizacion,
                  builder: (context, _) {
                    final a = context.actualizacion;
                    if (!a.hayNueva) return const SizedBox.shrink();
                    return Recuadro(
                      'Hay una versión nueva: ${a.versionNueva}',
                      consejo: 'Se instala desde Perfil → Versión, en un minuto.',
                      tono: TonoEstado.accion,
                      accion: TextButton(
                        onPressed: () => widget.irA('perfil'),
                        child: const Text('Ir al perfil'),
                      ),
                    );
                  },
                ),
                // Lo que el taller ha hecho con tus citas: confirmada (con su
                // tiempo y forma de pago), rechazada, o el informe pendiente
                // de pasar al diario. Desaparecen solos al pasar la fecha o al
                // añadir el informe: no hay que "marcar como leído".
                ..._citasQueImportan(context, almacen.citasDelCoche),
                _selectorPeriodo(),
                const SizedBox(height: 14),
                _rejilla(context, metricas),
                const SizedBox(height: 6),
                _grafica(serie),
                const SizedBox(height: 6),
                TituloSeccion(
                  'Lo que toca',
                  accion: avisos.isNotEmpty
                      ? TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const PantallaAvisos())),
                          child: const Text('Ver todos'),
                        )
                      : null,
                ),
                if (avisos.isEmpty)
                  const Tarjeta(
                    child: Text(
                      'Nada pendiente que sepamos. Los avisos de aceite, frenos, '
                      'neumáticos y correa salen de lo que anotes en el diario: sin '
                      'saber cuándo se hizo la última vez, no se avisa.',
                      style: TextStyle(color: Tono.tintaSuave, height: 1.4),
                    ),
                  )
                else
                  ...avisos.take(3).map((a) => _filaAviso(context, a)),
                const SizedBox(height: 8),
                // Lo que le vendría bien al coche, más allá de lo que toca.
                Builder(builder: (context) {
                  final consejos = consejosPara(coche, diario);
                  if (consejos.isEmpty) return const SizedBox.shrink();
                  return Tarjeta(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const PantallaMejoras())),
                    child: Row(
                      children: [
                        const PozoIcono(Icons.auto_awesome_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Mejoras para tu coche',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                '${consejos.length} ${consejos.length == 1 ? 'consejo' : 'consejos'}: '
                                '${consejos.first.titulo.toLowerCase()}${consejos.length > 1 ? ' y más' : ''}',
                                style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Tono.tintaSuave),
                      ],
                    ),
                  );
                }),
                const TituloSeccion('Atajos'),
                Row(
                  children: [
                    Expanded(child: _atajo(Icons.edit_note, 'Anotar', () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PantallaEditarIntervencion())))),
                    const SizedBox(width: 10),
                    Expanded(child: _atajo(Icons.bluetooth_searching, 'Leer OBD', () => widget.irA('obd'))),
                    const SizedBox(width: 10),
                    Expanded(child: _atajo(Icons.event_available, 'Pedir cita', () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PantallaElegirTaller())))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sinCoche(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Vacio(
                icono: Icons.directions_car_outlined,
                titulo: 'Empieza por tu coche',
                texto: 'Con la matrícula, la marca y el modelo la app ya sabe cuándo '
                    'te toca la ITV. Lo demás lo va aprendiendo del diario.',
                accion: FilledButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PantallaAltaVehiculo())),
                  child: const Text('Añadir mi coche'),
                ),
              ),
            ),
          ),
        ),
      );

  /// El título ES el botón del garaje. No hay otro.
  /// El coche verificado: el bastidor de la ficha técnica y el del OBD son el
  /// mismo. Dos pasos, y se dice cuál falta. Sin papeles guardados.
  Widget _verificacionCoche(BuildContext context, Vehiculo coche) {
    if (coche.bastidoresDiscrepan) {
      return Recuadro(
        'El bastidor de la ficha técnica y el del coche no coinciden',
        consejo: 'Ficha: ${coche.bastidorFicha} · OBD: ${coche.bastidorObd}. Vuelve a fotografiar '
            'la ficha con más luz; si siguen sin cuadrar, la ficha no es de este coche.',
        tono: TonoEstado.atencion,
        accion: TextButton(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PantallaAltaVehiculo(editar: coche))),
          child: const Text('Repetir la foto de la ficha'),
        ),
      );
    }
    final faltaFicha = coche.bastidorFicha.isEmpty;
    final faltaObd = coche.bastidorObd.isEmpty;
    return Recuadro(
      'Coche sin verificar · ${coche.pasosVerificacion} de 2 pasos',
      consejo: faltaFicha && faltaObd
          ? 'Una foto de la ficha técnica y una lectura del OBD: si el bastidor coincide, el '
              'coche queda verificado y el expediente vale más al venderlo.'
          : faltaFicha
              ? 'Ya tienes el bastidor del OBD. Falta la foto de la ficha técnica.'
              : 'Ya tienes el bastidor de la ficha. Falta leer el OBD dentro del coche.',
      tono: TonoEstado.neutro,
      accion: Row(
        children: [
          if (faltaFicha)
            TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PantallaAltaVehiculo(editar: coche))),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Foto de la ficha'),
            ),
          if (faltaObd)
            TextButton.icon(
              onPressed: () => widget.irA('obd'),
              icon: const Icon(Icons.bluetooth_searching, size: 18),
              label: const Text('Leer el OBD'),
            ),
        ],
      ),
    );
  }

  /// Las ofertas de los talleres publicados, si hay alguna vigente.
  Widget _ofertasCerca(BuildContext context) => FutureBuilder<int>(
        future: context.nube.talleresPublicados().then(
            (lista) => lista.fold<int>(0, (n, f) => n + f.ofertasVigentes.length)),
        builder: (context, snap) {
          final n = snap.data ?? 0;
          if (n == 0) return const SizedBox.shrink();
          return Tarjeta(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const PantallaOfertas())),
            child: Row(
              children: [
                const PozoIcono(Icons.local_offer_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ofertas de talleres',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('$n ${n == 1 ? 'oferta vigente' : 'ofertas vigentes'} cerca de ti',
                          style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Tono.tintaSuave),
              ],
            ),
          );
        },
      );

  Widget _cabecera(BuildContext context, String nombre, String matricula, bool varios,
          {bool verificado = false}) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaGaraje())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    if (matricula.isNotEmpty || verificado)
                      Row(
                        children: [
                          if (matricula.isNotEmpty)
                            Text(matricula, style: const TextStyle(color: Tono.tintaSuave, fontSize: 14)),
                          if (verificado) ...[
                            const SizedBox(width: 8),
                            const ChipEstado('Coche verificado', tono: TonoEstado.calma),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              Icon(varios ? Icons.swap_horiz : Icons.chevron_right, color: Tono.tintaSuave),
            ],
          ),
        ),
      );

  Widget _selectorPeriodo() => SegmentedButton<Periodo>(
        segments: Periodo.values
            .map((p) => ButtonSegment(value: p, label: Text(nombrePeriodo[p]!)))
            .toList(),
        selected: {_periodo},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          _periodo = s.first;
          _grupoTocado = null;
        }),
      );

  Widget _rejilla(BuildContext context, List<Metrica> metricas) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
        children: metricas.map((m) => _metrica(context, m)).toList(),
      );

  Widget _metrica(BuildContext context, Metrica m) {
    final icono = switch (m.destino) {
      DestinoMetrica.editarCoche => Icons.route_outlined,
      DestinoMetrica.expediente => Icons.receipt_long_outlined,
      DestinoMetrica.avisos => Icons.notifications_none,
      DestinoMetrica.diario => Icons.menu_book_outlined,
    };
    return Semantics(
      button: true,
      label: '${m.etiqueta}: ${m.valor} ${m.unidad}. ${m.describe}',
      child: Tarjeta(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(14),
        onTap: () => _irAMetrica(context, m.destino),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                PozoIcono(icono, tamano: 34),
                if (m.chip != null) ChipEstado(m.chip!.texto, tono: _tonoChip(m.chip!.tono)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.etiqueta, style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(m.valor,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                    if (m.unidad.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(m.unidad, style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                    ],
                  ],
                ),
                if (m.nota != null)
                  Text(m.nota!, style: const TextStyle(fontSize: 12, color: Tono.naranjaTinta)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TonoEstado _tonoChip(TonoChip t) => switch (t) {
        TonoChip.urgente => TonoEstado.urgente,
        TonoChip.atencion => TonoEstado.atencion,
        TonoChip.sube => TonoEstado.urgente,
        TonoChip.calma => TonoEstado.calma,
      };

  void _irAMetrica(BuildContext context, DestinoMetrica d) {
    final almacen = context.almacen;
    switch (d) {
      case DestinoMetrica.editarCoche:
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => PantallaAltaVehiculo(editar: almacen.coche)));
      case DestinoMetrica.expediente:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaExpediente()));
      case DestinoMetrica.avisos:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaAvisos()));
      case DestinoMetrica.diario:
        widget.irA('diario');
    }
  }

  Widget _grafica(Serie serie) {
    final tope = topeRedondo(serie.maximo);
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Gasto · ${serie.titulo}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (serie.nombrePrevio != null) ...[
                _leyenda(Tono.azul, serie.titulo),
                const SizedBox(width: 10),
                _leyenda(const Color(0x4D2B6CB0), serie.nombrePrevio!),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (serie.vacia)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Todavía no hay nada que dibujar. Cuando anotes una factura en el '
                'diario, aquí sale el gasto por periodo.',
                style: TextStyle(color: Tono.tintaSuave, height: 1.4),
              ),
            )
          else ...[
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Eje: tres marcas, en texto de verdad
                  SizedBox(
                    width: 44,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _marcaEje(tope),
                        _marcaEje(tope / 2),
                        _marcaEje(0),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => GestureDetector(
                        onTapDown: (d) {
                          final i = (d.localPosition.dx / (c.maxWidth / serie.grupos.length)).floor();
                          setState(() => _grupoTocado = i == _grupoTocado ? null : i);
                        },
                        child: CustomPaint(
                          painter: _PintorBarras(serie, tope, _grupoTocado),
                          size: Size(c.maxWidth, 140),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 52),
                ...serie.grupos.map((g) => Expanded(
                      child: Text(g.etiqueta,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                    )),
              ],
            ),
            if (_grupoTocado != null && _grupoTocado! < serie.grupos.length) ...[
              const SizedBox(height: 10),
              Builder(builder: (_) {
                final g = serie.grupos[_grupoTocado!];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Tono.azulFilm,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${g.nombre[0].toUpperCase()}${g.nombre.substring(1)}: ${enEuros(g.actual)}'
                    '${g.hayPrevio ? ' · antes ${enEuros(g.previo)}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Tono.azulTinta),
                  ),
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _marcaEje(double v) => Text(
        v == 0 ? '0' : (v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)} k€' : '${v.round()} €'),
        style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
      );

  Widget _leyenda(Color color, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(texto, style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
        ],
      );

  Widget _filaAviso(BuildContext context, Aviso a) {
    final tono = switch (a.urgencia) {
      Urgencia.alta => TonoEstado.urgente,
      Urgencia.media => TonoEstado.atencion,
      Urgencia.baja => TonoEstado.calma,
    };
    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaAvisos())),
      child: Row(
        children: [
          PozoIcono(
            a.clave == 'itv' ? Icons.verified_outlined : Icons.build_outlined,
            tamano: 36,
            fondo: switch (tono) {
              TonoEstado.urgente => Tono.rojoFilm,
              TonoEstado.atencion => Tono.naranjaFilm,
              _ => Tono.tealFilm,
            },
            tinta: switch (tono) {
              TonoEstado.urgente => Tono.rojoTinta,
              TonoEstado.atencion => Tono.naranjaTinta,
              _ => Tono.tealTinta,
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.tipo, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(a.detalle, style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Tono.tintaSuave),
        ],
      ),
    );
  }

  List<Widget> _citasQueImportan(BuildContext context, List<Cita> citas) {
    final hoy = hoyIso();
    final salida = <Widget>[];
    void verCitas() => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaCitas()));
    for (final c in citas) {
      if (salida.length >= 3) break;
      final taller = c.lugarNombre.isEmpty ? 'El taller' : c.lugarNombre;
      if (c.hayInforme && !c.informeAnadido) {
        salida.add(Recuadro(
          '$taller te ha mandado el informe'
          '${c.informeTitulo.isNotEmpty ? ' de «${c.informeTitulo}»' : ''}',
          consejo: 'Añádelo al diario de un toque: así cuenta en el expediente y en los avisos.',
          tono: TonoEstado.accion,
          accion: TextButton(onPressed: verCitas, child: const Text('Ver el informe')),
        ));
      } else if (c.estado == EstadoCita.confirmada && c.fecha.compareTo(hoy) >= 0) {
        salida.add(Recuadro(
          'Cita confirmada en $taller: ${fechaCorta(c.fecha)}'
          '${c.hora.isNotEmpty ? ' a las ${c.hora}' : ''}',
          consejo: c.textoRespuesta.isEmpty ? null : c.textoRespuesta,
          tono: TonoEstado.calma,
          accion: TextButton(onPressed: verCitas, child: const Text('Ver la cita')),
        ));
      } else if (c.estado == EstadoCita.rechazada && c.fecha.compareTo(hoy) >= 0) {
        salida.add(Recuadro(
          '$taller no puede atenderte el ${fechaCorta(c.fecha)}',
          consejo: c.motivo.isNotEmpty ? c.motivo : 'Puedes pedir otra fecha o buscar otro taller.',
          tono: TonoEstado.atencion,
          accion: TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PantallaElegirTaller())),
            child: const Text('Pedir otra fecha'),
          ),
        ));
      }
    }
    return salida;
  }

  Widget _atajo(IconData icono, String texto, VoidCallback alPulsar) => Tarjeta(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(vertical: 14),
        onTap: alPulsar,
        child: Column(
          children: [
            Icon(icono, color: Tono.azulTinta),
            const SizedBox(height: 6),
            Text(texto, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Solo barras. Ni una letra: las letras van fuera, en Text.
class _PintorBarras extends CustomPainter {
  final Serie serie;
  final double tope;
  final int? tocado;
  _PintorBarras(this.serie, this.tope, this.tocado);

  @override
  void paint(Canvas lienzo, Size tam) {
    final n = serie.grupos.length;
    if (n == 0) return;
    final ancho = tam.width / n;
    final conPrevio = serie.nombrePrevio != null;
    final anchoBarra = conPrevio ? ancho * 0.28 : ancho * 0.44;
    final hueco = conPrevio ? ancho * 0.06 : 0.0;

    final regla = Paint()
      ..color = Tono.regla
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = tam.height - f * tam.height;
      lienzo.drawLine(Offset(0, y), Offset(tam.width, y), regla);
    }

    for (var i = 0; i < n; i++) {
      final g = serie.grupos[i];
      final centro = ancho * i + ancho / 2;
      final resaltado = tocado == null || tocado == i;

      void barra(double x, double valor, Color color) {
        final h = tope <= 0 ? 0.0 : (valor / tope) * tam.height;
        final r = RRect.fromRectAndCorners(
          Rect.fromLTWH(x, tam.height - h, anchoBarra, h),
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        );
        lienzo.drawRRect(
            r, Paint()..color = resaltado ? color : color.withValues(alpha: 0.35));
        // Un cero se dibuja como una línea a ras: "no gastaste nada" se ve.
        if (h < 2) {
          lienzo.drawRect(Rect.fromLTWH(x, tam.height - 2, anchoBarra, 2),
              Paint()..color = color.withValues(alpha: 0.5));
        }
      }

      if (conPrevio) {
        barra(centro - anchoBarra - hueco / 2, g.previo, const Color(0x662B6CB0));
        barra(centro + hueco / 2, g.actual, Tono.azul);
      } else {
        barra(centro - anchoBarra / 2, g.actual, Tono.azul);
      }
    }
  }

  @override
  bool shouldRepaint(_PintorBarras old) =>
      old.serie != serie || old.tope != tope || old.tocado != tocado;
}
