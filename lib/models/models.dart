import 'package:intl/intl.dart';


/// WordPress renvoie les décimaux MySQL en chaînes ("1633.85") :
/// parsing tolérant num / String / null.
double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
}

int toI(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

final _price = NumberFormat.currency(locale: 'fr_FR', symbol: '€');
String euro(num v) => _price.format(v);

/// Réglages du site (taux de TVA, devise…) — récupérés au démarrage.
class Brand {
  Brand({
    required this.key,
    required this.name,
    required this.prefix,
    required this.color,
    this.tagline = '',
  });

  final String key;
  final String name;
  final String prefix;
  final String color;
  final String tagline;

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(
        key: (j['key'] ?? 'ppsolar').toString(),
        name: (j['name'] ?? '').toString(),
        prefix: (j['prefix'] ?? 'DEV').toString(),
        color: (j['color'] ?? '#1c2b33').toString(),
        tagline: (j['tagline'] ?? '').toString(),
      );
}

class QuoteRevision {
  QuoteRevision({
    required this.id,
    required this.revisionNo,
    required this.quoteNumber,
    required this.totalTtc,
    required this.createdAt,
  });

  final int id;
  final int revisionNo;
  final String quoteNumber;
  final double totalTtc;
  final DateTime? createdAt;

  factory QuoteRevision.fromJson(Map<String, dynamic> j) => QuoteRevision(
        id: toI(j['id']),
        revisionNo: toI(j['revision_no']),
        quoteNumber: (j['quote_number'] ?? '').toString(),
        totalTtc: toD(j['total_ttc']),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

class SiteSettings {
  SiteSettings({
    required this.companyName,
    required this.taxesEnabled,
    required this.taxRate,
    required this.shippingTaxRate,
    required this.taxLabel,
    required this.expiryDays,
    this.brands = const [],
    this.pdfEngine = 'browser',
  });

  final String companyName;
  final bool taxesEnabled;
  final double taxRate;
  final double shippingTaxRate;
  final String taxLabel;
  final List<Brand> brands;
  final String pdfEngine;
  final int expiryDays;

  factory SiteSettings.fromJson(Map<String, dynamic> j) => SiteSettings(
        companyName: j['company_name'] ?? '',
        taxesEnabled: j['taxes_enabled'] == true,
        taxRate: toD(j['tax_rate']),
        shippingTaxRate: toD(j['shipping_tax_rate']),
        taxLabel: j['tax_label'] ?? 'TVA',
        expiryDays: j['expiry_days'] == null ? 30 : toI(j['expiry_days']),
              brands: ((j['brands'] as List?) ?? const [])
            .map((e) => Brand.fromJson(e as Map<String, dynamic>))
            .toList(),
        pdfEngine: (j['pdf_engine'] ?? 'browser').toString(),
      );

  static SiteSettings fallback() => SiteSettings(
        companyName: 'PPSOLAR',
        taxesEnabled: true,
        taxRate: 0.2,
        shippingTaxRate: 0.2,
        taxLabel: 'TVA',
        expiryDays: 30,
      );
}

class QuoteItem {
  QuoteItem({
    this.productId = 0,
    this.wcProductId = 0,
    required this.name,
    this.sku = '',
    this.quantity = 1,
    required this.originalPrice,
    this.discountType = 'none',
    this.discountValue = 0,
    this.isCustom = false,
    this.warranty = '',
  });

  int productId;
  int wcProductId;
  String name;
  String sku;
  int quantity;
  double originalPrice;
  String discountType; // none | percentage | fixed
  double discountValue;
  bool isCustom;
  String warranty;

  double get unitPriceAfterDiscount {
    var p = originalPrice;
    if (discountType == 'percentage' && discountValue > 0) {
      p -= originalPrice * discountValue / 100;
    } else if (discountType == 'fixed' && discountValue > 0) {
      p -= discountValue;
    }
    return p < 0 ? 0 : p;
  }

  double get total => unitPriceAfterDiscount * quantity;

  factory QuoteItem.fromJson(Map<String, dynamic> j) => QuoteItem(
        productId: j['product_id'] == null ? 0 : toI(j['product_id']),
        wcProductId: j['wc_product_id'] == null ? 0 : toI(j['wc_product_id']),
        name: j['name'] ?? '',
        sku: j['sku'] ?? '',
        quantity: j['quantity'] == null ? 1 : toI(j['quantity']),
        originalPrice: toD(j['original_price'] ?? j['unit_price']),
        discountType: j['discount_type'] ?? 'none',
        discountValue: toD(j['discount_value']),
        isCustom: j['is_custom'] == true,
        warranty: (j['warranty'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'wc_product_id': wcProductId,
        'name': name,
        'sku': sku,
        'quantity': quantity,
        'original_price': originalPrice,
        'unit_price': unitPriceAfterDiscount,
        'discount_type': discountType,
        'discount_value': discountValue,
        'is_custom': isCustom,
        'warranty': warranty,
      };
}

class Quote {
  Quote({
    this.id = 0,
    this.quoteNumber = '',
    this.status = 'draft',
    this.customerFirstName = '',
    this.customerLastName = '',
    this.customerCompany = '',
    this.customerEmail = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.customerCity = '',
    this.customerPostcode = '',
    this.customerCountry = 'FR',
    this.shippingFirstName = '',
    this.shippingLastName = '',
    this.shippingCompany = '',
    this.shippingAddress = '',
    this.shippingCity = '',
    this.shippingPostcode = '',
    this.shippingCountry = '',
    this.discountType = 'none',
    this.discountValue = 0,
    this.shippingCost = 0,
    this.shippingFree = false,
    this.visitData = '',
    this.installDesc = '',
    this.installCost = 0,
    this.installDuration = '',
    this.installStart,
    this.brand = 'ppsolar',
    this.notes = '',
    this.requireSignature = true,
    this.paymentMode = 'bank',
    this.amountScope = 'total',
    this.depositPct = 30,
    this.acceptedAt,
    this.acceptedName = '',
    this.createdAt,
    this.expiresAt,
    List<QuoteItem>? items,
    this.serverTotalTtc,
    this.pdfUrl = '',
    this.signatureUrl = '',
  }) : items = items ?? [];

  int id;
  String quoteNumber;
  String status;
  String customerFirstName;
  String customerLastName;
  String customerCompany;
  String customerEmail;
  String customerPhone;
  String customerAddress;
  String customerCity;
  String customerPostcode;
  String customerCountry;
  String shippingFirstName;
  String shippingLastName;
  String shippingCompany;
  String shippingAddress;
  String shippingCity;
  String shippingPostcode;
  String shippingCountry;
  String discountType;
  double discountValue;
  double shippingCost;
  bool shippingFree;
  String visitData;
  String installDesc;
  double installCost;
  String installDuration;
  DateTime? installStart;
  String brand;
  String notes;
  bool requireSignature;
  String paymentMode; // bank | shop | none
  String amountScope; // total | materiel | acompte
  double depositPct;
  DateTime? acceptedAt;
  String acceptedName;
  DateTime? createdAt;
  DateTime? expiresAt;
  List<QuoteItem> items;

  /// Total TTC renvoyé par le serveur (référence pour les listes).
  final double? serverTotalTtc;

  /// Liens fournis par le serveur (lecture seule).
  final String pdfUrl;
  final String signatureUrl;

  String get customerDisplayName {
    final full = '$customerFirstName $customerLastName'.trim();
    return full.isNotEmpty ? full : customerCompany;
  }

  /* Calculs — miroir exact du modèle PHP (arrondis à 2 décimales). */

  double get totalHt =>
      items.fold(0.0, (sum, it) => sum + it.total);

  double get discountAmount {
    if (discountType == 'percentage' && discountValue > 0) {
      return _r2(totalHt * discountValue / 100);
    }
    if (discountType == 'fixed' && discountValue > 0) return discountValue;
    return 0;
  }

  double get totalAfterDiscount => totalHt - discountAmount;

  double taxAmount(SiteSettings s) => !s.taxesEnabled
      ? 0
      : _r2((totalAfterDiscount + installCost) * s.taxRate) +
          _r2(effectiveShipping * s.shippingTaxRate);

  /// Livraison comptée dans les totaux : 0 si elle est offerte.
  double get effectiveShipping => shippingFree ? 0 : shippingCost;

  double totalTtc(SiteSettings s) =>
      totalAfterDiscount + installCost + effectiveShipping + taxAmount(s);

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        id: j['id'] == null ? 0 : toI(j['id']),
        quoteNumber: j['quote_number'] ?? '',
        status: j['status'] ?? 'draft',
        customerFirstName: j['customer_first_name'] ?? '',
        customerLastName: j['customer_last_name'] ?? '',
        customerCompany: j['customer_company'] ?? '',
        customerEmail: j['customer_email'] ?? '',
        customerPhone: j['customer_phone'] ?? '',
        customerAddress: j['customer_address'] ?? '',
        customerCity: j['customer_city'] ?? '',
        customerPostcode: j['customer_postcode'] ?? '',
        customerCountry: (j['customer_country'] ?? 'FR').toString(),
        shippingFirstName: j['shipping_first_name'] ?? '',
        shippingLastName: j['shipping_last_name'] ?? '',
        shippingCompany: j['shipping_company'] ?? '',
        shippingAddress: j['shipping_address'] ?? '',
        shippingCity: j['shipping_city'] ?? '',
        shippingPostcode: j['shipping_postcode'] ?? '',
        shippingCountry: (j['shipping_country'] ?? '').toString(),
        discountType: j['discount_type'] ?? 'none',
        discountValue: toD(j['discount_value']),
        shippingCost: toD(j['shipping_cost']),
        shippingFree: j['shipping_free'] == true || toI(j['shipping_free']) == 1,
        visitData: (j['visit_data'] ?? '').toString(),
        installDesc: j['install_desc'] ?? '',
        installCost: toD(j['install_cost']),
        installDuration: (j['install_duration'] ?? '').toString(),
        installStart: DateTime.tryParse((j['install_start'] ?? '').toString()),
        brand: (j['brand'] ?? 'ppsolar').toString(),
        notes: j['notes'] ?? '',
        requireSignature: j['require_signature'] == null
            ? true
            : (j['require_signature'] == true ||
                toI(j['require_signature']) == 1),
        paymentMode: (j['payment_mode'] ?? 'bank').toString(),
        amountScope: (j['amount_scope'] ?? 'total').toString(),
        depositPct:
            j['deposit_pct'] == null ? 30 : toD(j['deposit_pct']),
        acceptedAt:
            DateTime.tryParse((j['accepted_at'] ?? '').toString()),
        acceptedName: (j['accepted_name'] ?? '').toString(),
        createdAt: DateTime.tryParse(j['created_at'] ?? ''),
        expiresAt: DateTime.tryParse(j['expires_at'] ?? ''),
        items: ((j['items'] as List?) ?? [])
            .map((e) => QuoteItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        serverTotalTtc: j['total_ttc'] == null ? null : toD(j['total_ttc']),
        pdfUrl: (j['pdf_url'] ?? '').toString(),
        signatureUrl: (j['signature_url'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'customer_first_name': customerFirstName,
        'customer_last_name': customerLastName,
        'customer_company': customerCompany,
        'customer_email': customerEmail,
        'customer_phone': customerPhone,
        'customer_address': customerAddress,
        'customer_city': customerCity,
        'customer_postcode': customerPostcode,
        'customer_country': customerCountry,
        'shipping_first_name': shippingFirstName,
        'shipping_last_name': shippingLastName,
        'shipping_company': shippingCompany,
        'shipping_address': shippingAddress,
        'shipping_city': shippingCity,
        'shipping_postcode': shippingPostcode,
        'shipping_country': shippingCountry,
        'discount_type': discountType,
        'discount_value': discountValue,
        'shipping_cost': shippingCost,
        'shipping_free': shippingFree ? 1 : 0,
        'visit_data': visitData,
        'install_desc': installDesc,
        'install_cost': installCost,
        'install_duration': installDuration,
        'install_start': installStart == null
            ? ''
            : '${installStart!.year.toString().padLeft(4, '0')}-${installStart!.month.toString().padLeft(2, '0')}-${installStart!.day.toString().padLeft(2, '0')}',
        'brand': brand,
        'notes': notes,
        'require_signature': requireSignature ? 1 : 0,
        'payment_mode': paymentMode,
        'amount_scope': amountScope,
        'deposit_pct': depositPct,
        if (expiresAt != null)
          'expires_at': DateFormat('yyyy-MM-dd').format(expiresAt!),
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.price,
    required this.image,
    this.warranty = '',
    this.cost = 0,
    this.quickBrand = '',
    this.quickGroup = '',
  });

  final int id;
  final String name;
  final String sku;
  final double price;
  final String image;
  final String warranty;
  final double cost;
  final String quickBrand;
  final String quickGroup;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: toI(j['id']),
        name: j['name'] ?? '',
        sku: j['sku'] ?? '',
        price: toD(j['price']),
        image: j['image'] ?? '',
        warranty: (j['warranty'] ?? '').toString(),
        cost: toD(j['cost']),
        quickBrand: (j['quick_brand'] ?? '').toString(),
        quickGroup: (j['quick_group'] ?? '').toString(),
      );
}

class CustomerHit {
  CustomerHit({
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.postcode = '',
    this.country = 'FR',
  });

  final String firstName;
  final String lastName;
  final String company;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String postcode;
  final String country;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : (company.isNotEmpty ? company : email);
  }

  factory CustomerHit.fromJson(Map<String, dynamic> j) => CustomerHit(
        firstName: (j['first_name'] ?? '').toString(),
        lastName: (j['last_name'] ?? '').toString(),
        company: (j['company'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        postcode: (j['postcode'] ?? '').toString(),
        country: (j['country'] ?? 'FR').toString(),
      );
}

const countryLabels = {
  'FR': 'France',
  'BE': 'Belgique',
  'CH': 'Suisse',
  'LU': 'Luxembourg',
  'MC': 'Monaco',
  'DE': 'Allemagne',
  'ES': 'Espagne',
  'IT': 'Italie',
  'PT': 'Portugal',
};

const statusLabels = {
  'draft': 'Brouillon',
  'sent': 'Envoyé',
  'accepted': 'Accepté',
  'rejected': 'Refusé',
  'converted': 'Converti',
  'expired': 'Expiré',
};
