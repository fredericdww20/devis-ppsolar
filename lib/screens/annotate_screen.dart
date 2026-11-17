import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

/// Un élément posé sur la photo : un trait libre ou un tampon émoticône.
abstract class _Mark {}

class _Stroke extends _Mark {
  _Stroke(this.color);
  final Color color;
  final List<Offset> points = []; // coordonnées IMAGE (pixels)
}

class _Stamp extends _Mark {
  _Stamp(this.kind, this.center);
  final String kind;
  Offset center; // coordonnées IMAGE (pixels) — déplaçable au doigt
}

/// Tampons métier : identifiant + libellé. Les pictogrammes sont
/// dessinés en vectoriel par _drawStamp — nets à toutes les tailles.
const _stamps = [
  ('indoor', 'Unité intérieure'),
  ('outdoor', 'Groupe extérieur'),
  ('pump', 'Pompe de relevage'),
  ('power', 'Alimentation'),
  ('duct', 'Goulotte / liaisons'),
];

const _ink = Color(0xFF16242C);

/// Illustrations des tampons, chargées une fois depuis les assets.
final Map<String, ui.Image> _stampImages = {};

Future<void> _loadStampImages() async {
  for (final s in _stamps) {
    if (_stampImages.containsKey(s.$1)) continue;
    final data =
        await rootBundle.load('assets/stamps/stamp_${s.$1}.png');
    final codec =
        await ui.instantiateImageCodec(data.buffer.asUint8List());
    _stampImages[s.$1] = (await codec.getNextFrame()).image;
  }
}

/// Dessine l'illustration du tampon `kind`, centrée sur `c`, taille `s`.
void _drawStamp(Canvas canvas, String kind, Offset c, double s) {
  final im = _stampImages[kind];
  if (im == null) return;
  canvas.drawImageRect(
      im,
      Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
      Rect.fromCenter(center: c, width: s, height: s),
      Paint()..filterQuality = FilterQuality.high);
}

/// Dessin et tampons par-dessus une photo.
/// Pop :
///   - List<int> : octets JPEG de l'image composée,
///   - 'keep'    : validé sans aucune annotation,
///   - null      : abandon (retour arrière).
class AnnotateScreen extends StatefulWidget {
  const AnnotateScreen(
      {super.key, required this.imagePath, this.originalPath = ''});

  /// Image de départ (la version annotée si elle existe).
  final String imagePath;

  /// Photo d'origine, pour pouvoir repartir de zéro.
  final String originalPath;

