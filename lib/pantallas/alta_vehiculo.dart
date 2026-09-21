/// DAR DE ALTA UN COCHE, o corregir uno.
///
/// El orden de los campos no es casual: la MATRÍCULA va primero porque de
/// ella sale gratis el mes de matriculación (y con él la ITV exacta), y
/// porque es lo único que el dueño sabe de memoria. Marca, modelo y motor
/// vienen del catálogo de matriculaciones reales, con autocompletar y no con
/// un desplegable: con 763 modelos un desplegable en un móvil es inservible.
///
/// LO QUE ESTA PANTALLA NO HACE: adivinar marca y modelo por la matrícula.
/// Eso solo lo da la DGT o un proveedor de pago, y una app que "deduce" el
/// modelo acierta un 60 % y da 700 € de historial al coche equivocado el
/// otro 40 %.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../datos/catalogo.dart';
import '../datos/ficha_tecnica.dart';
import '../datos/ocr_ficha.dart';
import '../datos/mantenimiento.dart';
import '../datos/matricula.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';

class PantallaAltaVehiculo extends StatefulWidget {
  final Vehiculo? editar;
  const PantallaAltaVehiculo({super.key, this.editar});

  @override
  State<PantallaAltaVehiculo> createState() => _PantallaAltaVehiculoState();
}

/// La tarjeta ITV en esquema: los códigos y qué es cada uno, en el orden en
/// que van impresos. No es un ejemplo con datos —no hay ninguno inventado—,
/// es el mapa de dónde mirar.
class _EsquemaFicha extends StatelessWidget {
  const _EsquemaFicha();

  static const _filas = [
    ('A', 'Matrícula'),
    ('B', 'Fecha de primera matriculación'),
    ('D.1', 'Marca'),
    ('D.2', 'Tipo, variante y versión'),
    ('D.3', 'Denominación comercial (modelo)'),
    ('E', 'Número de bastidor (17 caracteres)'),
    ('P.1', 'Cilindrada (cm³)'),
    ('P.2', 'Potencia (kW)'),
    ('P.3', 'Combustible'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FB),
          border: Border.all(color: Tono.azul.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TARJETA ITV · FICHA TÉCNICA',
                style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Tono.azulTinta)),
            const SizedBox(height: 6),
            ..._filas.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(4)),
                        child: Text(f.$1,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(3)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(f.$2, style: const TextStyle(fontSize: 10, color: Tono.tintaSuave)),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      );
}

class _PantallaAltaVehiculoState extends State<PantallaAltaVehiculo> {
  final _forma = GlobalKey<FormState>();
  late final TextEditingController _matricula;
  late final TextEditingController _marca;
  late final TextEditingController _modelo;
  late final TextEditingController _anio;
  late final TextEditingController _km;
  late final TextEditingController _matriculacion;

  /// LOS FOCOS VIVEN AQUÍ, no se crean al pintar. La primera versión hacía
  /// `FocusNode()` dentro del builder del autocompletar, y como cada tecla
  /// repinta la pantalla, cada tecla creaba un foco nuevo: al tocar otro
  /// campo con el dedo el foco se perdía y no dejaba escribir; solo el Enter
  /// del teclado funcionaba. Se notó en el coche, con el formulario delante.
  final _focoMarca = FocusNode();
  final _focoModelo = FocusNode();
  String _combustible = '';
  String _adBlue = 'auto';
  Catalogo? _catalogo;
  bool _cargandoCatalogo = true;
  String? _notaMatricula;
  String? _notaAnio;

  /// La motorización elegida en el desplegable (su etiqueta larga). No se
  /// guarda en el coche —lo que se guarda es el combustible—, pero hay que
  /// recordarla para que el desplegable enseñe lo que se eligió.
  String? _motorElegido;
  bool _guardando = false;

  /// Lo que se leyó de la foto de la ficha técnica y no tiene campo en el
  /// formulario: el bastidor se guarda con el coche; la cilindrada y la
  /// potencia sirven para preseleccionar la motorización.
  String _bastidorLeido = '';
  int? _cilindradaLeida;
  int? _potenciaLeida;
  bool _leyendoFicha = false;
  String? _notaFicha;

  /// «Más tarde»: la tarjeta de la ficha técnica se recoge y el formulario
  /// sigue a mano. Se puede volver a ella desde el inicio cuando quiera.
  bool _fichaMasTarde = false;

