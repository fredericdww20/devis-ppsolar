import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dossier_screen.dart';
import 'visit_screen.dart';
import 'package:intl/intl.dart';

import '../api/client.dart';
import '../models/models.dart';
import 'product_search_screen.dart';

class QuoteEditScreen extends StatefulWidget {
  const QuoteEditScreen(
      {super.key, required this.quoteId, required this.settings});

  final int quoteId;
  final SiteSettings settings;

  @override
  State<QuoteEditScreen> createState() => _QuoteEditScreenState();
}

class _QuoteEditScreenState extends State<QuoteEditScreen> {
  Quote _q = Quote();
  int _clientFormKey = 0;
  bool _shipDiff = false;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  List<Product> _quick = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadQuick();
  }

  Future<void> _loadQuick() async {
    try {
      final res = await ApiClient.instance.get('/quick-products');
      final list = ((res as Map<String, dynamic>)['products'] as List? ?? [])
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _quick = list);
    } catch (_) {
      // hors-ligne ou API ancienne : le bandeau reste simplement absent
    }
  }

  void _quickTap(Product p) {
    setState(() {
      final existing =
          _q.items.where((i) => i.productId == p.id && p.id != 0).toList();
      if (existing.isNotEmpty) {
        existing.first.quantity += 1;
        _snack('${p.name} — quantité : ${existing.first.quantity}');
      } else {
        _q.items.add(QuoteItem(
          productId: p.id,
          wcProductId: p.id,
          name: p.name,
          sku: p.sku,
          originalPrice: p.price,
          warranty: p.warranty,
        ));
        _snack('${p.name} ajouté');
      }
      _dirty = true;
    });
  }

  Future<void> _load() async {
    if (widget.quoteId == 0) {
      _q = Quote(
        expiresAt:
            DateTime.now().add(Duration(days: widget.settings.expiryDays)),
      );
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await ApiClient.instance.get('/quotes/${widget.quoteId}');
      _q = Quote.fromJson(data as Map<String, dynamic>);
      _shipDiff = _q.shippingLastName.isNotEmpty ||
          _q.shippingAddress.isNotEmpty ||
          _q.shippingCity.isNotEmpty;
    } catch (e) {
      if (mounted) _snack('Chargement impossible : $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _showRevisions() async {
    List<QuoteRevision> revs = [];
    try {
      final res = await ApiClient.instance.get('/quotes/${_q.id}/revisions');
      revs = ((res as Map<String, dynamic>)['revisions'] as List)
          .map((e) => QuoteRevision.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
      return;
    }
    if (!mounted) return;
    if (revs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Aucune version envoyée — une version est figée à chaque envoi par email.')));
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Versions envoyées',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            for (final r in revs)
              ListTile(
                leading: CircleAvatar(
                    radius: 17, child: Text('v${r.revisionNo}')),
                title: Text(
                    '${euro(r.totalTtc)} TTC',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(r.createdAt == null
                    ? ''
                    : DateFormat('d MMM yyyy à HH:mm', 'fr_FR')
                        .format(r.createdAt!)),
                trailing: TextButton(
                  child: const Text('Restaurer'),
                  onPressed: () => _restoreRevision(ctx, r),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreRevision(BuildContext sheetCtx, QuoteRevision r) async {
    final ok = await showDialog<bool>(
      context: sheetCtx,
      builder: (dCtx) => AlertDialog(
        title: Text('Restaurer la v${r.revisionNo} ?'),
        content: const Text(
            'Un nouveau devis brouillon sera créé à partir de cette version.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Restaurer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await ApiClient.instance
          .post('/quotes/${_q.id}/revisions/${r.revisionNo}/restore');
      final number = (res as Map<String, dynamic>)['quote_number'] ?? '';
      if (!mounted) return;
      Navigator.pop(sheetCtx);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Version restaurée en $number (brouillon)')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<bool> _save() async {
    if (_q.customerEmail.trim().isEmpty) {
      _snack('Email client obligatoire', error: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      final data = _q.id == 0
          ? await ApiClient.instance.post('/quotes', _q.toJson())
          : await ApiClient.instance.put('/quotes/${_q.id}', _q.toJson());
      _q = Quote.fromJson(data as Map<String, dynamic>);
      _shipDiff = _q.shippingLastName.isNotEmpty ||
          _q.shippingAddress.isNotEmpty ||
          _q.shippingCity.isNotEmpty;
      _dirty = false;
      _snack('Devis ${_q.quoteNumber} enregistré');
      return true;
    } catch (e) {
      _snack('Échec : $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _send() async {
    if (_dirty || _q.id == 0) {
      final ok = await _save();
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/quotes/${_q.id}/send');
      _q.status = 'sent';
      _snack('Devis envoyé à ${_q.customerEmail}');
    } catch (e) {
      _snack('Envoi impossible : $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFB32D2E) : null,
    ));
  }

  Future<void> _addProduct() async {
    final product = await Navigator.of(context).push<Product>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => const ProductSearchScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    if (product == null) return;
    setState(() {
      _q.items.add(QuoteItem(
        productId: product.id,
        wcProductId: product.id,
        name: product.name,
        sku: product.sku,
        originalPrice: product.price,
        warranty: product.warranty,
      ));
      _dirty = true;
    });
  }

  Future<void> _readyEmail() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commande complète'),
        content: const Text(
            'Envoyer au client l\'email « votre commande est complète, nous vous contactons pour le rendez-vous » (avec rappel du virement) ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Envoyer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.post('/quotes/${_q.id}/ready-email');
      _snack('Email « commande complète » envoyé.');
    } catch (e) {
      _snack('Envoi impossible : $e', error: true);
    }
  }

  List<Widget> _quickBand() {
    final visible = _quick
        .where((p) => p.quickBrand == 'all' || p.quickBrand == _q.brand)
        .toList();
    if (visible.isEmpty) return const [];
    final groups = <String, List<Product>>{};
    for (final p in visible) {
      groups.putIfAbsent(p.quickGroup, () => []).add(p);
    }
    final names = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [
      _card(children: [
        const Text('⚡ AJOUT RAPIDE — UN APPUI AJOUTE LA LIGNE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .5,
                color: Color(0xFF5B6A72))),
        const SizedBox(height: 8),
        for (final g in names) ...[
          if (g.isNotEmpty || names.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 5),
              child: Text(g.isEmpty ? 'Divers' : g,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF46535A))),
            ),
          LayoutBuilder(builder: (ctx, cons) {
            final cols = cons.maxWidth > 560 ? 3 : 2;
            final w = (cons.maxWidth - (cols - 1) * 8) / cols;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in groups[g]!)
                  SizedBox(
                    width: w,
                    child: OutlinedButton(
                      onPressed: () => _quickTap(p),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Row(children: [
                        if (p.image.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(p.image,
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox(width: 32, height: 32)),
                          ),
                        if (p.image.isNotEmpty) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1C2B33))),
                              Text('${euro(p.price)} HT',
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF2271B1))),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            );
          }),
        ],
      ]),
    ];
  }

  Future<void> _searchCustomer() async {
    final ctrl = TextEditingController();
    final hit = await showModalBottomSheet<CustomerHit>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        List<CustomerHit> results = [];
        bool searching = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> run(String term) async {
            if (term.trim().length < 2) return;
            setSheet(() => searching = true);
            try {
              final res = await ApiClient.instance
                  .get('/customers', {'search': term.trim()});
              results = (((res as Map<String, dynamic>)['customers']
                          as List?) ??
                      [])
                  .map((e) =>
                      CustomerHit.fromJson(e as Map<String, dynamic>))
                  .toList();
            } catch (_) {
              results = [];
            }
            setSheet(() => searching = false);
          }

          return Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rechercher un client existant',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Nom, email ou entreprise…',
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => run(ctrl.text)),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: run,
                ),
                const SizedBox(height: 10),
                if (searching)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child:
                          Center(child: CircularProgressIndicator())),
                if (!searching)
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in results)
                          ListTile(
                            leading:
                                const Icon(Icons.person_outline),
                            title: Text(c.displayName),
                            subtitle: Text([
                              c.email,
                              if (c.city.isNotEmpty) c.city
                            ].join(' — ')),
                            onTap: () => Navigator.pop(ctx, c),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        });
      },
    );
    if (hit == null) return;
    setState(() {
      _q.customerFirstName = hit.firstName;
      _q.customerLastName = hit.lastName;
      _q.customerCompany = hit.company;
      _q.customerEmail = hit.email;
      _q.customerPhone = hit.phone;
      _q.customerAddress = hit.address;
      _q.customerCity = hit.city;
      _q.customerPostcode = hit.postcode;
      _q.customerCountry =
          hit.country.isEmpty ? 'FR' : hit.country;
      _clientFormKey++; // reconstruit les champs avec les nouvelles valeurs
      _dirty = true;
    });
  }

  Future<void> _openPdf() async {
    if (_q.pdfUrl.isEmpty) {
      _snack('Enregistre le devis d\'abord', error: true);
      return;
    }
    final ok = await launchUrl(Uri.parse(_q.pdfUrl),
        mode: LaunchMode.externalApplication);
    if (!ok) _snack('Impossible d\'ouvrir le PDF', error: true);
  }

  Future<void> _duplicate() async {
    try {
      final res = await ApiClient.instance
          .post('/quotes/${_q.id}/duplicate');
      final num =
          ((res as Map<String, dynamic>)['quote_number'] ?? '').toString();
      if (!mounted) return;
      _snack('Copie créée : $num');
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Échec de la duplication : $e', error: true);
    }
  }

  Future<void> _convert() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convertir en commande ?'),
        content: const Text(
            'Une commande WooCommerce sera créée avec les lignes du devis. Le devis passera en « Converti ».'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Convertir')),
        ],
      ),
    );
    if (go != true) return;
    try {
      final res =
          await ApiClient.instance.post('/quotes/${_q.id}/convert');
      final num =
          ((res as Map<String, dynamic>)['order_number'] ?? '').toString();
      if (!mounted) return;
      _snack('Commande n°$num créée');
      await _reloadQuote();
    } catch (e) {
      _snack('Échec de la conversion : $e', error: true);
    }
  }

  Future<void> _renumber() async {
    try {
      final res =
          await ApiClient.instance.post('/quotes/${_q.id}/renumber');
      if (!mounted) return;
      setState(() {
        _q.quoteNumber =
            ((res as Map<String, dynamic>)['quote_number'] ?? '')
                .toString();
      });
      _snack('Nouveau numéro : ${_q.quoteNumber}');
    } catch (e) {
      _snack('Échec de la renumérotation : $e', error: true);
    }
  }

  Future<void> _reloadQuote() async {
    try {
      final data = await ApiClient.instance.get('/quotes/${_q.id}');
      if (!mounted) return;
      setState(() {
        _q = Quote.fromJson(data as Map<String, dynamic>);
        _shipDiff = _q.shippingLastName.isNotEmpty ||
            _q.shippingAddress.isNotEmpty ||
            _q.shippingCity.isNotEmpty;
        _dirty = false;
      });
    } catch (_) {}
  }

  void _showSignature() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Signature — ${_q.acceptedName}',
                  style:
                      const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Image.network(_q.signatureUrl,
                  errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Signature indisponible'))),
            ],
          ),
        ),
      ),
    );
  }

  void _addCustomItem() {
    setState(() {
      _q.items.add(QuoteItem(
        name: 'Produit libre',
        originalPrice: 0,
        isCustom: true,
      ));
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Modifications non enregistrées'),
            content: const Text('Quitter sans enregistrer ?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Rester')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Quitter')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F1A2B), Color(0xFF243751)]),
            ),
          ),

          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_q.id == 0 ? 'Nouveau devis' : _q.quoteNumber),
              Text(_q.brand == 'ppclim' ? 'PPCLIM' : 'PPSOLAR',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .6,
                      color: Color(0xFF9FB0C3))),
            ],
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
              )
            else ...[
              IconButton(
                  tooltip: 'Enregistrer',
                  onPressed: () async {
                    if (await _save() && mounted) setState(() {});
                  },
                  icon: const Icon(Icons.save_outlined)),
              if (_q.brand == 'ppclim')
                IconButton(
                    tooltip: 'Visite technique',
                    onPressed: () async {
                      final before = _q.visitData;
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => VisitScreen(quote: _q)));
                      if (_q.visitData != before) _markDirty();
                    },
                    icon: const Icon(Icons.fact_check_outlined)),
              if (_q.id != 0)
                IconButton(
                    tooltip: 'Dossier technique',
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => DossierScreen(
                                quoteId: _q.id,
                                quoteNumber: _q.quoteNumber))),
                    icon: const Icon(Icons.folder_outlined)),
              if (_q.id != 0)
                IconButton(
                    tooltip: 'Versions envoyées',
                    onPressed: _showRevisions,
                    icon: const Icon(Icons.history)),
              IconButton(
                  tooltip: 'Envoyer par email',
                  onPressed: _send,
                  icon: const Icon(Icons.send_outlined)),
              if (_q.id != 0)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'pdf':
                        _openPdf();
                      case 'dup':
                        _duplicate();
                      case 'convert':
                        _convert();
                      case 'renumber':
                        _renumber();
                      case 'ready':
                        _readyEmail();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'pdf', child: Text('Voir le PDF')),
                    const PopupMenuItem(
                        value: 'dup', child: Text('Dupliquer')),
                    const PopupMenuItem(
                        value: 'convert',
                        child: Text('Convertir en commande')),
                    if (_q.brand == 'ppclim' &&
                        (_q.status == 'accepted' || _q.status == 'converted'))
                      const PopupMenuItem(
                          value: 'ready',
                          child: Text('📦 Commande complète → RDV')),
                    const PopupMenuItem(
                        value: 'renumber',
                        child: Text('Renuméroter (marque)')),
                  ],
                ),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  if (_q.acceptedAt != null)
                    Card(
                      color: const Color(0xFFE6F4EA),
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined,
                            color: Color(0xFF1A7F37)),
                        title: Text(
                            'Accepté par ${_q.acceptedName.isEmpty ? 'le client' : _q.acceptedName}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A7F37))),
                        subtitle: Text(DateFormat(
                                "d MMMM yyyy 'à' HH:mm", 'fr_FR')
                            .format(_q.acceptedAt!)),
                        trailing: _q.signatureUrl.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Voir la signature',
                                icon: const Icon(Icons.draw_outlined,
                                    color: Color(0xFF1A7F37)),
                                onPressed: _showSignature,
                              ),
                      ),
                    ),
                  if (widget.settings.brands.length > 1) ...[
                    _sectionTitle('Marque'),
                    _card(children: [
                      Wrap(spacing: 8, children: [
                        for (final b in widget.settings.brands)
                          ChoiceChip(
                            label: Text(b.name),
                            selected: _q.brand == b.key,
                            onSelected: (_) => setState(() => _q.brand = b.key),
                          ),
                      ]),
                    ]),
                  ],
                  _sectionTitle('Client'),
                  _card(children: [
                    OutlinedButton.icon(
                      onPressed: _searchCustomer,
                      icon: const Icon(Icons.person_search_outlined),
                      label:
                          const Text('Rechercher un client existant'),
                    ),
                    const SizedBox(height: 4),
                  ]),
                  KeyedSubtree(
                      key: ValueKey('client-$_clientFormKey'),
                      child: _card(children: [
                    Row(children: [
                      Expanded(
                          child: _text('Prénom', _q.customerFirstName,
                              (v) => _q.customerFirstName = v)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _text('Nom', _q.customerLastName,
                              (v) => _q.customerLastName = v)),
                    ]),
                    _text('Société', _q.customerCompany,
                        (v) => _q.customerCompany = v),
                    _text('Email *', _q.customerEmail,
                        (v) => _q.customerEmail = v,
                        keyboard: TextInputType.emailAddress),
                    _text('Téléphone', _q.customerPhone,
                        (v) => _q.customerPhone = v,
                        keyboard: TextInputType.phone),
                    _text('Adresse', _q.customerAddress,
                        (v) => _q.customerAddress = v),
                    Row(children: [
                      SizedBox(
                          width: 130,
                          child: _text('Code postal', _q.customerPostcode,
                              (v) => _q.customerPostcode = v)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _text('Ville', _q.customerCity,
                              (v) => _q.customerCity = v)),
                    ]),
                    DropdownButtonFormField<String>(
                      value: countryLabels.containsKey(_q.customerCountry)
                          ? _q.customerCountry
                          : 'FR',
                      decoration:
                          const InputDecoration(labelText: 'Pays'),
                      items: [
                        for (final e in countryLabels.entries)
                          DropdownMenuItem(
                              value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() {
                        _q.customerCountry = v ?? 'FR';
                        _dirty = true;
                      }),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity:
                          ListTileControlAffinity.leading,
                      title: const Text(
                          'L\'adresse de livraison est différente'),
                      value: _shipDiff,
                      onChanged: (v) => setState(() {
                        _shipDiff = v ?? false;
                        if (!_shipDiff) {
                          _q.shippingFirstName = '';
                          _q.shippingLastName = '';
                          _q.shippingCompany = '';
                          _q.shippingAddress = '';
                          _q.shippingCity = '';
                          _q.shippingPostcode = '';
                          _q.shippingCountry = '';
                        }
                        _dirty = true;
                      }),
                    ),
                    if (_shipDiff) ...[
                      Row(children: [
                        Expanded(
                            child: _text('Prénom (livraison)',
                                _q.shippingFirstName,
                                (v) => _q.shippingFirstName = v)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _text('Nom (livraison)',
                                _q.shippingLastName,
                                (v) => _q.shippingLastName = v)),
                      ]),
                      _text('Société (livraison)', _q.shippingCompany,
                          (v) => _q.shippingCompany = v),
                      _text('Adresse (livraison)', _q.shippingAddress,
                          (v) => _q.shippingAddress = v),
                      Row(children: [
                        SizedBox(
                            width: 130,
                            child: _text('Code postal',
                                _q.shippingPostcode,
                                (v) => _q.shippingPostcode = v)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _text('Ville', _q.shippingCity,
                                (v) => _q.shippingCity = v)),
                      ]),
                      DropdownButtonFormField<String>(
                        value: countryLabels
                                .containsKey(_q.shippingCountry)
                            ? _q.shippingCountry
                            : 'FR',
                        decoration: const InputDecoration(
                            labelText: 'Pays (livraison)'),
                        items: [
                          for (final e in countryLabels.entries)
                            DropdownMenuItem(
                                value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() {
                          _q.shippingCountry = v ?? 'FR';
                          _dirty = true;
                        }),
                      ),
                    ],
                  ])),
                  _sectionTitle('Produits'),
                  ..._quickBand(),
                  for (var i = 0; i < _q.items.length; i++)
                    _ItemCard(
                      key: ObjectKey(_q.items[i]),
                      item: _q.items[i],
                      onChanged: _markDirty,
                      onRemove: () {
                        setState(() {
                          _q.items.removeAt(i);
                          _dirty = true;
                        });
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addProduct,
                          icon: const Icon(Icons.search),
                          label: const Text('Produit WooCommerce'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addCustomItem,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Produit libre'),
                        ),
                      ),
                    ]),
                  ),
                  _sectionTitle('Remise, pose et livraison'),
                  _card(children: [
                    Row(children: [
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<String>(
                          value: _q.discountType,
                          decoration:
                              const InputDecoration(labelText: 'Remise'),
                          items: const [
                            DropdownMenuItem(
                                value: 'none', child: Text('Aucune')),
                            DropdownMenuItem(
                                value: 'percentage', child: Text('%')),
                            DropdownMenuItem(
                                value: 'fixed', child: Text('€ HT')),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _q.discountType = v ?? 'none';
                              _dirty = true;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _num('Valeur', _q.discountValue, (v) {
                          _q.discountValue = v;
                        }),
                      ),
                    ]),
                    _num('Frais de livraison HT', _q.shippingCost,
                        (v) => _q.shippingCost = v),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _q.shippingFree,
                      onChanged: (v) => setState(() {
                        _q.shippingFree = v ?? false;
                        _dirty = true;
                      }),
                      title: const Text(
                          'Livraison offerte — montant barré sur le devis, non facturé',
                          style: TextStyle(fontSize: 13)),
                    ),
                    _num('Prestation de pose HT', _q.installCost,
                        (v) => _q.installCost = v),
                    _text('Description de la pose', _q.installDesc,
                        (v) => _q.installDesc = v,
                        lines: 2),
                    _text('Durée estimée des travaux', _q.installDuration,
                        (v) => _q.installDuration = v),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Démarrage possible à partir du'),
                      subtitle: Text(_q.installStart == null
                          ? 'Non renseigné'
                          : DateFormat('d MMMM yyyy', 'fr_FR')
                              .format(_q.installStart!)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_q.installStart != null)
                          IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _q.installStart = null)),
                        const Icon(Icons.calendar_today_outlined),
                      ]),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _q.installStart ??
                              DateTime.now().add(const Duration(days: 14)),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 730)),
                          locale: const Locale('fr', 'FR'),
                        );
                        if (d != null) setState(() => _q.installStart = d);
                      },
                    ),
                  ]),
                  _sectionTitle('Acceptation et règlement'),
                  _card(children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Signature requise'),
                      subtitle: const Text(
                          'Le client signe en ligne avant toute suite'),
                      value: _q.requireSignature,
                      onChanged: (v) => setState(() {
                        _q.requireSignature = v;
                        _dirty = true;
                      }),
                    ),
                    DropdownButtonFormField<String>(
                      value: _q.paymentMode,
                      decoration:
                          const InputDecoration(labelText: 'Règlement'),
                      items: const [
                        DropdownMenuItem(
                            value: 'bank', child: Text('Par virement')),
                        DropdownMenuItem(
                            value: 'shop',
                            child: Text('En ligne (boutique)')),
                        DropdownMenuItem(
                            value: 'none', child: Text('Aucun règlement')),
                      ],
                      onChanged: (v) => setState(() {
                        _q.paymentMode = v ?? 'bank';
                        _dirty = true;
                      }),
                    ),
                    if (_q.paymentMode != 'none') ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _q.amountScope,
                        decoration: const InputDecoration(
                            labelText: 'Montant demandé'),
                        items: const [
                          DropdownMenuItem(
                              value: 'total',
                              child: Text('Totalité du devis')),
                          DropdownMenuItem(
                              value: 'materiel',
                              child: Text(
                                  'Matériel seul (pose réglée ensuite)')),
                          DropdownMenuItem(
                              value: 'acompte', child: Text('Acompte (%)')),
                        ],
                        onChanged: (v) => setState(() {
                          _q.amountScope = v ?? 'total';
                          _dirty = true;
                        }),
                      ),
                      if (_q.amountScope == 'acompte')
                        TextFormField(
                          initialValue: _q.depositPct.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Pourcentage d\'acompte',
                              suffixText: '%'),
                          onChanged: (v) {
                            _q.depositPct =
                                double.tryParse(v.replaceAll(',', '.')) ??
                                    30;
                            _dirty = true;
                          },
                        ),
                    ],
                  ]),
                  _sectionTitle('Notes et validité'),
                  _card(children: [
                    DropdownButtonFormField<String>(
                      value: statusLabels.containsKey(_q.status)
                          ? _q.status
                          : 'draft',
                      decoration:
                          const InputDecoration(labelText: 'Statut'),
                      items: [
                        for (final e in statusLabels.entries)
                          DropdownMenuItem(
                              value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() {
                        _q.status = v ?? 'draft';
                        _dirty = true;
                      }),
                    ),
                    _text('Notes', _q.notes, (v) => _q.notes = v, lines: 3),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date d\'expiration'),
                      subtitle: Text(_q.expiresAt == null
                          ? 'Non définie'
                          : '${_q.expiresAt!.day}/${_q.expiresAt!.month}/${_q.expiresAt!.year}'),
                      trailing: const Icon(Icons.calendar_month_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _q.expiresAt ?? DateTime.now(),
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 1)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() {
                            _q.expiresAt = picked;
                            _dirty = true;
                          });
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 6),
                  _TotalsCard(quote: _q, settings: s),
                ],
              ),
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: Colors.black45)),
      );

  Widget _card({required List<Widget> children}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              children[i],
            ],
          ]),
        ),
      );

  Widget _text(String label, String value, ValueChanged<String> onChanged,
          {TextInputType? keyboard, int lines = 1}) =>
      TextFormField(
        initialValue: value,
        keyboardType: keyboard,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          onChanged(v);
          _markDirty();
        },
      );

  Widget _num(String label, double value, ValueChanged<double> onChanged) =>
      TextFormField(
        initialValue: value == 0 ? '' : value.toStringAsFixed(2),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: '€'),
        onChanged: (v) {
          onChanged(double.tryParse(v.replaceAll(',', '.')) ?? 0);
          _markDirty();
        },
      );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard(
      {super.key,
      required this.item,
      required this.onChanged,
      required this.onRemove});

  final QuoteItem item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: item.isCustom
                      ? TextFormField(
                          initialValue: item.name,
                          decoration: const InputDecoration(
                              labelText: 'Désignation'),
                          onChanged: (v) {
                            item.name = v;
                            onChanged();
                          },
                        )
                      : Text(item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 20),
                  color: const Color(0xFFB32D2E),
                ),
              ],
            ),
            if (item.sku.isNotEmpty)
              Text('Réf. ${item.sku}',
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.black45)),
            TextFormField(
              initialValue: item.warranty,
              decoration: const InputDecoration(
                  labelText: 'Garantie (optionnel)',
                  hintText: 'Ex. : Compresseur 5 ans, pièces 2 ans'),
              onChanged: (v) {
                item.warranty = v;
                onChanged();
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: item.quantity.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qté'),
                    onChanged: (v) {
                      item.quantity = int.tryParse(v) ?? 1;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: item.originalPrice == 0
                        ? ''
                        : item.originalPrice.toStringAsFixed(2),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Prix HT', suffixText: '€'),
                    onChanged: (v) {
                      item.originalPrice =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<String>(
                    value: item.discountType,
                    decoration:
                        const InputDecoration(labelText: 'Remise'),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('--')),
                      DropdownMenuItem(
                          value: 'percentage', child: Text('%')),
                      DropdownMenuItem(value: 'fixed', child: Text('€')),
                    ],
                    onChanged: (v) {
                      item.discountType = v ?? 'none';
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: item.discountValue == 0
                        ? ''
                        : item.discountValue.toString(),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(labelText: 'Val.'),
                    onChanged: (v) {
                      item.discountValue =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.quote, required this.settings});
  final Quote quote;
  final SiteSettings settings;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value,
            {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: color ?? Colors.black54,
                          fontWeight:
                              bold ? FontWeight.w700 : FontWeight.w400))),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row('Sous-total HT', euro(quote.totalHt)),
            if (quote.discountAmount > 0)
              row('Remise globale', '−${euro(quote.discountAmount)}',
                  color: const Color(0xFFB32D2E)),
            if (quote.installCost > 0)
              row('Prestation de pose HT', euro(quote.installCost)),
            if (quote.shippingCost > 0)
              quote.shippingFree
                  ? row('Livraison', 'Offerte',
                      color: const Color(0xFF1A7F37))
                  : row('Livraison HT', euro(quote.shippingCost)),
            if (settings.taxesEnabled)
              row(settings.taxLabel, euro(quote.taxAmount(settings))),
            const Divider(height: 18),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0F1A2B), Color(0xFF243751)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('TOTAL TTC',
                        style: TextStyle(
                            color: Color(0xFFDFE4E8),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ),
                  Text(euro(quote.totalTtc(settings)),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
