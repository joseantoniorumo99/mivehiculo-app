/// PEDIR CITA sin pasar por el mapa.
///
/// El mapa es para descubrir; pedir cita casi siempre es VOLVER: al taller
/// de siempre, o al que ya te hizo los frenos. Por eso esta pantalla enseña
/// primero los talleres que ya conoces (los de tus citas anteriores), luego
/// lo que le toca al coche —para buscar un taller que haga justo eso— y al
/// final el mapa. Se llega desde el inicio, desde el diario y desde las
/// citas: a un toque, desde donde se está mirando lo que le falta al coche.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../lugares/lugares.dart';
import '../tema.dart';
import 'mapa.dart';
import 'pedir_cita.dart';

class PantallaElegirTaller extends StatelessWidget {
  const PantallaElegirTaller({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedir cita')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) {
            final coche = almacen.coche;
            if (coche == null) {
              return const Vacio(
                icono: Icons.directions_car_outlined,
                titulo: 'Primero el coche',
                texto: 'Da de alta tu coche en el inicio y luego pide la cita.',
              );
            }
            final conocidos = _talleresConocidos(almacen.citasDelCoche);
            final avisos = avisosDe(coche, almacen.diarioDelCoche);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (!context.nube.conSesion)
                  const Recuadro(
                    'Sin cuenta, la cita se anota en tu móvil y hay que llamar.',
                    consejo: 'Con cuenta se envía al taller y te avisamos cuando conteste.',
                    tono: TonoEstado.atencion,
                  ),
                const TituloSeccion('Talleres que ya conoces'),
                if (conocidos.isEmpty)
                  const Tarjeta(
                    child: Text(
                      'Todavía ninguno. El primero lo eliges en el mapa; a partir de '
                      'ahí saldrá aquí para repetir en un toque.',
                      style: TextStyle(color: Tono.tintaSuave, height: 1.4),
                    ),
                  )
                else
                  ...conocidos.map((t) => Tarjeta(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => PantallaPedirCita(lugar: t.lugar))),
                        child: Row(
                          children: [
                            const PozoIcono(Icons.home_repair_service_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.lugar.nombre,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(
                                    '${t.veces == 1 ? 'Una cita' : '${t.veces} citas'} · última: '
                                    '${fechaCorta(t.ultimaFecha)}${t.ultimoServicio.isNotEmpty ? ' · ${t.ultimoServicio}' : ''}',
                                    style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Tono.tintaSuave),
                          ],
                        ),
                      )),
                if (avisos.isNotEmpty) ...[
                  const TituloSeccion('Para lo que toca'),
                  ...avisos.map((a) => Tarjeta(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => PantallaMapa(servicio: servicioParaTipo[a.clave]))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.tipo, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(a.detalle,
                                      style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                                ],
                              ),
                            ),
                            ChipEstado(
                              'Buscar taller',
                              tono: switch (a.urgencia) {
                                Urgencia.alta => TonoEstado.urgente,
                                Urgencia.media => TonoEstado.atencion,
                                Urgencia.baja => TonoEstado.accion,
                              },
                            ),
                          ],
                        ),
                      )),
                ],
                const TituloSeccion('Otro taller'),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const PantallaMapa())),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Buscar un taller en el mapa'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Talleres cercanos con horario y teléfono. Desde su ficha se pide la cita.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TallerConocido {
  final Lugar lugar;
  final int veces;
  final String ultimaFecha;
  final String ultimoServicio;
  const _TallerConocido(this.lugar, this.veces, this.ultimaFecha, this.ultimoServicio);
}

/// Los talleres de las citas anteriores, el más reciente primero. Se
/// reconstruye un `Lugar` con lo que la cita guardó (id y nombre): sin
/// coordenadas, porque para pedir cita no hacen falta. Los servicios que se
/// ofrecen son los de las citas anteriores más los tipos de mantenimiento.
List<_TallerConocido> _talleresConocidos(List<Cita> citas) {
  final ordenadas = [...citas]..sort((a, b) => b.fecha.compareTo(a.fecha));
  final porId = <String, List<Cita>>{};
  for (final c in ordenadas) {
    if (c.lugarId.isEmpty || c.lugarNombre.isEmpty) continue;
    porId.putIfAbsent(c.lugarId, () => []).add(c);
  }
  return porId.entries.map((e) {
    final lista = e.value;
    final servicios = <String>{
      ...lista.map((c) => c.servicio).where((s) => s.isNotEmpty),
      ...tiposMantenimiento.entries.where((t) => t.key != 'otro').map((t) => t.value),
    };
    return _TallerConocido(
      Lugar(
        id: e.key,
        tipo: TipoLugar.taller,
        nombre: lista.first.lugarNombre,
        lat: 0,
        lon: 0,
        servicios: servicios.toList(),
      ),
      lista.length,
      lista.first.fecha,
      lista.first.servicio,
    );
  }).toList();
}
