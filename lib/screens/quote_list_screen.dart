import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../models/models.dart';
import 'login_screen.dart';
import 'quote_edit_screen.dart';

class QuoteListScreen extends StatefulWidget {
  const QuoteListScreen({super.key});

  @override
  State<QuoteListScreen> createState() => _QuoteListScreenState();
}

class _QuoteListScreenState extends State<QuoteListScreen> {
  SiteSettings _settings = SiteSettings.fallback();
  List<Quote> _quotes = [];
  bool _loading = true;
  String _statusFilter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static SiteSettings? _settingsCache;

  Future<void> _load() async {
    setState(() {
      _loading = _quotes.isEmpty;
      _error = null;
    });
    try {
      final futures = <Future>[
        ApiClient.instance.get('/quotes', {
          'per_page': '50',
          if (_statusFilter.isNotEmpty) 'status': _statusFilter,
        }),
        if (_settingsCache == null) ApiClient.instance.get('/settings'),
      ];
      final results = await Future.wait(futures);
      _quotes = ((results[0] as Map<String, dynamic>)['quotes'] as List)
          .map((e) => Quote.fromJson(e as Map<String, dynamic>))
          .toList();
      if (results.length > 1) {
        _settingsCache =
            SiteSettings.fromJson(results[1] as Map<String, dynamic>);
      }
      _settings = _settingsCache ?? _settings;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteQuote(Quote q) async {
    try {
      await ApiClient.instance.delete('/quotes/${q.id}');
      setState(() => _quotes.removeWhere((x) => x.id == q.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Devis ${q.quoteNumber} supprimé')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Suppression impossible : $e'),
            backgroundColor: const Color(0xFFB32D2E)));
        _load();
      }
    }
  }

  Future<bool> _confirmDelete(Quote q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer ${q.quoteNumber} ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB32D2E)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _openEditor([Quote? quote]) async {
    final changed = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) =>
            QuoteEditScreen(quoteId: quote?.id ?? 0, settings: _settings),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (changed == true) _load();
  }

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

        title: const Text('Devis PPSOLAR'),
        actions: [
          IconButton(
            tooltip: 'Déconnexion',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiClient.instance.clearCredentials();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _filterChip('', 'Tous'),
                  for (final e in statusLabels.entries)
                    _filterChip(e.key, e.value),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau devis'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          style:
                              const TextStyle(color: Color(0xFFB32D2E))),
                    ),
                  ])
                : _quotes.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Aucun devis')),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 90),
                        itemCount: _quotes.length,
                        itemBuilder: (_, i) => _quoteCard(_quotes[i]),
                      ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _statusFilter = value);
          _load();
        },
        backgroundColor: const Color(0xFF33454F),
        selectedColor: const Color(0xFFF5A623),
        surfaceTintColor: Colors.transparent,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF1C2B33) : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _quoteCard(Quote q) {
    return Dismissible(
      key: ValueKey('quote-${q.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(q),
      onDismissed: (_) => _deleteQuote(q),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFB32D2E),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: _quoteCardInner(q),
    );
  }

  Color _brandColor(Quote q) {
    final b = _settings.brands.where((x) => x.key == q.brand);
    if (b.isEmpty) return const Color(0xFF1C2B33);
    final hex = b.first.color.replaceAll('#', '');
    return Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF1C2B33);
  }

  Widget _quoteCardInner(Quote q) {
    final ttc = q.serverTotalTtc ?? q.totalTtc(_settings);
    final expired = q.expiresAt != null &&
        q.expiresAt!.isBefore(DateTime.now()) &&
        (q.status == 'draft' || q.status == 'sent');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
              left: BorderSide(color: _brandColor(q), width: 4)),
        ),
        child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: () => _openEditor(q),
        title: Row(
          children: [
            if (_settings.brands.length > 1) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: _brandColor(q), shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(q.quoteNumber,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            _StatusBadge(status: q.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.customerDisplayName.isEmpty
                  ? q.customerEmail
                  : q.customerDisplayName),
              const SizedBox(height: 2),
              Text(
                [
                  if (q.createdAt != null)
                    DateFormat('d MMM yyyy', 'fr_FR').format(q.createdAt!),
                  if (expired) '⏰ Expiré',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: expired
                      ? const Color(0xFFB32D2E)
                      : Colors.black45,
                ),
              ),
            ],
          ),
        ),
        trailing: Text(
          euro(ttc),
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 15),
        ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  static const _colors = {
    'draft': (Color(0xFFF0F0F1), Color(0xFF50575E)),
    'sent': (Color(0xFFF0F6FC), Color(0xFF2271B1)),
    'accepted': (Color(0xFFEDFAEF), Color(0xFF007A29)),
    'rejected': (Color(0xFFFCF0F1), Color(0xFFB32D2E)),
    'converted': (Color(0xFFF0F0F1), Color(0xFF646970)),
    'expired': (Color(0xFFFCF9E8), Color(0xFF996B00)),
  };

  @override
  Widget build(BuildContext context) {
    final c = _colors[status] ??
        (const Color(0xFFF0F0F1), const Color(0xFF50575E));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.$1,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusLabels[status] ?? status,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: c.$2),
      ),
    );
  }
}
