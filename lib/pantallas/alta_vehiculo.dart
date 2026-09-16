/// DAR DE ALTA UN COCHE, o corregir uno.
///
/// El orden de los campos no es casual: la MATRÍCULA va primero porque de
/// ella sale gratis el mes de matriculación (y con él la ITV exacta), y
/// porque es lo único que el dueño sabe de memoria. Marca, modelo y motor
/// vienen del catálogo de matriculaciones reales, con autocompletar y no con
/// un desplegable: con 955 modelos un desplegable en un móvil es inservible.
///
/// LO QUE ESTA PANTALLA NO HACE: adivinar marca y modelo por la matrícula.
/// Eso solo lo da la DGT o un proveedor de pago, y una app que "deduce" el
/// modelo acierta un 60 % y da 700 € de historial al coche equivocado el
/// otro 40 %.
library;

import 'package:flutter/material.dart';

import '../datos/catalogo.dart';
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

class _PantallaAltaVehiculoState extends State<PantallaAltaVehiculo> {
  final _forma = GlobalKey<FormState>();
  late final TextEditingController _matricula;
  late final TextEditingController _marca;
  late final TextEditingController _modelo;
  late final TextEditingController _anio;
  late final TextEditingController _km;
  late final TextEditingController _matriculacion;
  String _combustible = '';
  String _adBlue = 'auto';
  Catalogo? _catalogo;
  bool _cargandoCatalogo = true;
  String? _notaMatricula;
  bool _guardando = false;

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
                etiqueta: 'Marca',
                opciones: _marcas,
                alElegir: (_) => setState(() {
                  _modelo.clear();
                }),
              ),
              const SizedBox(height: 12),
              _autocompletar(
                controlador: _modelo,
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
                      onChanged: (_) => setState(() {}),
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
              const SizedBox(height: 12),
              if (motores.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: motores.any((m) => m.etiqueta == _combustible) ? _combustible : null,
                  decoration: const InputDecoration(labelText: 'Motor'),
                  items: motores
                      .map((m) => DropdownMenuItem(
                            value: m.etiqueta,
                            child: Text(m.etiqueta, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final m = motores.firstWhere((x) => x.etiqueta == v);
                    setState(() => _combustible = m.combustible);
                  },
                  hint: const Text('Elige la motorización'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Motorizaciones vendidas en España para ese modelo. '
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
    required String etiqueta,
    required List<String> Function(String) opciones,
    required void Function(String) alElegir,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controlador,
      focusNode: FocusNode(),
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
