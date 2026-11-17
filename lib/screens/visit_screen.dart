import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/models.dart';

/// Fiche de visite technique (devis PPCLIM) — relevés faits sur place,
/// enregistrés avec le devis (champ visit_data), jamais visibles du client.
class VisitScreen extends StatefulWidget {
  const VisitScreen({super.key, required this.quote});

  final Quote quote;

  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitRoom {
  _VisitRoom(Map<String, dynamic> j)
      : name = TextEditingController(text: (j['name'] ?? '').toString()),
        area = TextEditingController(text: (j['area'] ?? '').toString()),
        frigo = TextEditingController(text: (j['frigo'] ?? '').toString()),
        elec = TextEditingController(text: (j['elec'] ?? '').toString()),
        drop = TextEditingController(text: (j['drop'] ?? '').toString()),
        notes = TextEditingController(text: (j['notes'] ?? '').toString()),
        pump = j['pump'] == true || j['pump'] == 1 || j['pump'] == '1',
        trunk = j['trunk'] == true || j['trunk'] == 1 || j['trunk'] == '1';

  final TextEditingController name;
  final TextEditingController area;
  final TextEditingController frigo;
  final TextEditingController elec;
  final TextEditingController drop;
  final TextEditingController notes;
  bool pump;
  bool trunk;

  Map<String, dynamic> toJson() => {
        'name': name.text,
        'area': area.text,
        'frigo': frigo.text,
        'elec': elec.text,
        'drop': drop.text,
        'pump': pump ? 1 : 0,
        'trunk': trunk ? 1 : 0,
        'notes': notes.text,
      };

  void dispose() {
    name.dispose();
    area.dispose();
    frigo.dispose();
    elec.dispose();
    drop.dispose();
    notes.dispose();
  }
}

class _VisitScreenState extends State<VisitScreen> {
  String _support = '';
  bool _breaker = false;
  late final TextEditingController _meter;
  late final TextEditingController _uePlace;
  late final TextEditingController _breakerNote;
  late final TextEditingController _notes;
  final List<_VisitRoom> _rooms = [];

  @override
  void initState() {
    super.initState();
    Map<String, dynamic> d = {};
    try {
      final parsed = jsonDecode(widget.quote.visitData);
      if (parsed is Map<String, dynamic>) d = parsed;
    } catch (_) {}
    _support = (d['support'] ?? '').toString();
    _breaker = d['breaker'] == true || d['breaker'] == 1 || d['breaker'] == '1';
    _meter = TextEditingController(text: (d['meter_len'] ?? '').toString());
    _uePlace = TextEditingController(text: (d['ue_place'] ?? '').toString());
    _breakerNote =
        TextEditingController(text: (d['breaker_note'] ?? '').toString());
    _notes = TextEditingController(text: (d['notes'] ?? '').toString());
    for (final r in (d['rooms'] as List? ?? [])) {
      if (r is Map<String, dynamic>) _rooms.add(_VisitRoom(r));
    }
  }

  @override
  void dispose() {
    _meter.dispose();
    _uePlace.dispose();
    _breakerNote.dispose();
    _notes.dispose();
    for (final r in _rooms) {
      r.dispose();
    }
    super.dispose();
  }

  /// Réécrit la fiche dans le devis à chaque modification.
  void _sync() {
    final rooms = _rooms.map((r) => r.toJson()).toList();
    final empty = _support.isEmpty &&
        _meter.text.isEmpty &&
        _uePlace.text.isEmpty &&
        !_breaker &&
        _breakerNote.text.isEmpty &&
        _notes.text.isEmpty &&
        rooms.isEmpty;
    widget.quote.visitData = empty
        ? ''
        : jsonEncode({
            'support': _support,
            'meter_len': _meter.text,
            'ue_place': _uePlace.text,
            'breaker': _breaker ? 1 : 0,
            'breaker_note': _breakerNote.text,
            'notes': _notes.text,
            'rooms': rooms,
          });
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool number = false, int lines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: lines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (_) => _sync(),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: Color(0xFF5B6A72))),
      );

  Widget _card(List<Widget> children) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F1A2B), Color(0xFF243751)]),
            ),
          ),

        title: Text('Visite technique — ${widget.quote.quoteNumber.isEmpty ? 'nouveau devis' : widget.quote.quoteNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _sectionTitle('Général'),
          _card([
            const Text('Support unité extérieure',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A868D))),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final opt in const [
                ['mural', 'Mural'],
                ['sol', 'Au sol'],
              ])
                ChoiceChip(
                  label: Text(opt[1]),
                  selected: _support == opt[0],
                  onSelected: (sel) => setState(() {
                    _support = sel ? opt[0] : '';
                    _sync();
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            _field('Emplacement de l\'unité extérieure', _uePlace),
            const SizedBox(height: 10),
            _field('Liaison électrique UE → compteur (m)', _meter,
                number: true),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Disjoncteur à prévoir'),
              value: _breaker,
              onChanged: (v) => setState(() {
                _breaker = v;
                _sync();
              }),
            ),
            if (_breaker) _field('Calibre / détail', _breakerNote),
            const SizedBox(height: 10),
            _field('Observations générales', _notes, lines: 3),
          ]),
          _sectionTitle('Pièces à équiper (${_rooms.length})'),
          for (var i = 0; i < _rooms.length; i++) _roomCard(i),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                _rooms.add(_VisitRoom(const {}));
                _sync();
              }),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une pièce'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Enregistrée avec le devis (pense à sauvegarder le devis en revenant). Jamais visible du client.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF5B6A72)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomCard(int i) {
    final r = _rooms[i];
    return _card([
      Row(children: [
        Expanded(
          child: TextField(
            controller: r.name,
            decoration: InputDecoration(
                labelText: 'Pièce ${i + 1} — nom', isDense: true),
            style: const TextStyle(fontWeight: FontWeight.w600),
            onChanged: (_) => _sync(),
          ),
        ),
        IconButton(
          tooltip: 'Supprimer la pièce',
          onPressed: () => setState(() {
            _rooms.removeAt(i).dispose();
            _sync();
          }),
          icon: const Icon(Icons.close, color: Color(0xFFB32D2E)),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _field('Superficie (m²)', r.area, number: true)),
        const SizedBox(width: 8),
        Expanded(child: _field('Liaison frigo (m)', r.frigo, number: true)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _field('Liaison élec. UE↔UI (m)', r.elec, number: true)),
        const SizedBox(width: 8),
        Expanded(child: _field('Dénivelé (m)', r.drop, number: true)),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Pompe de relevage'),
        value: r.pump,
        onChanged: (v) => setState(() {
          r.pump = v;
          _sync();
        }),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Goulotte apparente'),
        value: r.trunk,
        onChanged: (v) => setState(() {
          r.trunk = v;
          _sync();
        }),
      ),
      _field('Remarques', r.notes),
    ]);
  }
}
