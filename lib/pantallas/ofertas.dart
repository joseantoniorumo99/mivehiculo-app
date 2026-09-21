/// OFERTAS DE TALLERES: lo que los talleres publican desde su panel, en un
/// apartado propio. Es la única "publicidad" de la app, y por eso vive aquí y
/// no en medio del diario: quien quiere mirarla la abre; a quien no, no le
/// corta nada. Es además el modelo de negocio hecho pantalla: el taller
/// llega a quien está cerca y puede necesitarle, sin que nadie le dé una
/// lista de clientes.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../datos/mantenimiento.dart' show enEuros, fechaCorta;
import '../estado.dart';
import '../lugares/lugares.dart';
import '../tema.dart';
import 'ficha_lugar.dart';
import 'pedir_cita.dart';

class PantallaOfertas extends StatefulWidget {
  const PantallaOfertas({super.key});

  @override
  State<PantallaOfertas> createState() => _PantallaOfertasState();
}

class _PantallaOfertasState extends State<PantallaOfertas> {
  List<FichaTaller>? _talleres;
  Position? _yo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final nube = context.nube;
    // La última posición conocida basta para ordenar por distancia; si no la
    // hay, se enseñan sin distancia, que es mejor que esperar.
    try {
      _yo = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    final lista = await nube.talleresPublicados();
    if (!mounted) return;
    setState(() => _talleres = lista.where((f) => f.ofertasVigentes.isNotEmpty).toList());
  }

  double? _distancia(FichaTaller f) {
    final yo = _yo;
    if (yo == null || !f.conPunto) return null;
    return distanciaKm(yo.latitude, yo.longitude, f.lat!, f.lon!);
  }

  @override
  Widget build(BuildContext context) {
    final talleres = _talleres;
    final ordenados = talleres == null
        ? const <FichaTaller>[]
        : ([...talleres]..sort((a, b) => (_distancia(a) ?? 1e9).compareTo(_distancia(b) ?? 1e9)));
    return Scaffold(
      appBar: AppBar(title: const Text('Ofertas de talleres')),
      body: SafeArea(
        child: talleres == null
            ? const Center(child: CircularProgressIndicator())
            : ordenados.isEmpty
                ? const Vacio(
                    icono: Icons.local_offer_outlined,
                    titulo: 'Ninguna oferta ahora mismo',
                    texto: 'Las publican los propios talleres desde su panel. Cuando haya alguna cerca, saldrá aquí.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      const Text(
                        'Publicadas por los propios talleres. Ningún taller paga por salir antes: '
                        'van por cercanía.',
                        style: TextStyle(fontSize: 12, color: Tono.tintaSuave, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      for (final f in ordenados)
                        for (final o in f.ofertasVigentes) _tarjeta(context, f, o),
                    ],
                  ),
      ),
    );
  }

  Widget _tarjeta(BuildContext context, FichaTaller f, Oferta o) {
    final d = _distancia(f);
    final lugar = f.comoLugar();
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              if (o.precio != null)
                Text(enEuros(o.precio),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              f.nombre,
              if (d != null) textoDistancia(d),
              if (o.hasta.isNotEmpty) 'hasta el ${fechaCorta(o.hasta)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
          ),
          if (o.detalle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(o.detalle, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 6),
          ChipEstado(f.verificado ? 'Taller verificado' : 'Taller sin verificar',
              tono: f.verificado ? TonoEstado.calma : TonoEstado.neutro),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PantallaFichaLugar(
                              lugar: lugar, distancia: d ?? 0, distanciaDesdeTi: d != null))),
                  child: const Text('Ver el taller'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PantallaPedirCita(
                              lugar: lugar, servicio: o.servicio.isEmpty ? null : o.servicio))),
                  child: const Text('Pedir cita'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
