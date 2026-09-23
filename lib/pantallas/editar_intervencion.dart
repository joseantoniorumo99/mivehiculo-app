/// ANOTAR O CORREGIR UNA INTERVENCIÓN.
///
/// El mismo formulario para las dos cosas. Borrar va DENTRO de aquí y no en
/// cada fila del diario, donde se tocaría sin querer.
///
/// EL DESGLOSE: una factura de taller de verdad son cinco cosas —diagnosis,
/// motor de arranque, brazo de suspensión, aceite, mano de obra—, y
/// guardarla como "Revisión general · 700 €" pierde justo lo que querría ver
/// quien compre el coche. Cada línea puede llevar su tipo, y así el aviso del
/// aceite se da por atendido aunque el aceite fuese dentro de una revisión.
/// El desglose suma la BASE imponible: si no cuadra con el total se avisa de
/// que el IVA va aparte, porque si no parece un error de lectura.
///
/// LA FOTO SE COPIA a la carpeta de la app al guardar, no al elegirla: cerrar
/// el formulario no debe dejar imágenes sueltas sin dueño.
///
/// LA FOTO SE LEE: ML Kit saca el texto en el propio móvil (la factura no sale
/// de él) y `leerFactura` propone fecha, total, taller, km, tipo y desglose.
/// PROPONE, NO DECIDE: solo rellena lo que está vacío o lo que pusimos
/// nosotros por defecto (la fecha de hoy, los km del coche, el primer tipo);
/// lo que el usuario haya escrito no se toca, y nunca se guarda sola. Un
/// importe mal leído metido a la fuerza contamina el historial y no se
/// descubre hasta que vas a vender el coche.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../datos/leer_factura.dart';
import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../datos/ocr_ficha.dart';
import '../estado.dart';
import '../tema.dart';

class PantallaEditarIntervencion extends StatefulWidget {
  final Intervencion? editar;
  final String? tipoInicial;
  const PantallaEditarIntervencion({super.key, this.editar, this.tipoInicial});

  @override
  State<PantallaEditarIntervencion> createState() => _PantallaEditarIntervencionState();
}

class _LineaEnEdicion {
  final concepto = TextEditingController();
  final importe = TextEditingController();
  String tipo = '';
  _LineaEnEdicion([Linea? de]) {
    if (de != null) {
      concepto.text = de.concepto;
      importe.text = de.importe == 0 ? '' : _numero(de.importe);
      tipo = de.tipo;
    }
  }
  void soltar() {
    concepto.dispose();
    importe.dispose();
  }
}

String _numero(double n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2).replaceAll('.', ',');

