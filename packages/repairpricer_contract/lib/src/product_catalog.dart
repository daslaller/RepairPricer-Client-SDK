/// Product identity is independent of repair devices, repairs and tiers.
/// Unknown classification is valid and must not hide a supplier listing.
enum ProductKind {
  component,
  completeDevice,
  accessory,
  consumable,
  softwareService,
  other,
  unknown;

  static ProductKind parse(Object? value) => values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => unknown,
      );
}

enum ProductAvailability {
  inStock,
  outOfStock,
  unknown;

  static ProductAvailability parse(Object? value) => values.firstWhere(
        (status) => status.name == value,
        orElse: () => unknown,
      );
}

/// A licensed subscriber's product listing. This includes sourcing and purchase
/// price information and MUST NOT be serialized into a public shop widget.
/// [modelCode] is supplier text, not verified compatibility or a global MPN.
class ProductCatalogEntry {
  ProductCatalogEntry({
    required this.productId,
    required this.generation,
    required this.supplierId,
    required this.supplierSku,
    required this.title,
    required this.currency,
    required this.vatIncluded,
    required this.observedAt,
    required this.priceContext,
    this.unitPriceMinor,
    this.modelCode,
    this.manufacturer,
    this.category,
    this.kind = ProductKind.unknown,
    this.availability = ProductAvailability.unknown,
    this.quantity,
    this.sourceGeneratedAt,
  }) {
    for (final value in [
      productId,
      generation,
      supplierId,
      supplierSku,
      title,
      priceContext
    ]) {
      if (value.trim().isEmpty) {
        throw ArgumentError('Product identity fields must not be blank');
      }
    }
    validateProductCurrency(currency);
    if (unitPriceMinor != null) validateProductAmount(unitPriceMinor!);
    if (quantity != null && quantity! < 0) {
      throw ArgumentError('Quantity cannot be negative');
    }
  }

  final String productId;
  final String generation;
  final String supplierId;
  final String supplierSku;
  final String title;
  final String? modelCode;
  final String? manufacturer;
  final String? category;
  final ProductKind kind;
  final int? unitPriceMinor;
  final String currency;
  final bool vatIncluded;
  final ProductAvailability availability;
  final int? quantity;
  final DateTime observedAt;
  final DateTime? sourceGeneratedAt;

  /// Non-secret identifier for the supplier account/price basis, not a token.
  final String priceContext;

  factory ProductCatalogEntry.fromJson(Map<String, dynamic> json) =>
      ProductCatalogEntry(
        productId: json['productId'] as String,
        generation: json['generation'] as String,
        supplierId: json['supplierId'] as String,
        supplierSku: json['supplierSku'] as String,
        title: json['title'] as String,
        modelCode: json['modelCode'] as String?,
        manufacturer: json['manufacturer'] as String?,
        category: json['category'] as String?,
        kind: ProductKind.parse(json['kind']),
        unitPriceMinor: json['unitPriceMinor'] as int?,
        currency: json['currency'] as String,
        vatIncluded: json['vatIncluded'] as bool,
        availability: ProductAvailability.parse(json['availability']),
        quantity: json['quantity'] as int?,
        observedAt: DateTime.parse(json['observedAt'] as String),
        sourceGeneratedAt: json['sourceGeneratedAt'] == null
            ? null
            : DateTime.parse(json['sourceGeneratedAt'] as String),
        priceContext: json['priceContext'] as String,
      );

  Map<String, Object?> toJson() => {
        'productId': productId,
        'generation': generation,
        'supplierId': supplierId,
        'supplierSku': supplierSku,
        'title': title,
        'modelCode': modelCode,
        'manufacturer': manufacturer,
        'category': category,
        'kind': kind.name,
        'unitPriceMinor': unitPriceMinor,
        'currency': currency,
        'vatIncluded': vatIncluded,
        'availability': availability.name,
        'quantity': quantity,
        'observedAt': observedAt.toUtc().toIso8601String(),
        'sourceGeneratedAt': sourceGeneratedAt?.toUtc().toIso8601String(),
        'priceContext': priceContext,
      };
}

/// A public, retail-priced product. Deliberately has no supplier, cost, account,
/// margin, raw payload or compatible-device fields.
class ShopProduct {
  ShopProduct({
    required this.productId,
    required this.title,
    required this.priceMinor,
    required this.currency,
    required this.vatIncluded,
    required this.observedAt,
    this.modelCode,
    this.category,
    this.kind = ProductKind.unknown,
    this.availability = ProductAvailability.unknown,
    this.maxQuantity = 1,
    List<String> images = const [],
  }) : images = List.unmodifiable(images) {
    if (productId.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError('Product ID and title are required');
    }
    validateProductCurrency(currency);
    validateProductAmount(priceMinor);
    if (maxQuantity < 0 || maxQuantity > 999) {
      throw ArgumentError('maxQuantity must be between 0 and 999');
    }
    for (final image in images) {
      final uri = Uri.tryParse(image);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw ArgumentError('Product images must use HTTPS');
      }
    }
  }

  final String productId;
  final String title;
  final String? modelCode;
  final String? category;
  final ProductKind kind;
  final int priceMinor;
  final String currency;
  final bool vatIncluded;
  final ProductAvailability availability;
  final DateTime observedAt;

  /// Shop's purchase limit; it is not a claim about supplier inventory quantity.
  final int maxQuantity;
  final List<String> images;
  bool get canAddToCart =>
      availability == ProductAvailability.inStock && maxQuantity > 0;

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
        productId: json['productId'] as String,
        title: json['title'] as String,
        modelCode: json['modelCode'] as String?,
        category: json['category'] as String?,
        kind: ProductKind.parse(json['kind']),
        priceMinor: json['priceMinor'] as int,
        currency: json['currency'] as String,
        vatIncluded: json['vatIncluded'] as bool,
        availability: ProductAvailability.parse(json['availability']),
        observedAt: DateTime.parse(json['observedAt'] as String),
        maxQuantity: json['maxQuantity'] as int? ?? 1,
        images: (json['images'] as List? ?? const []).cast<String>(),
      );

  Map<String, Object?> toJson() => {
        'productId': productId,
        'title': title,
        'modelCode': modelCode,
        'category': category,
        'kind': kind.name,
        'priceMinor': priceMinor,
        'currency': currency,
        'vatIncluded': vatIncluded,
        'availability': availability.name,
        'observedAt': observedAt.toUtc().toIso8601String(),
        'maxQuantity': maxQuantity,
        'images': images,
      };
}

/// Integer minor units that round-trip exactly on Dart VM and JavaScript.
void validateProductAmount(int value) {
  if (value < 0 || value > 9007199254740991) {
    throw ArgumentError('Money must be a non-negative JavaScript-safe integer');
  }
}

void validateProductCurrency(String value) {
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
    throw ArgumentError('Currency must be an uppercase ISO code');
  }
}