  @override
  State<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends State<AnnotateScreen> {
  ui.Image? _image;
  final List<_Mark> _marks = [];
  Color _color = const Color(0xFFD63638);
  String? _activeStamp; // tampon armé ; prochain toucher = pose
  _Stamp? _dragging; // tampon en cours de déplacement
  bool _saving = false;

  static const _palette = [
    Color(0xFFD63638), // rouge
    Color(0xFFF5A623), // ambre PPSOLAR
    Color(0xFF2271B1), // bleu
    Color(0xFFFFFFFF), // blanc
  ];

  late String _basePath;

  @override
  void initState() {
    super.initState();
    _basePath = widget.imagePath;
    _loadStampImages().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(_basePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  Rect _fitRect(Size area) {
    final im = _image!;
    final scale = (area.width / im.width < area.height / im.height)
        ? area.width / im.width
        : area.height / im.height;
    final w = im.width * scale;
    final h = im.height * scale;
    return Rect.fromLTWH(
        (area.width - w) / 2, (area.height - h) / 2, w, h);
  }

  Offset? _toImage(Offset local, Size area) {
    final rect = _fitRect(area);
    if (!rect.contains(local)) return null;
    final scale = rect.width / _image!.width;
    return Offset(
        (local.dx - rect.left) / scale, (local.dy - rect.top) / scale);
  }

  double get _strokeWidthImg => _image!.width / 160;
  double get _stampSizeImg => _image!.width / 8;

  void _paintMarks(Canvas canvas, double scale, Offset origin) {
    for (final m in _marks) {
      if (m is _Stroke) {
        final paint = Paint()
          ..color = m.color
          ..strokeWidth = _strokeWidthImg * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final path = Path();
        for (var i = 0; i < m.points.length; i++) {
          final p = Offset(m.points[i].dx * scale + origin.dx,
              m.points[i].dy * scale + origin.dy);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(path, paint);
      } else if (m is _Stamp) {
        _drawStamp(
            canvas,
            m.kind,
            Offset(m.center.dx * scale + origin.dx,
                m.center.dy * scale + origin.dy),
            _stampSizeImg * scale);
      }
    }
  }

  Future<void> _save() async {
    if (_image == null || _saving) return;
    if (_marks.isEmpty) {
      Navigator.of(context).pop('keep');
      return;
    }
    setState(() => _saving = true);
    final im = _image!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(im, Offset.zero, Paint());
    _paintMarks(canvas, 1.0, Offset.zero);
    final out =
        await recorder.endRecording().toImage(im.width, im.height);
    final raw = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    final composed = img.Image.fromBytes(
      width: im.width,
      height: im.height,
      bytes: raw!.buffer,
      order: img.ChannelOrder.rgba,
    );
    final jpeg = img.encodeJpg(composed, quality: 82);
    if (!mounted) return;
    Navigator.of(context).pop(jpeg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C2B33),
      appBar: AppBar(
        title: const Text('Annoter la photo'),
        actions: [
          if (widget.originalPath.isNotEmpty &&
              widget.originalPath != widget.imagePath)
            IconButton(
              tooltip: 'Repartir de la photo d\'origine',
              onPressed: () {
                setState(() {
                  _marks.clear();
                  _basePath = widget.originalPath;
                  _image = null;
                });
                _load();
              },
              icon: const Icon(Icons.restore),
            ),
          IconButton(
            tooltip: 'Annuler le dernier élément',
            onPressed: _marks.isEmpty
                ? null
                : () => setState(() => _marks.removeLast()),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Tout effacer',
            onPressed: _marks.isEmpty
                ? null
                : () => setState(() => _marks.clear()),
            icon: const Icon(Icons.layers_clear_outlined),
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              tooltip: 'Enregistrer',
              onPressed: _save,
              icon: const Icon(Icons.check),
            ),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(builder: (ctx, constraints) {
                    final area = Size(
                        constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      onTapUp: (d) {
                        if (_activeStamp == null) return;
                        final p = _toImage(d.localPosition, area);
                        if (p == null) return;
                        setState(() {
                          _marks.add(_Stamp(_activeStamp!, p));
                          _activeStamp = null;
                        });
                      },
                      onPanStart: (d) {
                        if (_activeStamp != null) return;
                        final p = _toImage(d.localPosition, area);
                        if (p == null) return;
                        // Un doigt posé sur un tampon existant = déplacement
                        final half = _stampSizeImg / 2;
                        for (final m in _marks.reversed) {
                          if (m is _Stamp &&
                              (p - m.center).distance <= half) {
                            setState(() => _dragging = m);
                            return;
                          }
                        }
                        setState(() {
                          _marks.add(_Stroke(_color)..points.add(p));
                        });
                      },
                      onPanUpdate: (d) {
                        if (_activeStamp != null) return;
                        final p = _toImage(d.localPosition, area);
                        if (p == null) return;
                        if (_dragging != null) {
                          setState(() => _dragging!.center = p);
                          return;
                        }
                        if (_marks.isEmpty || _marks.last is! _Stroke) {
                          return;
                        }
                        setState(() =>
                            (_marks.last as _Stroke).points.add(p));
                      },
                      onPanEnd: (_) => _dragging = null,
                      onLongPressStart: (d) {
                        final p = _toImage(d.localPosition, area);
                        if (p == null) return;
                        final half = _stampSizeImg / 2;
                        for (final m in _marks.reversed) {
                          if (m is _Stamp &&
                              (p - m.center).distance <= half) {
                            setState(() => _marks.remove(m));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content:
                                        Text('Tampon supprimé'),
                                    duration:
                                        Duration(seconds: 1)));
                            return;
                          }
                        }
                      },
                      child: CustomPaint(
                        size: area,
                        painter: _AnnotPainter(
                            image: _image!,
                            fitRect: _fitRect(area),
                            paintMarks: _paintMarks),
                      ),
                    );
                  }),
                ),
                if (_activeStamp != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFF5A623),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Touche la photo pour poser : ${_stamps.firstWhere((s) => s.$1 == _activeStamp).$2}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF1C2B33),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10),
                          child: Row(children: [
                            for (final s in _stamps)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4),
                                child: ChoiceChip(
                                  avatar: Image.asset(
                                      'assets/stamps/stamp_${s.$1}.png',
                                      width: 22,
                                      height: 22),
                                  label: Text(s.$2,
                                      style: const TextStyle(
                                          fontSize: 12)),
                                  selected: _activeStamp == s.$1,
                                  onSelected: (sel) => setState(() {
                                    _activeStamp =
                                        sel ? s.$1 : null;
                                  }),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            for (final c in _palette)
                              GestureDetector(
                                onTap: () => setState(() {
                                  _color = c;
                                  _activeStamp = null;
                                }),
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 7),
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _color == c &&
                                              _activeStamp == null
                                          ? const Color(0xFFF5A623)
                                          : Colors.white24,
                                      width: _color == c &&
                                              _activeStamp == null
                                          ? 3
                                          : 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AnnotPainter extends CustomPainter {
  _AnnotPainter(
      {required this.image,
      required this.fitRect,
      required this.paintMarks});

  final ui.Image image;
  final Rect fitRect;
  final void Function(Canvas, double, Offset) paintMarks;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(
            0, 0, image.width.toDouble(), image.height.toDouble()),
        fitRect,
        Paint());
    final scale = fitRect.width / image.width;
    paintMarks(canvas, scale, fitRect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _AnnotPainter old) => true;
}
