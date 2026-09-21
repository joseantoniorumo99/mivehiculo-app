/// EL MAPA: talleres, gasolineras, lavaderos, recambios y desguaces cerca.
///
/// Distingue DÓNDE ESTÁS de DÓNDE MIRAS. La búsqueda automática va alrededor
/// de ti; «Buscar en esta zona» va alrededor del centro del mapa, porque para
/// eso lo has arrastrado hasta ahí. Pero las distancias se miden SIEMPRE
/// desde ti: "a 249 m" tiene que significar de ti, mires donde mires.
///
/// Las teselas son de OpenStreetMap, con su atribución a la vista porque la
/// licencia lo exige y porque es lo justo. Los sitios llegan por nuestra
/// función en Cloudflare (ver `lugares/lugares.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../estado.dart';
import '../lugares/lugares.dart';
import '../tema.dart';
import 'ficha_lugar.dart';

/// Si no hay ubicación, se mira aquí. Es donde vive el dueño de la app; se
/// cambiará por el centro de España cuando la use más gente.
const LatLng _centroPorDefecto = LatLng(37.5417, -5.8703);

class PantallaMapa extends StatefulWidget {
  /// Si viene de un aviso, el servicio que se busca ("Frenos", "ITV"…).
  final String? servicio;
  const PantallaMapa({super.key, this.servicio});

  @override
  State<PantallaMapa> createState() => _PantallaMapaState();
}

