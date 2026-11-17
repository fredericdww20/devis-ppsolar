import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../api/client.dart';

/// Une pièce du dossier technique, telle que stockée sur la tablette.
class DossierPiece {
  DossierPiece({
    this.localId = 0,
    this.serverId = 0,
    required this.quoteId,
    required this.uid,
    this.kind = 'photo',
    this.phase = 'visite',
    this.caption = '',
    this.origPath = '',
    this.annotPath = '',
    this.remoteFileUrl = '',
    this.remoteAnnotUrl = '',
    this.createdAt = '',
    this.serverUpdated = '',
    this.synced = false,
    this.dirty = true,
    this.deleted = false,
  });

  int localId;
  int serverId;
  final int quoteId;
  final String uid;
  final String kind; // photo | note
  final String phase; // visite | chantier
  String caption;
  String origPath;
  String annotPath;
  String remoteFileUrl;
  String remoteAnnotUrl;
  String createdAt;
  String serverUpdated;
  bool synced;
  bool dirty;
  bool deleted;

  bool get isPhoto => kind == 'photo';

  /// La photo existe-t-elle en local (annotable) ?
  bool get hasLocalFile => origPath.isNotEmpty && File(origPath).existsSync();

  factory DossierPiece.fromRow(Map<String, dynamic> r) => DossierPiece(
        localId: r['id'] as int,
        serverId: (r['server_id'] as int?) ?? 0,
        quoteId: r['quote_id'] as int,
        uid: (r['uid'] as String?) ?? '',
        kind: (r['kind'] as String?) ?? 'photo',
        phase: (r['phase'] as String?) ?? 'visite',
        caption: (r['caption'] as String?) ?? '',
        origPath: (r['orig_path'] as String?) ?? '',
        annotPath: (r['annot_path'] as String?) ?? '',
        remoteFileUrl: (r['remote_file_url'] as String?) ?? '',
        remoteAnnotUrl: (r['remote_annot_url'] as String?) ?? '',
        createdAt: (r['created_at'] as String?) ?? '',
        serverUpdated: (r['server_updated'] as String?) ?? '',
        synced: ((r['synced'] as int?) ?? 0) == 1,
        dirty: ((r['dirty'] as int?) ?? 0) == 1,
        deleted: ((r['deleted'] as int?) ?? 0) == 1,
      );

  Map<String, dynamic> toRow() => {
        'server_id': serverId,
        'quote_id': quoteId,
        'uid': uid,
        'kind': kind,
        'phase': phase,
        'caption': caption,
        'orig_path': origPath,
        'annot_path': annotPath,
        'remote_file_url': remoteFileUrl,
        'remote_annot_url': remoteAnnotUrl,
        'created_at': createdAt,
        'server_updated': serverUpdated,
        'synced': synced ? 1 : 0,
        'dirty': dirty ? 1 : 0,
        'deleted': deleted ? 1 : 0,
      };
}

