import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:repairpricer_contract/repairpricer_contract.dart';

/// One pinned publication of one supplier catalog. Retain this across pages so
/// a publication during browsing cannot mix old and new generations.
class ProductCatalogEdition {
  const ProductCatalogEdition(
      {required this.supplierId,
      required this.generation,
      required this.productCount,
      required this.publishedAt});
  final String supplierId;
  final String generation;
  final int productCount;
  final DateTime publishedAt;
  factory ProductCatalogEdition.fromRow(Map<String, dynamic> row) =>
      ProductCatalogEdition(
          supplierId: row['supplier_id'] as String,
          generation: row['generation'] as String,
          productCount: row['product_count'] as int,
          publishedAt: DateTime.parse(row['published_at'] as String));
}

class ProductCatalogPage {
  const ProductCatalogPage(
      {required this.products, required this.edition, this.nextCursor});
  final List<ProductCatalogEntry> products;
  final ProductCatalogEdition edition;
  final String? nextCursor;
}

/// Licensed product-catalog reads, separate from the device/repair catalog.
/// Every call checks the authenticated subscriber team’s product entitlement. This client
/// never falls back to repair data when the module is unavailable.
class ProductCatalogClient {
  ProductCatalogClient(Client client,
      {this.functionId = 'product_catalog_read'})
      : _transport = ((request) async {
          final execution = await Functions(client).createExecution(
              functionId: functionId, body: jsonEncode(request), xasync: false);
          return Map<String, dynamic>.from(
              jsonDecode(execution.responseBody) as Map);
        });
  ProductCatalogClient.withTransport(ShopTransport transport)
      : _transport = transport,
        functionId = 'product_catalog_read';
  final String functionId;
  final ShopTransport _transport;

  Future<Map<String, dynamic>> _call(Map<String, Object?> request) async {
    final response = await _transport(request);
    if (response['ok'] != true) {
      throw ShopException(
          response['error'] as String? ?? 'Product catalog unavailable');
    }
    return response;
  }

  Future<List<ProductCatalogEdition>> listEditions({String? teamId}) async {
    final response = await _call({'action': 'editions', 'teamId': teamId});
    return List.unmodifiable((response['editions'] as List).map((row) =>
        ProductCatalogEdition.fromRow(Map<String, dynamic>.from(row as Map))));
  }

  Future<ProductCatalogPage> listProducts(
      {required ProductCatalogEdition edition,
      String? teamId,
      String? search,
      String? category,
      ProductKind? kind,
      int limit = 50,
      String? cursorAfter}) async {
    if (limit < 1 || limit > 100) throw ArgumentError('limit must be 1–100');
    final response = await _call({
      'action': 'products',
      'teamId': teamId,
      'supplierId': edition.supplierId,
      'generation': edition.generation,
      'search': search,
      'category': category,
      'kind': kind?.name,
      'limit': limit,
      'cursorAfter': cursorAfter,
    });
    final products = (response['products'] as List)
        .map((row) =>
            ProductCatalogEntry.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    if (products.any((p) =>
        p.supplierId != edition.supplierId ||
        p.generation != edition.generation)) {
      throw const FormatException('Product page belongs to another edition');
    }
    return ProductCatalogPage(
        edition: edition,
        products: List.unmodifiable(products),
        nextCursor: response['nextCursor'] as String?);
  }
}

/// Inject the widget transport (HTTP or an Appwrite Function execution). It
/// receives only a public shop key and action-specific public request data.
typedef ShopTransport = Future<Map<String, dynamic>> Function(
    Map<String, Object?> request);
typedef ShopCheckoutHandler<T> = Future<T> Function(
    ShopCheckoutHandoff handoff);

class ShopCheckoutHandoff {
  ShopCheckoutHandoff(
      {required this.widgetKey,
      required List<ShopCartLine> lines,
      required this.quote})
      : lines = List.unmodifiable(lines);
  final String widgetKey;
  final List<ShopCartLine> lines;
  final ShopQuote quote;

  /// Send this to the merchant backend. The quote is deliberately excluded:
  /// the backend obtains a fresh authoritative quote before accepting payment.
  Map<String, Object> toCheckoutRequest() => {
        'widgetKey': widgetKey,
        'lines': lines.map((line) => line.toJson()).toList(),
      };
}

class ShopProductPage {
  const ShopProductPage({required this.products, this.nextCursor});
  final List<ShopProduct> products;
  final String? nextCursor;
}

/// Public retail shop API, independent of subscriber catalog access. Supply an
/// origin-aware transport appropriate for the website hosting the widget.
class ShopClient {
  ShopClient({required this.widgetKey, required ShopTransport transport})
      : _transport = transport {
    if (widgetKey.trim().isEmpty) throw ArgumentError('widgetKey is required');
  }
  final String widgetKey;
  final ShopTransport _transport;

  Future<Map<String, dynamic>> _call(String action,
      [Map<String, Object?> values = const {}]) async {
    final response =
        await _transport({'widgetKey': widgetKey, 'action': action, ...values});
    if (response['ok'] != true) {
      throw ShopException(
          response['error'] as String? ?? 'Shop request failed');
    }
    return response;
  }

  Future<Map<String, dynamic>> loadAppearance() async =>
      Map<String, dynamic>.from((await _call('config'))['appearance'] as Map);

  Future<ShopProductPage> listProducts(
      {String? search,
      String? category,
      int limit = 24,
      String? cursorAfter}) async {
    if (limit < 1 || limit > 100) throw ArgumentError('limit must be 1–100');
    final response = await _call('products', {
      'search': search,
      'category': category,
      'limit': limit,
      'cursorAfter': cursorAfter
    });
    return ShopProductPage(
        products: List.unmodifiable((response['products'] as List).map((row) =>
            ShopProduct.fromJson(Map<String, dynamic>.from(row as Map)))),
        nextCursor: response['nextCursor'] as String?);
  }

  Future<ShopQuote> quote(List<ShopCartLine> lines) async {
    if (lines.isEmpty || lines.length > 100) {
      throw ArgumentError('Cart must have 1–100 lines');
    }
    if (lines.map((line) => line.productId).toSet().length != lines.length) {
      throw ArgumentError('Duplicate cart products');
    }
    final response = await _call(
        'quote', {'lines': lines.map((line) => line.toJson()).toList()});
    final quote =
        ShopQuote.fromJson(Map<String, dynamic>.from(response['quote'] as Map));
    final requested = {for (final line in lines) line.productId: line.quantity};
    if (quote.lines.length != requested.length ||
        quote.lines.any(
            (line) => requested[line.product.productId] != line.quantity)) {
      throw const FormatException('Quote does not match the requested cart');
    }
    if (quote.isExpired(DateTime.now())) {
      throw const ShopException('Quote has expired');
    }
    return quote;
  }

  /// Validates current products/prices, then delegates checkout to the shop.
  /// Calling this does not place a DCS order or collect payment.
  Future<T> checkout<T>(ShopCart cart, ShopCheckoutHandler<T> handler) async {
    final lines = cart.lines;
    final current = await quote(lines);
    return handler(ShopCheckoutHandoff(
        widgetKey: widgetKey, lines: lines, quote: current));
  }
}

class ShopException implements Exception {
  const ShopException(this.message);
  final String message;
  @override
  String toString() => 'ShopException: $message';
}
