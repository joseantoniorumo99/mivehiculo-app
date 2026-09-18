/// MEJORAS ACONSEJADAS PARA TU COCHE: piezas y trabajos que mejoran cómo va,
/// deducidos de lo que la app sabe de él. Cada uno con su motivo, lo que se
/// gana, y el botón que lleva a los talleres que lo hacen.
///
/// No son avisos: nada de aquí "toca". Es lo que un buen mecánico te diría
/// si te sentaras con él diez minutos, y por eso se dice de dónde sale cada
/// consejo y que el libro del coche manda.
library;

import 'package:flutter/material.dart';

import '../datos/consejos.dart';
import '../estado.dart';
import '../tema.dart';
import 'editar_intervencion.dart';
import 'mapa.dart';

class PantallaMejoras extends StatelessWidget {
  const PantallaMejoras({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Mejoras para tu coche')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) {
            final coche = almacen.coche;
            if (coche == null) {
              return const Vacio(
                icono: Icons.auto_awesome_outlined,
                titulo: 'Primero el coche',
                texto: 'Con el combustible, el año y los kilómetros ya se puede aconsejar.',
              );
            }
            final consejos = consejosPara(coche, almacen.diarioDelCoche);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(resumenParaConsejos(coche),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Orientativo: sale del combustible, la edad, los kilómetros y lo que consta '
                  'en el diario. El libro de mantenimiento de tu coche manda.',
                  style: TextStyle(fontSize: 12, color: Tono.tintaSuave, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (consejos.isEmpty)
                  const Tarjeta(
                    child: Text(
                      'Nada que aconsejar con lo que se sabe. Pon el combustible, el año y '
                      'los kilómetros en la ficha del coche y aquí saldrá lo que le venga bien.',
                      style: TextStyle(color: Tono.tintaSuave, height: 1.4),
                    ),
                  )
                else
                  ...consejos.map((c) => _tarjeta(context, c)),
                const SizedBox(height: 8),
                const Text(
                  'Ningún precio se inventa: lo que cueste lo pone cada taller en su ficha. '
                  'Cuando lo hagas, anótalo en el diario y el consejo desaparece solo.',
                  style: TextStyle(fontSize: 12, color: Tono.tintaSuave, height: 1.4),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tarjeta(BuildContext context, Consejo c) {
    final tono = switch (c.beneficio) {
      Beneficio.seguridad => TonoEstado.urgente,
      Beneficio.rendimiento => TonoEstado.accion,
      Beneficio.consumo => TonoEstado.calma,
      Beneficio.duracion => TonoEstado.neutro,
    };
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              ChipEstado(nombreBeneficio[c.beneficio]!, tono: tono),
            ],
          ),
          const SizedBox(height: 8),
          Text(c.motivo, style: const TextStyle(height: 1.45)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.trending_up, size: 18, color: Tono.tealTinta),
              const SizedBox(width: 6),
              Expanded(
                child: Text(c.gana,
                    style: const TextStyle(color: Tono.tealTinta, fontWeight: FontWeight.w600, height: 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PantallaEditarIntervencion(tipoInicial: c.clave == 'otro' ? null : c.clave))),
                  child: const Text('Ya está hecho'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => PantallaMapa(servicio: c.servicio))),
                  child: const Text('Talleres que lo hacen'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
