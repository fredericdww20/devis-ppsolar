import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/dossier_store.dart';
import 'annotate_screen.dart';

/// Dossier technique d'un devis : photos de visite annotées et notes.
/// Tout s'enregistre d'abord sur la tablette ; la synchronisation vers
/// le site se fait dès que le réseau répond.
class DossierScreen extends StatefulWidget {
  const DossierScreen(
      {super.key, required this.quoteId, required this.quoteNumber});

  final int quoteId;
  final String quoteNumber;

  @override
  State<DossierScreen> createState() => _DossierScreenState();
}

class _DossierScreenState extends State<DossierScreen> {
  final _store = DossierStore.instance;
  final _picker = ImagePicker();
  List<DossierPiece> _pieces = [];
  int _pending = 0;
  bool _syncing = false;
  Timer? _autoSync;
  String _phase = 'visite'; // onglet courant : visite | chantier

  @override
  void initState() {
    super.initState();
    _refresh();
    _sync(silent: true);
    // Tant que le dossier est ouvert, on regarde le site régulièrement :
    // un dessin fait sur l'ordinateur apparaît sans rien toucher.
    _autoSync = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_syncing) _sync(silent: true);
    });
  }

  @override
  void dispose() {
    _autoSync?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await _store.list(widget.quoteId);
    final pending = await _store.pendingCount(widget.quoteId);
    if (!mounted) return;
    setState(() {
      _pieces = list;
      _pending = pending;
    });
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final err = await _store.sync(widget.quoteId);
    if (!mounted) return;
    setState(() => _syncing = false);
    await _refresh();
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? 'Dossier synchronisé'),
          backgroundColor:
              err == null ? const Color(0xFF1A7F37) : const Color(0xFF8A6D3B)));
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    final XFile? shot = await _picker.pickImage(
        source: source, maxWidth: 1600, imageQuality: 85);
    if (shot == null) return;
    final dir = await _store.filesDir(widget.quoteId);
    final uid = _store.newUid();
    final dest = '${dir.path}/orig-$uid.jpg';
    await File(shot.path).copy(dest);

    // La photo n'est enregistrée au dossier qu'après l'écran de dessin.
    if (!mounted) return;
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
          builder: (_) =>
              AnnotateScreen(imagePath: dest, originalPath: dest)),
    );

    String annotPath = '';
    if (result is List<int>) {
      annotPath = '${dir.path}/annot-$uid.jpg';
      await File(annotPath).writeAsBytes(result);
    } else if (result == null) {
      // Retour arrière : garder quand même ou abandonner ?
      if (!mounted) return;
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Garder la photo ?'),
          content: const Text(
              'Tu es revenu sans enregistrer. Ajouter quand même la photo au dossier, sans annotation ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abandonner')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Garder')),
          ],
        ),
      );
      if (keep != true) {
        final f = File(dest);
        if (await f.exists()) await f.delete();
        return;
      }
    }
    // result == 'keep' : validé sans annotation → photo seule.

    final piece = DossierPiece(
      quoteId: widget.quoteId,
      uid: uid,
      kind: 'photo',
      phase: _phase,
      origPath: dest,
      annotPath: annotPath,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _store.insert(piece);
    await _refresh();
    _sync(silent: true);
  }

  Future<void> _addNote() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note de visite'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: 'Ex. : prévoir goulotte sur pignon est…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Ajouter')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await _store.insert(DossierPiece(
      quoteId: widget.quoteId,
      uid: _store.newUid(),
      kind: 'note',
      phase: _phase,
      caption: text,
      createdAt: DateTime.now().toIso8601String(),
    ));
    await _refresh();
    _sync(silent: true);
  }

  Future<void> _editCaption(DossierPiece p) async {
    final ctrl = TextEditingController(text: p.caption);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.isPhoto ? 'Légende de la photo' : 'Note'),
        content: TextField(
            controller: ctrl, autofocus: true, maxLines: 4),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (text == null) return;
    p.caption = text;
    p.dirty = true;
    await _store.save(p);
    await _refresh();
    _sync(silent: true);
  }

  Future<void> _annotate(DossierPiece p) async {
    // Photo venue du site (ajoutée depuis l'ordinateur) : rapatrier
    // l'original en local au premier dessin.
    if (!p.hasLocalFile && p.remoteFileUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(p.remoteFileUrl));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        final dir = await _store.filesDir(widget.quoteId);
        final dest = '${dir.path}/orig-${p.uid}.jpg';
        await File(dest).writeAsBytes(resp.bodyBytes);
        p.origPath = dest;
        await _store.save(p);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Photo introuvable hors-ligne — réessaie avec du réseau ($e)')));
        }
        return;
      }
    }
    if (!p.hasLocalFile) return;
    // Le dessin le plus récent vient peut-être de l'ordinateur :
    // le rapatrier pour dessiner par-dessus, pas à côté.
    if ((p.annotPath.isEmpty || !File(p.annotPath).existsSync()) &&
        p.remoteAnnotUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(p.remoteAnnotUrl));
        if (resp.statusCode == 200) {
          final dir = await _store.filesDir(widget.quoteId);
          final dest = '${dir.path}/annot-${p.uid}.jpg';
          await File(dest).writeAsBytes(resp.bodyBytes);
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          p.annotPath = dest; // copie du dessin du site — rien à renvoyer
          await _store.save(p);
        }
      } catch (_) {}
    }
    final hasAnnot =
        p.annotPath.isNotEmpty && File(p.annotPath).existsSync();
    final png = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
          builder: (_) => AnnotateScreen(
              imagePath: hasAnnot ? p.annotPath : p.origPath,
              originalPath: p.origPath)),
    );
    if (png == null || png == 'keep') return;
    final dir = await _store.filesDir(widget.quoteId);
    final dest = '${dir.path}/annot-${p.uid}.jpg';
    if (p.annotPath.isNotEmpty && p.annotPath != dest) {
      final old = File(p.annotPath);
      if (await old.exists()) await old.delete();
    }
    await File(dest).writeAsBytes(png as List<int>);
    // Le fichier garde le même nom : vider le cache d'images pour que
    // la miniature et le plein écran montrent la nouvelle version.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    p.annotPath = dest;
    p.dirty = true;
    await _store.save(p);
    await _refresh();
    _sync(silent: true);
  }

  void _viewPhoto(DossierPiece p) {
    final photos = _pieces
        .where((e) =>
            e.isPhoto &&
            e.phase == _phase &&
            (e.hasLocalFile ||
                e.remoteFileUrl.isNotEmpty ||
                e.remoteAnnotUrl.isNotEmpty ||
                (e.annotPath.isNotEmpty &&
                    File(e.annotPath).existsSync())))
        .toList();
    final start = photos.indexWhere((e) => e.localId == p.localId);
    if (photos.length > 1 && start >= 0) {
      _viewGallery(photos, start);
      return;
    }
    _viewSingle(p);
  }

  Widget _fullImage(DossierPiece p) {
    final localAnnot =
        p.annotPath.isNotEmpty && File(p.annotPath).existsSync();
    if (localAnnot) return Image.file(File(p.annotPath));
    if (p.remoteAnnotUrl.isNotEmpty) {
      return Image.network(p.remoteAnnotUrl,
          errorBuilder: (_, __, ___) => p.hasLocalFile
              ? Image.file(File(p.origPath))
              : const Icon(Icons.cloud_off_outlined,
                  color: Colors.white54, size: 48));
    }
    if (p.hasLocalFile) return Image.file(File(p.origPath));
    return Image.network(p.remoteFileUrl,
        errorBuilder: (_, __, ___) => const Icon(
            Icons.cloud_off_outlined,
            color: Colors.white54,
            size: 48));
  }

  void _viewGallery(List<DossierPiece> photos, int start) {
    var index = start;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StatefulBuilder(builder: (ctx, setView) {
        final p = photos[index];
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(
                '${index + 1}/${photos.length}${p.caption.isEmpty ? '' : ' — ${p.caption}'}',
                style: const TextStyle(fontSize: 15)),
            actions: [
              if (p.hasLocalFile || p.remoteFileUrl.isNotEmpty)
                IconButton(
                  tooltip: 'Dessiner',
                  icon: const Icon(Icons.draw_outlined),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _annotate(p);
                  },
                ),
            ],
          ),
          body: PageView.builder(
            controller: PageController(initialPage: start),
            itemCount: photos.length,
            onPageChanged: (i) => setView(() => index = i),
            itemBuilder: (_, i) => Center(
              child: InteractiveViewer(
                  maxScale: 6, child: _fullImage(photos[i])),
            ),
          ),
        );
      }),
    ));
  }

  void _viewSingle(DossierPiece p) {
    // Même priorité que la miniature : le dessin avant la photo brute.
    final localAnnot =
        p.annotPath.isNotEmpty && File(p.annotPath).existsSync();
    final localPath = localAnnot
        ? p.annotPath
        : (p.remoteAnnotUrl.isEmpty && p.hasLocalFile ? p.origPath : '');
    final url = p.remoteAnnotUrl.isNotEmpty
        ? p.remoteAnnotUrl
        : p.remoteFileUrl;
    if (localPath.isEmpty && url.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(p.caption.isEmpty ? 'Photo' : p.caption,
              style: const TextStyle(fontSize: 15)),
          actions: [
            if (p.hasLocalFile || p.remoteFileUrl.isNotEmpty)
              IconButton(
                tooltip: 'Dessiner',
                icon: const Icon(Icons.draw_outlined),
                onPressed: () {
                  Navigator.of(context).pop();
                  _annotate(p);
                },
              ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(maxScale: 6, child: _fullImage(p)),
        ),
      ),
    ));
  }

  Future<void> _delete(DossierPiece p) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette pièce ?'),
        content: Text(p.isPhoto
            ? 'La photo et son annotation seront supprimées, ici et sur le site.'
            : 'La note sera supprimée, ici et sur le site.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (go != true) return;
    await _store.remove(p);
    await _refresh();
    _sync(silent: true);
  }

  void _addMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Ajouter une note'),
              onTap: () {
                Navigator.pop(ctx);
                _addNote();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(DossierPiece p) {
    // Priorité au DESSIN, local ou site, avant la photo brute.
    final localAnnot =
        p.annotPath.isNotEmpty && File(p.annotPath).existsSync();
    if (localAnnot) {
      return Image.file(File(p.annotPath),
          width: 92, height: 92, cacheWidth: 200, fit: BoxFit.cover);
    }
    if (p.remoteAnnotUrl.isNotEmpty) {
      return Image.network(p.remoteAnnotUrl,
          width: 92,
          height: 92,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => p.hasLocalFile
              ? Image.file(File(p.origPath),
                  width: 92,
                  height: 92,
                  cacheWidth: 200,
                  fit: BoxFit.cover)
              : const SizedBox(
                  width: 92,
                  height: 92,
                  child: Icon(Icons.cloud_off_outlined)));
    }
    if (p.hasLocalFile) {
      return Image.file(File(p.origPath),
          width: 92, height: 92, cacheWidth: 200, fit: BoxFit.cover);
    }
    final url = p.remoteFileUrl;
    if (url.isNotEmpty) {
      return Image.network(url,
          width: 92,
          height: 92,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
              width: 92,
              height: 92,
              child: Icon(Icons.cloud_off_outlined)));
    }
    return const SizedBox(
        width: 92, height: 92, child: Icon(Icons.image_outlined));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dossier — ${widget.quoteNumber}'),
        actions: [
          if (_syncing)
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
              tooltip: _pending == 0
                  ? 'Tout est synchronisé'
                  : '$_pending en attente — synchroniser',
              onPressed: () => _sync(),
              icon: Badge(
                isLabelVisible: _pending > 0,
                label: Text('$_pending'),
                child: Icon(_pending == 0
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMenu,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Ajouter'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
            for (final ph in const [
              ('visite', '🔍 Visite technique'),
              ('chantier', '🏁 Fin de chantier'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                      '${ph.$2} (${_pieces.where((e) => e.phase == ph.$1).length})'),
                  selected: _phase == ph.$1,
                  onSelected: (_) => setState(() => _phase = ph.$1),
                ),
              ),
          ]),
        ),
        Expanded(child: _buildList()),
      ]),
    );
  }

  Widget _buildList() {
    final pieces =
        _pieces.where((e) => e.phase == _phase).toList();
    return pieces.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucune pièce dans cet onglet.\n\nLes photos et notes que tu ajoutes vont dans l\'onglet ouvert — visite technique ou fin de chantier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: pieces.length,
              itemBuilder: (ctx, i) {
                final p = pieces[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.isPhoto)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: GestureDetector(
                                onTap: () => _viewPhoto(p),
                                child: _thumb(p)),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.sticky_note_2_outlined,
                                size: 40, color: Color(0xFF33454F)),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _editCaption(p),
                                child: Text(
                                  p.caption.isEmpty
                                      ? (p.isPhoto
                                          ? 'Ajouter une légende…'
                                          : '')
                                      : p.caption,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      color: p.caption.isEmpty
                                          ? Colors.black38
                                          : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(children: [
                                Icon(
                                  p.dirty
                                      ? Icons.cloud_upload_outlined
                                      : Icons.cloud_done_outlined,
                                  size: 15,
                                  color: p.dirty
                                      ? const Color(0xFFB36B00)
                                      : const Color(0xFF1A7F37),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  p.dirty
                                      ? 'En attente de synchro'
                                      : 'Synchronisé',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black45),
                                ),
                                if (p.isPhoto &&
                                    (p.hasLocalFile ||
                                        p.remoteFileUrl
                                            .isNotEmpty)) ...[
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 28)),
                                    onPressed: () => _annotate(p),
                                    icon: const Icon(Icons.draw_outlined,
                                        size: 16),
                                    label: const Text('Dessiner',
                                        style:
                                            TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ]),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _delete(p),
                          icon: const Icon(Icons.close, size: 20),
                          color: const Color(0xFFB32D2E),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
  }
}