  /// La foto de la ficha técnica: ML Kit saca el texto, `leerFichaTecnica`
  /// lo interpreta, y aquí se RELLENAN LOS HUECOS. Lo que el dueño ya
  /// escribió no se toca: propone, no decide.
  Future<void> _leerFichaTecnica(ImageSource origen) async {
    final elegida = await ImagePicker().pickImage(source: origen, maxWidth: 2400, imageQuality: 92);
    if (elegida == null || !mounted) return;
    setState(() {
      _leyendoFicha = true;
      _notaFicha = null;
    });
    try {
      final texto = await textoDeLaFoto(elegida.path);
      final d = leerFichaTecnica(texto, marcasConocidas: _catalogo?.listaMarcas ?? const []);
      if (!mounted) return;
      if (!d.hayAlgo) {
        setState(() => _notaFicha = 'No se ha podido leer nada claro. Prueba con más luz, la tarjeta plana y sin reflejos.');
        return;
      }
      final rellenado = <String>[];
      setState(() {
        if (d.matricula != null && _matricula.text.trim().isEmpty) {
          _matricula.text = d.matricula!;
          rellenado.add('matrícula');
        }
        if (d.marca != null && _marca.text.trim().isEmpty) {
          _marca.text = d.marca!;
          rellenado.add('marca');
        }
        if (d.modelo != null && _modelo.text.trim().isEmpty) {
          _modelo.text = _modeloDelCatalogo(d.modelo!);
          rellenado.add('modelo');
        }
        if (d.matriculacion != null) {
          if (_matriculacion.text.trim().isEmpty) _matriculacion.text = d.matriculacion!.substring(0, 7);
          if (_anio.text.trim().isEmpty) {
            _anio.text = '${d.anio}';
            rellenado.add('año');
          }
        }
        if (d.combustible != null && _combustible.isEmpty) {
          _combustible = d.combustible!;
          rellenado.add('combustible');
        }
        if (d.bastidor != null) {
          _bastidorLeido = d.bastidor!;
          rellenado.add('bastidor');
        }
        _cilindradaLeida = d.cilindrada;
        _potenciaLeida = d.potenciaKw;
        _elegirMotorPorFicha();
        final noLeido = ['matrícula', 'marca', 'modelo', 'fecha de matriculación', 'combustible', 'bastidor']
            .where((x) => !d.leido.contains(x))
            .toList();
        final leidoTexto = rellenado.isEmpty
            ? 'Leído, pero los campos ya estaban escritos: no se ha cambiado nada.'
            : 'Rellenado desde la ficha: ${rellenado.join(', ')}.';
        final faltaTexto = noLeido.isEmpty ? '' : ' No se ha leído: ${noLeido.join(', ')}.';
        _notaFicha = '$leidoTexto$faltaTexto Revísalo antes de guardar.';
      });
    } catch (e) {
      if (mounted) setState(() => _notaFicha = 'No se ha podido leer la foto: $e');
    } finally {
      if (mounted) setState(() => _leyendoFicha = false);
    }
  }