class _PantallaMapaState extends State<PantallaMapa> {
  final _mapa = MapController();
  LatLng? _yo;
  LatLng _centroBuscado = _centroPorDefecto;
  LatLng _centroVista = _centroPorDefecto;
  List<Lugar> _lugares = [];
  bool _cargando = false;
  String? _fallo;
  String? _notaUbicacion;
  String? _notaTeselas;
  TipoLugar? _filtro;
  String? _servicio;
  bool _mapaListo = false;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio;
    _filtro = _servicio != null ? TipoLugar.taller : null;
    _arrancar();
  }

  Future<void> _arrancar() async {
    await _pedirUbicacion();
    await _buscar(_yo ?? _centroPorDefecto);
  }

  /// Pide la ubicación una vez. Si no se puede, se dice por qué y se sigue con
  /// el centro por defecto: un mapa sin ubicación es útil; uno que no carga
  /// hasta que le den permiso, no.
  Future<void> _pedirUbicacion() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notaUbicacion = 'La ubicación del móvil está apagada: enséñame dónde estás '
            'arrastrando el mapa.';
        return;
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        _notaUbicacion = 'Sin permiso de ubicación. Las distancias se miden desde el '
            'centro del mapa.';
        return;
      }
      /// Primero la ÚLTIMA POSICIÓN CONOCIDA, que es instantánea, y el mapa
      /// se centra ya; luego la de verdad, que en un garaje puede tardar o no
      /// llegar nunca. Antes se esperaba solo a la segunda y el mapa se quedaba
      /// en el centro por defecto mientras tanto, que parecía roto.
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        _yo = LatLng(ultima.latitude, ultima.longitude);
        _centroVista = _yo!;
        if (_mapaListo) _mapa.move(_yo!, 13);
        if (mounted) setState(() {});
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 15));
      _yo = LatLng(p.latitude, p.longitude);
      _centroVista = _yo!;
      if (_mapaListo) _mapa.move(_yo!, 13);
    } catch (_) {
      if (_yo == null) {
        _notaUbicacion = 'No he podido saber dónde estás. Las distancias se miden desde '
            'el centro del mapa.';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _buscar(LatLng centro) async {
    setState(() {
      _cargando = true;
      _fallo = null;
      _centroBuscado = centro;
    });
    final r = await buscarLugares(centro.latitude, centro.longitude, radio: 6000);
    if (!mounted) return;
    // Los talleres con ficha publicada que no están en OpenStreetMap (dados
    // de alta a mano) también salen: son los que de verdad reciben citas.
    final publicados = await context.nube.talleresPublicados();
    if (!mounted) return;
    final vistos = r.lista.map((l) => etiquetaDeTaller(l.id)).toSet();
    final extra = publicados
        .where((f) => f.conPunto && !vistos.contains(f.id))
        .where((f) => distanciaKm(centro.latitude, centro.longitude, f.lat!, f.lon!) <= 30)
        .map((f) => f.comoLugar())
        .toList();
    setState(() {
      _lugares = [...r.lista, ...extra];
      _fallo = r.error;
      _cargando = false;
    });
  }

  /// Desde dónde se miden las distancias: desde ti si se sabe; si no, desde
  /// el centro buscado, y la nota de arriba lo dice.
  LatLng get _origen => _yo ?? _centroBuscado;

  double _distancia(Lugar l) =>
      distanciaKm(_origen.latitude, _origen.longitude, l.lat, l.lon);

  List<Lugar> get _visibles {
    var lista = _lugares.where((l) => _filtro == null || l.tipo == _filtro).toList();
    if (_servicio != null) {
      final conServicio = lista.where((l) => l.hace(_servicio!)).toList();
      // Si nadie declara el servicio en OSM, mejor todos los talleres que nada
      if (conServicio.isNotEmpty) lista = conServicio;
    }
    lista.sort((a, b) => _distancia(a).compareTo(_distancia(b)));
    return lista;
  }

  bool get _vistaLejosDeLaBusqueda =>
      distanciaKm(_centroVista.latitude, _centroVista.longitude,
          _centroBuscado.latitude, _centroBuscado.longitude) >
      1.5;

  void _abrir(Lugar l) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PantallaFichaLugar(
                  lugar: l,
                  distancia: _distancia(l),
                  distanciaDesdeTi: _yo != null,
                  servicio: _servicio,
                )),
      );

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    return Scaffold(
      appBar: AppBar(
        title: Text(_servicio != null ? 'Talleres · $_servicio' : 'Cerca de ti'),
        actions: [
          if (_servicio != null)
            IconButton(
              tooltip: 'Quitar el filtro',
              onPressed: () => setState(() => _servicio = null),
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(null, 'Todo'),
                ...TipoLugar.values.map((t) => _chip(t, nombreTipoLugar[t]!)),
              ],
            ),
          ),
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: _yo ?? _centroPorDefecto,
                    initialZoom: 13,
                    onMapReady: () {
                      _mapaListo = true;
                      if (_yo != null) _mapa.move(_yo!, 13);
                    },
                    onPositionChanged: (camara, porGesto) {
                      if (porGesto) setState(() => _centroVista = camara.center);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'es.regislab.mivehiculo',
                      maxZoom: 19,
                      // Si las teselas no llegan (sin red, o el servidor de OSM
                      // corta), se dice una vez en vez de dejar cuadros grises
                      // mudos que parecen un fallo de la app.
                      errorTileCallback: (tesela, error, pila) {
                        if (_notaTeselas != null || !mounted) return;
                        setState(() => _notaTeselas =
                            'El mapa de fondo no está cargando (¿sin conexión?). La '
                            'lista de sitios funciona igual si ya se pidió.');
                      },
                    ),
                    MarkerLayer(
                      markers: [
                        if (_yo != null)
                          Marker(
                            point: _yo!,
                            width: 22,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Tono.azul,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                            ),
                          ),
                        ...visibles.map((l) => Marker(
                              point: LatLng(l.lat, l.lon),
                              width: 36,
                              height: 36,
                              child: GestureDetector(
                                onTap: () => _abrir(l),
                                child: Icon(_iconoDe(l.tipo),
                                    color: l.tipo == TipoLugar.taller ? Tono.azulTinta : Tono.tealTinta,
                                    size: 30,
                                    shadows: const [Shadow(color: Colors.white, blurRadius: 6)]),
                              ),
                            )),
                      ],
                    ),
                    const SimpleAttributionWidget(
                      source: Text('© OpenStreetMap', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                if (_vistaLejosDeLaBusqueda && !_cargando)
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            backgroundColor: Colors.white,
                            foregroundColor: Tono.azulTinta),
                        onPressed: () => _buscar(_centroVista),
                        child: const Text('Buscar en esta zona'),
                      ),
                    ),
                  ),
                if (_cargando)
                  const Positioned(
                    top: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Chip(
                        avatar: SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        label: Text('Buscando sitios…'),
                      ),
                    ),
                  ),
                if (_yo != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'yo',
                      backgroundColor: Colors.white,
                      foregroundColor: Tono.azulTinta,
                      onPressed: () => _mapa.move(_yo!, 14),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                if (_notaUbicacion != null)
                  Recuadro(_notaUbicacion!, tono: TonoEstado.neutro),
                if (_notaTeselas != null)
                  Recuadro(_notaTeselas!, tono: TonoEstado.neutro),
                if (_fallo != null)
                  Recuadro('No he podido pedir los sitios.',
                      consejo: _fallo, tono: TonoEstado.atencion),
                if (!_cargando && _fallo == null && visibles.isEmpty)
                  const Vacio(
                    icono: Icons.location_off_outlined,
                    titulo: 'Nada por aquí',
                    texto: 'OpenStreetMap no tiene sitios de este tipo en esta zona, o '
                        'están sin etiquetar. Prueba a mover el mapa y buscar en '
                        'otra zona.',
                  ),
                ...visibles.map((l) => _fila(l)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(TipoLugar? t, String texto) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 6),
        child: ChoiceChip(
          label: Text(texto),
          selected: _filtro == t,
          onSelected: (_) => setState(() => _filtro = t),
        ),
      );

  IconData _iconoDe(TipoLugar t) => switch (t) {
        TipoLugar.taller => Icons.build_circle,
        TipoLugar.gasolinera => Icons.local_gas_station,
        TipoLugar.lavadero => Icons.local_car_wash,
        TipoLugar.repuestos => Icons.storefront,
        TipoLugar.desguace => Icons.recycling,
      };

  Widget _fila(Lugar l) {
    final estado = l.estadoAhora();
    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _abrir(l),
      child: Row(
        children: [
          PozoIcono(_iconoDe(l.tipo), tamano: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    textoDistancia(_distancia(l)),
                    if (l.direccion.isNotEmpty) l.direccion,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                ),
                if (estado != null)
                  Text(estado,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: estado.startsWith('Abierto') ? Tono.tealTinta : Tono.naranjaTinta)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Tono.tintaSuave),
        ],
      ),
    );
  }
}
