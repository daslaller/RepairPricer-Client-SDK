import 'product_catalog.dart';

enum ShopProductSource { supplier, own, bundle }

enum ShopPriceMode { inherit, fixed, markup, margin }

enum ShopCheckoutMode { merchant, stripe }

/// Shared shop pricing. Costs exclude VAT. Percentages use basis points;
/// fixed prices use the shop's display VAT basis. Round upwards to minor units
/// using integers so a minimum margin never becomes smaller through rounding.
class ShopPriceRule {
  ShopPriceRule({this.mode = ShopPriceMode.inherit, this.value = 0}) {
    validateProductAmount(value);
    if (mode == ShopPriceMode.margin && value >= 10000 ||
        mode == ShopPriceMode.markup && value > 100000 ||
        mode == ShopPriceMode.inherit && value != 0) {
      throw ArgumentError('Invalid shop pricing rule');
    }
  }
  final ShopPriceMode mode;
  final int value;
  int price(int costExVatMinor,
      {required int vatBasisPoints,
      required bool vatIncluded,
      ShopPriceRule? defaults}) {
    validateProductAmount(costExVatMinor);
    if (vatBasisPoints < 0 || vatBasisPoints > 10000) {
      throw ArgumentError('Invalid VAT rate');
    }
    final rule = mode == ShopPriceMode.inherit ? defaults : this;
    if (rule == null || rule.mode == ShopPriceMode.inherit) {
      throw ArgumentError('A default price rule is required');
    }
    if (rule.mode == ShopPriceMode.fixed) return rule.value;
    var numerator = BigInt.from(costExVatMinor);
    var denominator = BigInt.one;
    if (rule.mode == ShopPriceMode.markup) {
      numerator *= BigInt.from(10000 + rule.value);
      denominator *= BigInt.from(10000);
    } else {
      numerator *= BigInt.from(10000);
      denominator *= BigInt.from(10000 - rule.value);
    }
    if (vatIncluded) {
      numerator *= BigInt.from(10000 + vatBasisPoints);
      denominator *= BigInt.from(10000);
    }
    final result = (numerator + denominator - BigInt.one) ~/ denominator;
    if (result > BigInt.from(9007199254740991)) {
      throw ArgumentError('Price is too large');
    }
    return result.toInt();
  }

  factory ShopPriceRule.fromJson(Map<String, dynamic> json) => ShopPriceRule(
      mode: ShopPriceMode.values.byName(json['mode'] as String),
      value: json['value'] as int);
  Map<String, Object> toJson() => {'mode': mode.name, 'value': value};
}

class ShopBundleItem {
  ShopBundleItem({required this.productId, required this.quantity}) {
    shopText(productId, 36);
    if (quantity < 1 || quantity > 999) {
      throw ArgumentError('Invalid bundle quantity');
    }
  }
  final String productId;
  final int quantity;
  factory ShopBundleItem.fromJson(Map<String, dynamic> json) => ShopBundleItem(
      productId: json['productId'] as String,
      quantity: json['quantity'] as int);
  Map<String, Object> toJson() =>
      {'productId': productId, 'quantity': quantity};
}