/// Stockage hors-ligne du dossier technique + synchronisation vers le site.
class DossierStore {
  DossierStore._();
  static final DossierStore instance = DossierStore._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/dossier.db',
      version: 3,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE pieces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER DEFAULT 0,
            quote_id INTEGER NOT NULL,
            uid TEXT UNIQUE,
            kind TEXT NOT NULL DEFAULT 'photo',
            phase TEXT NOT NULL DEFAULT 'visite',
            caption TEXT DEFAULT '',
            orig_path TEXT DEFAULT '',
            annot_path TEXT DEFAULT '',
            remote_file_url TEXT DEFAULT '',
            remote_annot_url TEXT DEFAULT '',
            created_at TEXT DEFAULT '',
            server_updated TEXT DEFAULT '',
            synced INTEGER DEFAULT 0,
            dirty INTEGER DEFAULT 1,
            deleted INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute(
              "ALTER TABLE pieces ADD COLUMN server_updated TEXT DEFAULT ''");
        }
        if (oldV < 3) {
          await d.execute(
              "ALTER TABLE pieces ADD COLUMN phase TEXT NOT NULL DEFAULT 'visite'");
        }
      },
    );
    return _db!;
  }

  String newUid() {
    final rnd = Random().nextInt(0xFFFFFF).toRadixString(16);
    return 'tab-${DateTime.now().microsecondsSinceEpoch}-$rnd';
  }

  /// Dossier des fichiers d'un devis sur la tablette.
  Future<Directory> filesDir(int quoteId) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/dossiers/$quoteId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<DossierPiece>> list(int quoteId) async {
    final d = await db;
    final rows = await d.query('pieces',
        where: 'quote_id = ? AND deleted = 0',
        whereArgs: [quoteId],
        orderBy: 'id ASC');
    return rows.map(DossierPiece.fromRow).toList();
  }

  Future<int> pendingCount(int quoteId) async {
    final d = await db;
    final rows = await d.rawQuery(
        'SELECT COUNT(*) c FROM pieces WHERE quote_id = ? AND dirty = 1',
        [quoteId]);
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<DossierPiece> insert(DossierPiece p) async {
    final d = await db;
    p.localId = await d.insert('pieces', p.toRow());
    return p;
  }

  Future<void> save(DossierPiece p) async {
    final d = await db;
    await d.update('pieces', p.toRow(), where: 'id = ?', whereArgs: [p.localId]);
  }

  /// Suppression : immédiate si jamais synchronisée, sinon marquée
  /// pour suppression serveur au prochain passage réseau.
  Future<void> remove(DossierPiece p) async {
    final d = await db;
    for (final path in [p.origPath, p.annotPath]) {
      if (path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }
    if (p.serverId == 0) {
      await d.delete('pieces', where: 'id = ?', whereArgs: [p.localId]);
    } else {
      await d.update('pieces', {'deleted': 1, 'dirty': 1},
          where: 'id = ?', whereArgs: [p.localId]);
    }
  }

  Future<String> _b64(String path) async =>
      base64Encode(await File(path).readAsBytes());

  /// Pousse tout ce qui attend, puis rapatrie l'état serveur.
  /// Renvoie null si tout s'est bien passé, sinon un message court.
  Future<String?> sync(int quoteId) async {
    final d = await db;
    try {
      final rows = await d.query('pieces',
          where: 'quote_id = ? AND dirty = 1', whereArgs: [quoteId]);

      for (final r in rows) {
        final p = DossierPiece.fromRow(r);

        if (p.deleted) {
          await ApiClient.instance
              .delete('/quotes/$quoteId/attachments/${p.serverId}');
          await d.delete('pieces', where: 'id = ?', whereArgs: [p.localId]);
          continue;
        }

        if (p.serverId == 0) {
          final body = <String, dynamic>{
            'kind': p.kind,
            'phase': p.phase,
            'caption': p.caption,
            'client_uid': p.uid,
          };
          if (p.isPhoto && p.hasLocalFile) {
            body['image_base64'] = await _b64(p.origPath);
            if (p.annotPath.isNotEmpty && File(p.annotPath).existsSync()) {
              body['annotated_base64'] = await _b64(p.annotPath);
            }
          }
          final res = await ApiClient.instance
              .post('/quotes/$quoteId/attachments', body);
          final m = res as Map<String, dynamic>;
          p.serverId = (m['id'] as num?)?.toInt() ?? 0;
          p.remoteFileUrl = (m['file_url'] ?? '').toString();
          p.remoteAnnotUrl = (m['annotated_url'] ?? '').toString();
          p.serverUpdated = (m['updated_at'] ?? '').toString();
        } else {
          final body = <String, dynamic>{'caption': p.caption};
          if (p.annotPath.isNotEmpty && File(p.annotPath).existsSync()) {
            body['annotated_base64'] = await _b64(p.annotPath);
          }
          final res = await ApiClient.instance
              .post('/quotes/$quoteId/attachments/${p.serverId}', body);
          final m = res as Map<String, dynamic>;
          p.remoteAnnotUrl = (m['annotated_url'] ?? '').toString();
          p.serverUpdated = (m['updated_at'] ?? '').toString();
        }
        p.synced = true;
        p.dirty = false;
        await save(p);
      }

      // Rapatrier : pièces créées ailleurs (admin WordPress) et suppressions serveur.
      final res =
          await ApiClient.instance.get('/quotes/$quoteId/attachments');
      final serverList = (((res as Map<String, dynamic>)['attachments']
                  as List?) ??
              [])
          .cast<Map<String, dynamic>>();
      final serverIds = <int>{};
      for (final s in serverList) {
        final sid = (s['id'] as num?)?.toInt() ?? 0;
        serverIds.add(sid);
        final uid = (s['client_uid'] ?? '').toString();
        final local = await d.query('pieces',
            where: 'quote_id = ? AND (server_id = ? OR (uid != \'\' AND uid = ?))',
            whereArgs: [quoteId, sid, uid]);
        final sUpdated = (s['updated_at'] ?? '').toString();
        if (local.isEmpty) {
          await d.insert('pieces', {
            'server_id': sid,
            'quote_id': quoteId,
            'uid': uid.isEmpty ? newUid() : uid,
            'kind': (s['kind'] ?? 'photo').toString(),
            'phase': (s['phase'] ?? 'visite').toString(),
            'caption': (s['caption'] ?? '').toString(),
            'remote_file_url': (s['file_url'] ?? '').toString(),
            'remote_annot_url': (s['annotated_url'] ?? '').toString(),
            'created_at': (s['created_at'] ?? '').toString(),
            'server_updated': sUpdated,
            'synced': 1,
            'dirty': 0,
          });
        } else {
          final lp = DossierPiece.fromRow(local.first);
          // La tablette a des changements non envoyés : elle gagne,
          // ils partiront au prochain passage.
          if (lp.dirty) continue;
          if (lp.serverUpdated != sUpdated ||
              lp.remoteAnnotUrl !=
                  (s['annotated_url'] ?? '').toString()) {
            // Modifié ailleurs (ordinateur) : adopter la version du site.
            // Le dessin local périmé sera retéléchargé au prochain
            // affichage ou dessin.
            if (lp.annotPath.isNotEmpty) {
              final f = File(lp.annotPath);
              if (await f.exists()) await f.delete();
            }
            await d.update(
                'pieces',
                {
                  'server_id': sid,
                  'phase': (s['phase'] ?? 'visite').toString(),
                  'caption': (s['caption'] ?? '').toString(),
                  'remote_file_url': (s['file_url'] ?? '').toString(),
                  'remote_annot_url':
                      (s['annotated_url'] ?? '').toString(),
                  'annot_path': '',
                  'server_updated': sUpdated,
                  'synced': 1,
                  'dirty': 0,
                },
                where: 'id = ?',
                whereArgs: [lp.localId]);
          }
        }
      }
      // Supprimées côté serveur → retirer les copies locales propres.
      final syncedLocal = await d.query('pieces',
          where: 'quote_id = ? AND server_id > 0 AND dirty = 0',
          whereArgs: [quoteId]);
      for (final r in syncedLocal) {
        final sid = (r['server_id'] as int?) ?? 0;
        if (!serverIds.contains(sid)) {
          final p = DossierPiece.fromRow(r);
          for (final path in [p.origPath, p.annotPath]) {
            if (path.isNotEmpty) {
              final f = File(path);
              if (await f.exists()) await f.delete();
            }
          }
          await d.delete('pieces', where: 'id = ?', whereArgs: [p.localId]);
        }
      }
      return null;
    } on ApiException catch (e) {
      // Le serveur a répondu : erreur réelle, pas un problème de réseau.
      return 'Synchro refusée par le site : ${e.message}';
    } catch (e) {
      final msg = e.toString();
      final offline = msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Connection') ||
          msg.contains('TimeoutException');
      return offline
          ? 'Hors-ligne — sera synchronisé plus tard'
          : 'Échec de synchro : $msg';
    }
  }
}