  /// "C3" leído → "C3" del catálogo si existe con esa marca; si no, tal cual.
  String _modeloDelCatalogo(String leido) {
    final c = _catalogo;
    if (c == null || _marca.text.isEmpty) return leido;
    final l = leido.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final m in c.modelosDe(_marca.text)) {
      if (m.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == l) return m;
    }
    return leido;
  }

  /// Con cilindrada y potencia de la ficha, la motorización sale sola: es el
  /// dato exacto (1.560 cm³ y 73 kW es el 1.6 HDi de 100 CV, sin adivinar).
  void _elegirMotorPorFicha() {
    final cc = _cilindradaLeida;
    if (cc == null) return;
    final cv = _potenciaLeida == null ? null : (_potenciaLeida! * 1.35962).round();
    Motor? mejor;
    for (final m in _motores) {
      if ((m.cilindrada - cc).abs() > 30) continue;
      if (_combustible.isNotEmpty && m.combustible != _combustible) continue;
      if (cv != null && m.cv > 0 && (m.cv - cv).abs() > 6) continue;
      if (mejor == null || (cv != null && m.cv > 0 && mejor.cv == 0)) mejor = m;
    }
    if (mejor != null) {
      _motorElegido = mejor.etiquetaLarga;
      _combustible = mejor.combustible;
    }
  }

  /// La tarjeta ITV, dibujada: dónde está cada dato. Se enseña al dueño para
  /// que sepa qué fotografiar (y qué es "la ficha técnica", que no todo el
  /// mundo lo sabe).
  void _explicarFichaTecnica() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('La ficha técnica'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Es la tarjeta azul o verde que va con el permiso de circulación '
                '(tarjeta ITV). Lleva los datos del coche con códigos fijos; la app '
                'busca esos códigos en la foto:',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              _EsquemaFicha(),
              const SizedBox(height: 10),
              const Text(
                'Haz la foto con la tarjeta plana, con luz y sin reflejos. La foto no '
                'sale del móvil.',
                style: TextStyle(fontSize: 12, color: Tono.tintaSuave, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
      ),
    );
  }

  /// EL AÑO QUE ESCRIBE EL DUEÑO MANDA sobre lo que diga la matrícula. La
  /// matrícula data la matriculación EN ESPAÑA: un coche importado de segunda
  /// mano lleva matrícula del día que llegó, y para la ITV cuenta su primera
  /// matriculación en origen. Si el año escrito no cuadra con el de la
  /// matrícula, se deja de fiar de la matrícula para la fecha y se dice.
  void _alCambiarAnio(String texto) {
    final anio = int.tryParse(texto.trim());
    setState(() {
      _notaAnio = null;
      if (anio == null) return;
      final f = fechaDeMatricula(_matricula.text);
      if (f != null && f.anio != anio) {
        if (_matriculacion.text.startsWith('${f.anio}-')) _matriculacion.clear();
        _notaAnio = 'La matrícula apunta a ${f.anio}, pero manda el año que pongas. '
            'Si el coche vino de fuera, pon abajo el mes de su primera '
            'matriculación en origen: es el que vale para la ITV.';
      }
    });
  }

  bool get _esEdicion => widget.editar != null;

  @override
  void initState() {
    super.initState();
    final v = widget.editar;
    _matricula = TextEditingController(text: v?.matricula ?? '');
    _marca = TextEditingController(text: v?.marca ?? '');
    _modelo = TextEditingController(text: v?.modelo ?? '');
    _anio = TextEditingController(text: v?.anio?.toString() ?? '');
    _km = TextEditingController(text: v?.km?.toString() ?? '');
    _matriculacion = TextEditingController(text: v?.matriculacion ?? '');
    _combustible = v?.combustible ?? '';
    _adBlue = v?.adBlue ?? 'auto';
    Catalogo.cargar().then((c) {
      if (!mounted) return;
      setState(() {
        _catalogo = c;
        _cargandoCatalogo = false;
      });
    });
    _matricula.addListener(_alCambiarMatricula);
  }

  @override
  void dispose() {
    _matricula.dispose();
    _marca.dispose();
    _modelo.dispose();
    _anio.dispose();
    _km.dispose();
    _matriculacion.dispose();
    _focoMarca.dispose();
    _focoModelo.dispose();
    super.dispose();
  }

  /// De la matrícula sale el mes de matriculación. Solo se rellena si el
  /// campo está vacío: si el dueño ya lo escribió, manda él.
  void _alCambiarMatricula() {
    final f = fechaDeMatricula(_matricula.text);
    setState(() {
      if (f == null) {
        _notaMatricula = partesDeMatricula(_matricula.text) == null &&
                _matricula.text.trim().length >= 7
            ? 'No tiene el formato actual (1234 ABC). Si es anterior a 2000, '
                'pon el año a mano.'
            : null;
        return;
      }
      _notaMatricula =
          'Matriculado hacia ${mesesLargos[f.mes - 1]} de ${f.anio}, según la '
          'serie de letras. Orientativo: la fecha oficial está en la ficha técnica.';
      if (_matriculacion.text.isEmpty) _matriculacion.text = f.iso;
      if (_anio.text.isEmpty) _anio.text = '${f.anio}';
    });
  }

  List<String> _marcas(String texto) {
    final c = _catalogo;
    if (c == null) return const [];
    final t = texto.toLowerCase();
    return c.listaMarcas.where((m) => m.toLowerCase().contains(t)).take(12).toList();
  }

  List<String> _modelos(String texto) {
    final c = _catalogo;
    if (c == null) return const [];
    final t = texto.toLowerCase();
    return c.modelosDe(_marca.text).where((m) => m.toLowerCase().contains(t)).take(12).toList();
  }

  List<Motor> get _motores {
    final c = _catalogo;
    if (c == null || _marca.text.isEmpty || _modelo.text.isEmpty) return const [];
    return c.motoresDe(_marca.text, _modelo.text, anio: int.tryParse(_anio.text));
  }

  Future<void> _guardar() async {
    if (!_forma.currentState!.validate()) return;
    setState(() => _guardando = true);
    final almacen = context.almacen;
    final v = widget.editar ?? Vehiculo();
    v
      ..matricula = formatearMatricula(_matricula.text)
      ..marca = _marca.text.trim()
      ..modelo = _modelo.text.trim()
      ..anio = int.tryParse(_anio.text.trim())
      ..km = int.tryParse(_km.text.replaceAll('.', '').trim())
      ..matriculacion = _matriculacion.text.trim()
      ..combustible = _combustible
      ..adBlue = _adBlue;
    if (_bastidorLeido.isNotEmpty) {
      v.bastidorFicha = _bastidorLeido;
      if (v.bastidor.isEmpty) v.bastidor = _bastidorLeido;
    }

    if (_esEdicion) {
      final repetida = almacen.vehiculoConMatricula(v.matricula, excepto: v.id);
      if (repetida != null) {
        setState(() => _guardando = false);
        if (mounted) {
          avisar(context, 'Esa matrícula ya es de ${repetida.nombre}.');
        }
        return;
      }
      await almacen.guardarVehiculo(v);
    } else {
      final ya = almacen.vehiculoConMatricula(v.matricula);
      final guardado = await almacen.anadirVehiculo(v);
      if (ya != null && mounted) {
        avisar(context, 'Ese coche ya estaba: te llevo a ${guardado.nombre}.');
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final combustibles = _catalogo?.combustibles ??
        const ['Gasolina', 'Diésel', 'Híbrido', 'Híbrido diésel', 'Eléctrico', 'GLP'];
    final motores = _motores;
    final adblue = adBlueDeLaNorma(_combustible, int.tryParse(_anio.text));

    return Scaffold(
      appBar: AppBar(title: Text(_esEdicion ? 'Tu coche' : 'Añadir un coche')),
      body: SafeArea(
        child: Form(
          key: _forma,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (!_fichaMasTarde && (!_esEdicion || _bastidorLeido.isEmpty)) ...[
                Tarjeta(
                  color: Tono.azulFilm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined, color: Tono.azulTinta),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('¿Saber más de tu coche ahora, o más tarde?',
                                style: TextStyle(fontWeight: FontWeight.w700, color: Tono.azulTinta)),
                          ),
                          TextButton(
                            onPressed: _explicarFichaTecnica,
                            child: const Text('¿Qué es?'),
                          ),
                        ],
                      ),
                      const Text(
                        'Con una foto de la ficha técnica se rellenan solos la marca, el modelo, '
                        'la fecha, el combustible, el motor y el bastidor, y el coche queda a un '
                        'paso de «verificado». Tú revisas y guardas.',
                        style: TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _leyendoFicha ? null : () => _leerFichaTecnica(ImageSource.camera),
                              icon: _leyendoFicha
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.photo_camera_outlined),
                              label: Text(_leyendoFicha ? 'Leyendo…' : 'Hacer foto'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _leyendoFicha ? null : () => _leerFichaTecnica(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('De la galería'),
                            ),
                          ),
                        ],
                      ),
                      if (_notaFicha != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_notaFicha!,
                              style: const TextStyle(fontSize: 12, color: Tono.tinta, height: 1.4)),
                        ),
                      if (_bastidorLeido.isEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() => _fichaMasTarde = true),
                            child: const Text('Más tarde, lo relleno a mano'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              TextFormField(
                controller: _matricula,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Matrícula',
                  hintText: '1234 ABC',
                ),
                validator: (t) => (t == null || t.trim().length < 4)
                    ? 'Escribe la matrícula'
                    : null,
              ),
              if (_notaMatricula != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(_notaMatricula!,
                      style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                ),
              const SizedBox(height: 16),
              _autocompletar(
                controlador: _marca,
                foco: _focoMarca,
                etiqueta: 'Marca',
                opciones: _marcas,
                alElegir: (_) => setState(() {
                  _modelo.clear();
                }),
              ),
              const SizedBox(height: 12),
              _autocompletar(
                controlador: _modelo,
                foco: _focoModelo,
                etiqueta: 'Modelo',
                opciones: _modelos,
                alElegir: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _anio,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Año'),
                      onChanged: _alCambiarAnio,
                      validator: (t) {
                        final n = int.tryParse((t ?? '').trim());
                        if (n == null) return 'Pon el año';
                        if (n < 1950 || n > DateTime.now().year + 1) return 'Ese año no cuadra';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _km,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Kilómetros'),
                    ),
                  ),
                ],
              ),
              if (_notaAnio != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(_notaAnio!,
                      style: const TextStyle(fontSize: 12, color: Tono.naranjaTinta)),
                ),
              const SizedBox(height: 12),
              if (motores.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('motor-${_marca.text}-${_modelo.text}'),
                  initialValue: motores.any((m) => m.etiquetaLarga == _motorElegido)
                      ? _motorElegido
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Motor'),
                  items: motores
                      .map((m) => DropdownMenuItem(
                            value: m.etiquetaLarga,
                            child: Text(
                              m.detalle.isEmpty ? m.etiquetaLarga : '${m.etiquetaLarga} · ${m.detalle}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final m = motores.firstWhere((x) => x.etiquetaLarga == v);
                    setState(() {
                      _motorElegido = v;
                      _combustible = m.combustible;
                    });
                  },
                  hint: const Text('Elige la motorización'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Todas las motorizaciones vendidas en España para ese modelo, '
                  'las de tu año primero, con sus años de venta. Los cm³ ayudan a '
                  'reconocerla (1.560 cm³ es el 1.6 HDi, por ejemplo). '
                  'Combustible elegido: ${_combustible.isEmpty ? '—' : _combustible}.',
                  style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: combustibles.contains(_combustible) ? _combustible : null,
                  decoration: const InputDecoration(labelText: 'Combustible'),
                  items: combustibles
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _combustible = v ?? ''),
                  validator: (v) => (v == null || v.isEmpty) ? 'Elige el combustible' : null,
                ),
                if (_catalogo != null && _marca.text.isNotEmpty && _modelo.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'El catálogo cubre ${_catalogo!.primerAnio}–${_catalogo!.ultimoAnio}, '
                      'hasta donde llegan los datos públicos. Fuera de ahí se elige a mano.',
                      style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _matriculacion,
                decoration: const InputDecoration(
                  labelText: 'Primera matriculación (AAAA-MM)',
                  hintText: '2019-06',
                  helperText: 'Con el mes, la ITV se calcula exacta. Sin él, aproximada.',
                ),
                validator: (t) {
                  final s = (t ?? '').trim();
                  if (s.isEmpty) return null;
                  if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])(-\d{2})?$').hasMatch(s)) {
                    return 'Formato AAAA-MM';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              const TituloSeccion('AdBlue'),
              Text(
                '${adblue.texto}. ${adblue.detalle}',
                style: const TextStyle(color: Tono.tintaSuave),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('Deducir')),
                  ButtonSegment(value: 'si', label: Text('Sí')),
                  ButtonSegment(value: 'no', label: Text('No')),
                ],
                selected: {_adBlue == 'quizas' ? 'auto' : _adBlue},
                onSelectionChanged: (s) => setState(() => _adBlue = s.first),
              ),
              const SizedBox(height: 6),
              const Text(
                'Mira si hay un tapón azul junto al del combustible. «Deducir» '
                'lo saca de la normativa y no congela la deducción de hoy.',
                style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
              ),
              if (_esEdicion && widget.editar!.bastidor.isNotEmpty) ...[
                const SizedBox(height: 18),
                const TituloSeccion('Bastidor'),
                SelectableText(widget.editar!.bastidor,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
                const Text('Leído del coche por OBD.',
                    style: TextStyle(fontSize: 12, color: Tono.tintaSuave)),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: Text(_esEdicion ? 'Guardar cambios' : 'Guardar el coche'),
              ),
              if (_cargandoCatalogo)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Cargando el catálogo de marcas…',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _autocompletar({
    required TextEditingController controlador,
    required FocusNode foco,
    required String etiqueta,
    required List<String> Function(String) opciones,
    required void Function(String) alElegir,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controlador,
      focusNode: foco,
      optionsBuilder: (t) => opciones(t.text),
      onSelected: alElegir,
      fieldViewBuilder: (context, c, foco, alEnviar) => TextFormField(
        controller: c,
        focusNode: foco,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: etiqueta),
        validator: (t) => (t == null || t.trim().isEmpty) ? 'Escribe la $etiqueta' : null,
        onChanged: (_) => setState(() {}),
      ),
      optionsViewBuilder: (context, elegir, lista) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: lista
                  .map((o) => ListTile(
                        dense: true,
                        title: Text(o),
                        onTap: () => elegir(o),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}