/// Authenticated merchant configuration, never a public storefront payload.
/// Supplier identities are references to the licensed catalog, not credentials.
class ManagedShopProduct {
  ManagedShopProduct(
      {required this.productId,
      required this.source,
      required this.title,
      required this.category,
      required this.kind,
      required this.enabled,
      required this.purchaseLimit,
      required this.pricing,
      this.supplierId,
      this.supplierSku,
      this.modelCode,
      this.costExVatMinor = 0,
      this.stockQuantity = 0,
      List<String> images = const [],
      List<ShopBundleItem> components = const []})
      : images = List.unmodifiable(images),
        components = List.unmodifiable(components) {
    shopText(productId, 36);
    shopText(title, 256);
    shopText(category, 256);
    if (modelCode != null) shopText(modelCode!, 128);
    validateProductAmount(costExVatMinor);
    if (stockQuantity < 0 ||
        stockQuantity > 1000000 ||
        purchaseLimit < 0 ||
        purchaseLimit > 999) {
      throw ArgumentError('Invalid stock or purchase limit');
    }
    if (images.length > 20) throw ArgumentError('Too many images');
    for (final image in images) {
      shopHttpsUrl(image);
    }
    if (source == ShopProductSource.supplier) {
      shopText(supplierId, 64);
      shopText(supplierSku, 128);
      if (costExVatMinor != 0 || stockQuantity != 0) {
        throw ArgumentError('Supplier cost and stock come from the catalog');
      }
    } else if (supplierId != null || supplierSku != null) {
      throw ArgumentError('Unexpected supplier reference');
    }
    if (source == ShopProductSource.bundle) {
      if (components.isEmpty ||
          components.length > 50 ||
          components.any((c) => c.productId == productId) ||
          components.map((c) => c.productId).toSet().length !=
              components.length ||
          costExVatMinor != 0 ||
          stockQuantity != 0) {
        throw ArgumentError('Invalid bundle components');
      }
    } else if (components.isNotEmpty) {
      throw ArgumentError('Only bundles have components');
    }
  }
  final String productId, title, category;
  final ShopProductSource source;
  final ProductKind kind;
  final bool enabled;
  final int purchaseLimit, costExVatMinor, stockQuantity;
  final ShopPriceRule pricing;
  final String? supplierId, supplierSku, modelCode;
  final List<String> images;
  final List<ShopBundleItem> components;
  factory ManagedShopProduct.fromJson(
          Map<String, dynamic> j) =>
      ManagedShopProduct(
          productId: j['productId'] as String,
          source: ShopProductSource.values.byName(j['source'] as String),
          title: j['title'] as String,
          category: j['category'] as String,
          kind: ProductKind.values.byName(j['kind'] as String),
          enabled: j['enabled'] as bool,
          purchaseLimit: j['purchaseLimit'] as int,
          pricing:
              ShopPriceRule
                  .fromJson(Map<String, dynamic>.from(j['pricing'] as Map)),
          supplierId: j['supplierId'] as String?,
          supplierSku: j['supplierSku'] as String?,
          modelCode: j['modelCode'] as String?,
          costExVatMinor: j['costExVatMinor'] as int? ?? 0,
          stockQuantity: j['stockQuantity'] as int? ?? 0,
          images: (j['images'] as List? ?? []).cast<String>(),
          components: (j[
                      'components'] as List? ??
                  [])
              .map((v) =>
                  ShopBundleItem.fromJson(Map<String, dynamic>.from(v as Map)))
              .toList());
  Map<String, Object?> toJson() => {
        'productId': productId,
        'source': source.name,
        'title': title,
        'category': category,
        'kind': kind.name,
        'enabled': enabled,
        'purchaseLimit': purchaseLimit,
        'pricing': pricing.toJson(),
        'supplierId': supplierId,
        'supplierSku': supplierSku,
        'modelCode': modelCode,
        'costExVatMinor': costExVatMinor,
        'stockQuantity': stockQuantity,
        'images': images,
        'components': components.map((c) => c.toJson()).toList(),
      };
}