double? _leerDecimal(String t) {
  final s = t.trim().replaceAll('€', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  // 1.234,56 → 1234.56 ; 1234.56 → 1234.56 ; 1234,56 → 1234.56
  final conComa = s.contains(',');
  final limpio = conComa ? s.replaceAll('.', '').replaceAll(',', '.') : s;
  return double.tryParse(limpio);
}

class _PantallaEditarIntervencionState extends State<PantallaEditarIntervencion> {
  final _forma = GlobalKey<FormState>();
  late String _tipo;
  late final TextEditingController _titulo;
  late final TextEditingController _fecha;
  late final TextEditingController _km;
  late final TextEditingController _coste;
  late final TextEditingController _taller;
  late final TextEditingController _nota;
  final List<_LineaEnEdicion> _lineas = [];
  File? _fotoNueva;
  String _fotoGuardada = '';
  bool _quitarFoto = false;
  bool _guardando = false;
  bool _leyendoFactura = false;
  String? _notaFactura;

  // Lo que pusimos NOSOTROS por defecto: solo eso puede pisar la lectura
  late final String _fechaPorDefecto;
  late final String _kmPorDefecto;
  late final String _tipoPorDefecto;

  bool get _esEdicion => widget.editar != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    final coche = context.almacen.coche;
    _tipo = e?.tipo ?? widget.tipoInicial ?? 'aceite';
    if (!tiposMantenimiento.containsKey(_tipo)) _tipo = 'otro';
    _titulo = TextEditingController(text: e?.titulo ?? '');
    _fecha = TextEditingController(text: e?.fecha ?? hoyIso());
    _km = TextEditingController(text: (e?.km ?? coche?.km)?.toString() ?? '');
    _coste = TextEditingController(text: e?.coste == null ? '' : _numero(e!.coste!));
    _taller = TextEditingController(text: e?.taller ?? '');
    _nota = TextEditingController(text: e?.nota ?? '');
    _fotoGuardada = e?.factura ?? '';
    for (final l in e?.lineas ?? const <Linea>[]) {
      _lineas.add(_LineaEnEdicion(l));
    }
    _fechaPorDefecto = _esEdicion ? '' : _fecha.text;
    _kmPorDefecto = _esEdicion ? '' : _km.text;
    _tipoPorDefecto = _esEdicion ? '' : _tipo;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _fecha.dispose();
    _km.dispose();
    _coste.dispose();
    _taller.dispose();
    _nota.dispose();
    for (final l in _lineas) {
      l.soltar();
    }
    super.dispose();
  }

  double get _sumaLineas =>
      _lineas.fold(0.0, (s, l) => s + (_leerDecimal(l.importe.text) ?? 0));

  Future<void> _elegirFecha() async {
    final actual = DateTime.tryParse(_fecha.text) ?? DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      locale: const Locale('es'),
    );
    if (f != null) setState(() => _fecha.text = hoyIso(f));
  }

  Future<void> _elegirFoto(ImageSource de) async {
    XFile? x;
    try {
      // 2.000 px: al OCR le cuesta con menos, y la foto se guarda tal cual
      x = await ImagePicker().pickImage(source: de, maxWidth: 2000, imageQuality: 88);
    } catch (e) {
      if (mounted) avisar(context, 'No se ha podido coger la foto: $e');
      return;
    }
    if (x == null || !mounted) return;
    setState(() {
      _fotoNueva = File(x!.path);
      _quitarFoto = false;
      _notaFactura = null;
    });
    await _leerFactura(x.path);
  }

  /// Lee la foto y RELLENA LOS HUECOS. Al corregir una anotación ya escrita,
  /// fecha, km y tipo son del usuario y no se tocan: solo el total, el
  /// taller y el desglose si estaban vacíos.
  Future<void> _leerFactura(String ruta) async {
    setState(() => _leyendoFactura = true);
    LecturaFactura r;
    try {
      final texto = await textoDeLaFoto(ruta);
      r = leerFactura(texto);
    } catch (e) {
      r = const LecturaFactura.fallo('No se ha podido leer la foto. Puedes rellenar los datos a mano.');
    }
    if (!mounted) return;
    final d = r.datos;
    if (d == null || !d.hayAlgo) {
      setState(() {
        _leyendoFactura = false;
        _notaFactura = r.error ??
            'No se ha leído nada claro. Prueba con más luz, la factura plana y sin sombras; o rellénalo a mano.';
      });
      return;
    }
    final rellenado = <String>[];
    setState(() {
      _leyendoFactura = false;
      if (d.fecha != null && _fechaPorDefecto.isNotEmpty && _fecha.text == _fechaPorDefecto) {
        _fecha.text = d.fecha!;
        rellenado.add('fecha');
      }
      if (d.importe != null && _coste.text.trim().isEmpty) {
        _coste.text = _numero(d.importe!);
        rellenado.add('total');
      }
      if (d.taller != null && _taller.text.trim().isEmpty) {
        _taller.text = d.taller!;
        rellenado.add('taller');
      }
      if (d.km != null && _kmPorDefecto.isNotEmpty && _km.text == _kmPorDefecto) {
        _km.text = d.km.toString();
        rellenado.add('km');
      }
      if (d.tipo != null &&
          tiposMantenimiento.containsKey(d.tipo) &&
          _tipoPorDefecto.isNotEmpty &&
          _tipo == _tipoPorDefecto) {
        _tipo = d.tipo!;
        rellenado.add('qué se hizo');
      }
      if (d.lineas.isNotEmpty && _lineas.isEmpty) {
        for (final l in d.lineas) {
          _lineas.add(_LineaEnEdicion(Linea(concepto: l.concepto, importe: l.importe, tipo: l.tipo)));
        }
        rellenado.add('desglose (${d.lineas.length} líneas)');
      }
      if (rellenado.isEmpty) {
        _notaFactura = 'La factura se ha leído, pero los campos ya estaban rellenos y no se ha tocado nada.';
      } else {
        _notaFactura = 'Leído de la factura: ${rellenado.join(', ')}. Revísalo antes de guardar'
            '${d.iva == 'sin' ? '; el desglose suma la base y el IVA va aparte' : ''}.';
      }
    });
  }

  Future<void> _guardar() async {
    if (!_forma.currentState!.validate()) return;
    final almacen = context.almacen;
    final coche = almacen.coche;
    if (coche == null) return;
    setState(() => _guardando = true);

    final i = widget.editar ??
        Intervencion(vehiculoId: coche.id, fecha: _fecha.text.trim());
    i
      ..fecha = _fecha.text.trim()
      ..tipo = _tipo
      ..titulo = _titulo.text.trim()
      ..km = int.tryParse(_km.text.replaceAll('.', '').trim())
      ..coste = _leerDecimal(_coste.text)
      ..taller = _taller.text.trim()
      ..nota = _nota.text.trim()
      ..lineas = _lineas
          .where((l) => l.concepto.text.trim().isNotEmpty || _leerDecimal(l.importe.text) != null)
          .map((l) => Linea(
                concepto: l.concepto.text.trim(),
                importe: _leerDecimal(l.importe.text) ?? 0,
                tipo: l.tipo,
              ))
          .toList();

    if (_quitarFoto) {
      i.factura = '';
    } else if (_fotoNueva != null) {
      i.factura = await almacen.adjuntarFactura(_fotoNueva!);
    }

    await almacen.guardarIntervencion(i);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _borrar() async {
    final ok = await confirmar(
      context,
      titulo: 'Borrar esta anotación',
      texto: 'Se borra del diario, con su foto si la tenía. No se puede deshacer.',
    );
    if (!ok || !mounted) return;
    await context.almacen.borrarIntervencion(widget.editar!.id);
    if (mounted) {
      Navigator.pop(context); // el formulario
      Navigator.maybePop(context); // la ficha, si venía de ella
    }
  }

  @override
  Widget build(BuildContext context) {
    final coste = _leerDecimal(_coste.text);
    final suma = _sumaLineas;
    final conLineas = _lineas.isNotEmpty && suma > 0;
    final noCuadra = conLineas && coste != null && (coste - suma).abs() > 0.5;
    final ivaCuadra = noCuadra && ((suma * 1.21) - coste).abs() < 1;
    final fotoActual = _fotoNueva ??
        (!_quitarFoto && _fotoGuardada.isNotEmpty
            ? context.almacen.ficheroFactura(_fotoGuardada)
            : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Corregir' : 'Anotar'),
        actions: [
          if (_esEdicion)
            IconButton(
              tooltip: 'Borrar',
              onPressed: _borrar,
              icon: const Icon(Icons.delete_outline, color: Tono.rojoTinta),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _forma,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Qué se hizo'),
                items: tiposMantenimiento.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v ?? 'otro'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titulo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Título (opcional)',
                  hintText: 'Cambio de aceite y filtros · Golpe en el paragolpes…',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fecha,
                      readOnly: true,
                      onTap: _elegirFecha,
                      decoration: const InputDecoration(
                        labelText: 'Fecha',
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      validator: (t) =>
                          DateTime.tryParse(t ?? '') == null ? 'Elige la fecha' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _km,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Km del coche'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _coste,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Total (€)', hintText: '0'),
                      onChanged: (_) => setState(() {}),
                      validator: (t) => (t != null && t.trim().isNotEmpty && _leerDecimal(t) == null)
                          ? 'Un número, con coma o punto'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _taller,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Taller (opcional)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TituloSeccion(
                'Desglose de la factura',
                accion: TextButton.icon(
                  onPressed: () => setState(() => _lineas.add(_LineaEnEdicion())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Línea'),
                ),
              ),
              if (_lineas.isEmpty)
                const Text(
                  'Opcional. Si la factura trae varios conceptos, anótalos uno a uno: '
                  'es lo que verá quien compre el coche, y lo que hace que el aviso '
                  'del aceite se dé por hecho aunque fuera dentro de una revisión.',
                  style: TextStyle(color: Tono.tintaSuave, fontSize: 13, height: 1.4),
                ),
              ..._lineas.asMap().entries.map((e) => _linea(e.key, e.value)),
              if (conLineas)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Suma del desglose: ${enEuros(suma)}'
                    '${noCuadra ? (ivaCuadra ? ' · con IVA ${enEuros(suma * 1.21)}: cuadra, el IVA va aparte' : ' · no cuadra con el total') : ''}',
                    style: TextStyle(
                        fontSize: 13,
                        color: noCuadra && !ivaCuadra ? Tono.naranjaTinta : Tono.tintaSuave),
                  ),
                ),
              const SizedBox(height: 18),
              const TituloSeccion('Factura'),
              if (fotoActual != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(fotoActual, height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _leyendoFactura ? null : () => _leerFactura(fotoActual.path),
                      icon: const Icon(Icons.document_scanner_outlined, size: 18),
                      label: const Text('Leer los datos'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _fotoNueva = null;
                        _quitarFoto = true;
                        _notaFactura = null;
                      }),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Quitar la foto'),
                    ),
                  ],
                ),
                if (_leyendoFactura)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Leyendo la factura…', style: TextStyle(color: Tono.tintaSuave)),
                      ],
                    ),
                  )
                else if (_notaFactura != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Recuadro(
                      _notaFactura!,
                      tono: _notaFactura!.startsWith('Leído') ? TonoEstado.calma : TonoEstado.neutro,
                    ),
                  ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _elegirFoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Hacer foto'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _elegirFoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('De la galería'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              const Text(
                'La factura se lee en el propio móvil y rellena lo que esté vacío: '
                'fecha, total, taller, kilómetros y desglose. La foto no sale del '
                'móvil salvo a tu cuenta, si la tienes.',
                style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nota,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  hintText: 'Marca del aceite, qué dijo el mecánico, lo que quieras recordar',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: Text(_esEdicion ? 'Guardar cambios' : 'Guardar en el diario'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linea(int i, _LineaEnEdicion l) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: l.concepto,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Concepto', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: l.importe,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '€ (base)', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar línea',
                  onPressed: () => setState(() {
                    _lineas.removeAt(i).soltar();
                  }),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: l.tipo.isEmpty ? '' : l.tipo,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Cuenta como…', isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('Nada en concreto (mano de obra, etc.)')),
                ...tiposMantenimiento.entries
                    .where((e) => e.key != 'otro' && e.key != 'revision')
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() => l.tipo = v ?? ''),
            ),
          ],
        ),
      );
}
