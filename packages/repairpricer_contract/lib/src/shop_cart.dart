import 'product_catalog.dart';

/// Only identities and quantities cross the checkout request boundary. Retail
/// totals must be re-established by the server, never accepted from this cart.
class ShopCartLine {
  ShopCartLine({required this.productId, required this.quantity}) {
    if (productId.trim().isEmpty || quantity < 1 || quantity > 999) {
      throw ArgumentError('A cart line needs a product ID and quantity 1–999');
    }
  }
  final String productId;
  final int quantity;
  factory ShopCartLine.fromJson(Map<String, dynamic> json) => ShopCartLine(
      productId: json['productId'] as String,
      quantity: json['quantity'] as int);
  Map<String, Object> toJson() =>
      {'productId': productId, 'quantity': quantity};
}

/// Local cart state for a shop. Totals are estimates until a server quote is
/// returned. Distinct product IDs preserve capacity, generation and condition.
class ShopCart {
  final Map<String, ShopProduct> _products = {};
  final Map<String, int> _quantities = {};
  String? get currency => _products.values.firstOrNull?.currency;
  bool get isEmpty => _quantities.isEmpty;
  List<ShopCartLine> get lines => List.unmodifiable([
        for (final entry in _quantities.entries)
          ShopCartLine(productId: entry.key, quantity: entry.value),
      ]);

  int get estimatedSubtotalMinor {
    var total = 0;
    for (final entry in _quantities.entries) {
      total += _products[entry.key]!.priceMinor * entry.value;
      validateProductAmount(total);
    }
    return total;
  }

  void add(ShopProduct product, {int quantity = 1}) {
    if (quantity < 1) throw ArgumentError('Added quantity must be positive');
    setQuantity(product, (_quantities[product.productId] ?? 0) + quantity);
  }

  void setQuantity(ShopProduct product, int quantity) {
    if (quantity == 0) {
      remove(product.productId);
      return;
    }
    if (!product.canAddToCart ||
        quantity < 0 ||
        quantity > product.maxQuantity) {
      throw ArgumentError(
          'Product is unavailable or quantity exceeds its limit');
    }
    if (currency != null && currency != product.currency) {
      throw ArgumentError('A cart cannot mix currencies');
    }
    final current = _products.values.firstOrNull;
    if (current != null && current.vatIncluded != product.vatIncluded) {
      throw ArgumentError('A cart cannot mix VAT display bases');
    }
    var newTotal = product.priceMinor * quantity;
    for (final entry in _quantities.entries) {
      if (entry.key != product.productId) {
        newTotal += _products[entry.key]!.priceMinor * entry.value;
      }
    }
    validateProductAmount(newTotal);
    _products[product.productId] = product;
    _quantities[product.productId] = quantity;
  }

  void remove(String productId) {
    _products.remove(productId);
    _quantities.remove(productId);
  }

  void clear() {
    _products.clear();
    _quantities.clear();
  }
}

class ShopQuoteLine {
  ShopQuoteLine({required this.product, required this.quantity}) {
    if (quantity < 1 ||
        quantity > product.maxQuantity ||
        !product.canAddToCart) {
      throw ArgumentError('Invalid quoted quantity');
    }
    validateProductAmount(totalMinor);
  }
  final ShopProduct product;
  final int quantity;
  int get totalMinor => product.priceMinor * quantity;
  factory ShopQuoteLine.fromJson(Map<String, dynamic> json) {
    final line = ShopQuoteLine(
        product: ShopProduct.fromJson(
            Map<String, dynamic>.from(json['product'] as Map)),
        quantity: json['quantity'] as int);
    if (json['totalMinor'] != line.totalMinor) {
      throw const FormatException('Inconsistent quote line total');
    }
    return line;
  }
  Map<String, Object> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        'totalMinor': totalMinor
      };
}

/// Server-validated merchandise subtotal. Shipping/payment belong to checkout;
/// this is neither a paid order nor a supplier reservation.
class ShopQuote {
  ShopQuote({required List<ShopQuoteLine> lines, required this.expiresAt})
      : lines = List.unmodifiable(lines) {
    if (lines.isEmpty || lines.length > 100) {
      throw ArgumentError('Quote must have 1–100 lines');
    }
    if (lines.map((line) => line.product.productId).toSet().length !=
        lines.length) {
      throw ArgumentError('Duplicate quote products');
    }
    if (lines.any((line) =>
        line.product.currency != currency ||
        line.product.vatIncluded != vatIncluded)) {
      throw ArgumentError('Quote has inconsistent currency or VAT basis');
    }
    validateProductAmount(subtotalMinor);
  }
  final List<ShopQuoteLine> lines;
  final DateTime expiresAt;
  String get currency => lines.first.product.currency;
  bool get vatIncluded => lines.first.product.vatIncluded;
  int get subtotalMinor =>
      lines.fold(0, (total, line) => total + line.totalMinor);
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  factory ShopQuote.fromJson(Map<String, dynamic> json) {
    final quote = ShopQuote(
        lines: (json['lines'] as List)
            .map((line) =>
                ShopQuoteLine.fromJson(Map<String, dynamic>.from(line as Map)))
            .toList(),
        expiresAt: DateTime.parse(json['expiresAt'] as String));
    if (json['subtotalMinor'] != quote.subtotalMinor ||
        json['currency'] != quote.currency ||
        json['vatIncluded'] != quote.vatIncluded) {
      throw const FormatException('Inconsistent quote totals');
    }
    return quote;
  }
  Map<String, Object> toJson() => {
        'lines': lines.map((line) => line.toJson()).toList(),
        'subtotalMinor': subtotalMinor,
        'currency': currency,
        'vatIncluded': vatIncluded,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };
}