class ShopSettings {
  ShopSettings(
      {required this.title,
      required this.currency,
      required this.vatIncluded,
      required this.vatBasisPoints,
      required this.defaultPricing,
      this.enabled = false,
      this.checkoutMode = ShopCheckoutMode.merchant,
      this.locale = 'sv',
      this.accentColor = '#176b5b',
      this.shippingMinor = 0,
      this.checkoutReturnUrl,
      List<String> allowedOrigins = const [],
      List<String> shippingCountries = const ['SE']})
      : allowedOrigins = List.unmodifiable(allowedOrigins),
        shippingCountries = List.unmodifiable(shippingCountries) {
    shopText(title, 256);
    validateProductCurrency(currency);
    validateProductAmount(shippingMinor);
    if (defaultPricing.mode == ShopPriceMode.inherit ||
        defaultPricing.mode == ShopPriceMode.fixed ||
        vatBasisPoints < 0 ||
        vatBasisPoints > 10000 ||
        !['sv', 'sv-SE', 'en', 'en-GB', 'en-US'].contains(locale) ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accentColor)) {
      throw ArgumentError('Invalid shop settings');
    }
    if (allowedOrigins.length > 20 ||
        shippingCountries.isEmpty ||
        shippingCountries.length > 50 ||
        shippingCountries.any((c) => !RegExp(r'^[A-Z]{2}$').hasMatch(c))) {
      throw ArgumentError('Invalid countries or origins');
    }
    for (final value in allowedOrigins) {
      final uri = shopHttpsUrl(value);
      if (uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        throw ArgumentError('Expected a website origin');
      }
    }
    if (checkoutReturnUrl != null) {
      final url = shopHttpsUrl(checkoutReturnUrl!);
      if (!allowedOrigins.any((v) => Uri.parse(v).origin == url.origin)) {
        throw ArgumentError(
            'Checkout return URL must belong to an allowed website');
      }
    }
    if (checkoutMode == ShopCheckoutMode.stripe &&
        (!vatIncluded || checkoutReturnUrl == null)) {
      throw ArgumentError(
          'Stripe checkout needs VAT-inclusive prices and a return URL');
    }
  }
  final String title, currency, locale, accentColor;
  final bool enabled, vatIncluded;
  final int vatBasisPoints, shippingMinor;
  final ShopPriceRule defaultPricing;
  final ShopCheckoutMode checkoutMode;
  final String? checkoutReturnUrl;
  final List<String> allowedOrigins, shippingCountries;
  factory ShopSettings.defaults() => ShopSettings(
      title: 'My electronics shop',
      currency: 'SEK',
      vatIncluded: true,
      vatBasisPoints: 2500,
      defaultPricing: ShopPriceRule(mode: ShopPriceMode.markup, value: 2000));
  factory ShopSettings.fromJson(Map<String, dynamic> j) => ShopSettings(
      title: j['title'] as String,
      currency: j['currency'] as String,
      vatIncluded: j['vatIncluded'] as bool,
      vatBasisPoints: j['vatBasisPoints'] as int,
      defaultPricing: ShopPriceRule.fromJson(
          Map<String, dynamic>.from(j['defaultPricing'] as Map)),
      enabled: j['enabled'] as bool? ?? false,
      checkoutMode: ShopCheckoutMode.values
          .byName(j['checkoutMode'] as String? ?? 'merchant'),
      locale: j['locale'] as String? ?? 'sv',
      accentColor: j['accentColor'] as String? ?? '#176b5b',
      shippingMinor: j['shippingMinor'] as int? ?? 0,
      checkoutReturnUrl: j['checkoutReturnUrl'] as String?,
      allowedOrigins: (j['allowedOrigins'] as List? ?? []).cast<String>(),
      shippingCountries:
          (j['shippingCountries'] as List? ?? ['SE']).cast<String>());
  Map<String, Object?> toJson() => {
        'title': title,
        'currency': currency,
        'vatIncluded': vatIncluded,
        'vatBasisPoints': vatBasisPoints,
        'defaultPricing': defaultPricing.toJson(),
        'enabled': enabled,
        'checkoutMode': checkoutMode.name,
        'locale': locale,
        'accentColor': accentColor,
        'shippingMinor': shippingMinor,
        'checkoutReturnUrl': checkoutReturnUrl,
        'allowedOrigins': allowedOrigins,
        'shippingCountries': shippingCountries
      };
}

String shopText(Object? value, int max) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw ArgumentError('Invalid text field');
  }
  return value;
}

Uri shopHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  if (value.length > 2048 ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw ArgumentError('Expected a public HTTPS URL');
  }
  return uri;
}
