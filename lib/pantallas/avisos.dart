/// LOS AVISOS: qué le toca al coche y con qué urgencia.
///
/// Cada aviso lleva dos salidas y no una: "ya está hecho" abre el diario con
/// el tipo puesto, y "buscar taller" abre el mapa filtrado por ese servicio.
/// Un aviso que solo avisa y no da dónde resolverlo es dar la lata.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../estado.dart';
import '../lugares/lugares.dart';
import '../tema.dart';
import 'editar_intervencion.dart';
import 'mapa.dart';

class PantallaAvisos extends StatelessWidget {
  const PantallaAvisos({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) {
            final coche = almacen.coche;
            final avisos = avisosDe(coche, almacen.diarioDelCoche);
            final adblue = estadoAdBlue(coche);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (avisos.isEmpty)
                  const Vacio(
                    icono: Icons.notifications_none,
                    titulo: 'Nada pendiente que sepamos',
                    texto: 'Los avisos de aceite, frenos, neumáticos y correa salen '
                        'de lo que anotes en el diario. Sin saber cuándo se hizo la '
                        'última vez no hay desde dónde contar, y adivinar sería mentir.',
                  )
                else
                  ...avisos.map((a) => _tarjeta(context, a)),
                const SizedBox(height: 8),
                Tarjeta(
                  color: Tono.sueloAlto,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cómo se calculan',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text(
                        'ITV: por la fecha de matriculación y la norma (a los 4 años, '
                        'luego cada 2 hasta los 10, y después cada año). Aceite cada '
                        '15.000 km, neumáticos 40.000, frenos 50.000, correa 120.000: '
                        'intervalos genéricos, el libro de tu coche manda. Se cuenta '
                        'desde la última anotación del diario, incluso si iba dentro '
                        'de una revisión general.',
                        style: TextStyle(color: Tono.tintaSuave, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Text('AdBlue: ${adblue.texto.toLowerCase()}. ${adblue.detalle}',
                          style: const TextStyle(color: Tono.tintaSuave, height: 1.4)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tarjeta(BuildContext context, Aviso a) {
    final (tono, texto) = switch (a.urgencia) {
      Urgencia.alta => (TonoEstado.urgente, 'Urgente'),
      Urgencia.media => (TonoEstado.atencion, 'Pronto'),
      Urgencia.baja => (TonoEstado.calma, 'Sin prisa'),
    };
    final servicio = servicioParaTipo[a.clave];
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.tipo,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              ChipEstado(texto, tono: tono),
            ],
          ),
          const SizedBox(height: 4),
          Text(a.detalle, style: const TextStyle(color: Tono.tintaSuave)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PantallaEditarIntervencion(tipoInicial: a.clave))),
                  child: const Text('Ya está hecho'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => PantallaMapa(servicio: servicio))),
                  child: const Text('Buscar taller'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
