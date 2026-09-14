import 'package:flutter_test/flutter_test.dart';
import 'package:repairpricer/repairpricer.dart';

final p = ShopProduct(
    productId: 'p_1',
    title: 'Laptop',
    priceMinor: 10000,
    currency: 'SEK',
    vatIncluded: true,
    observedAt: DateTime.now(),
    availability: ProductAvailability.inStock,
    maxQuantity: 3);
Map<String, dynamic> quoteResponse({String? productId}) {
  final product = productId == null
      ? p
      : ShopProduct.fromJson({...p.toJson(), 'productId': productId});
  return {
    'ok': true,
    'quote': ShopQuote(
            lines: [ShopQuoteLine(product: product, quantity: 1)],
            expiresAt: DateTime.now().add(const Duration(minutes: 10)))
        .toJson()
  };
}

void main() {
  test('SDK checkout invokes merchant handler with an unpriced request',
      () async {
    final calls = <Map<String, Object?>>[];
    final client = ShopClient(
        widgetKey: 'shop',
        transport: (request) async {
          calls.add(request);
          return quoteResponse();
        });
    final cart = ShopCart()..add(p);
    final result = await client.checkout(cart, (handoff) async {
      expect(handoff.toCheckoutRequest(), {
        'widgetKey': 'shop',
        'lines': [
          {'productId': 'p_1', 'quantity': 1}
        ]
      });
      expect(handoff.quote.subtotalMinor, 10000);
      return 'merchant-checkout';
    });
    expect(result, 'merchant-checkout');
    expect(calls.single['action'], 'quote');
  });
  test('SDK rejects a quote for another product before calling merchant',
      () async {
    final client = ShopClient(
        widgetKey: 'shop',
        transport: (_) async => quoteResponse(productId: 'another'));
    bool called = false;
    await expectLater(
        client.checkout(ShopCart()..add(p), (_) async {
          called = true;
        }),
        throwsFormatException);
    expect(called, false);
  });
  test('catalog paging pins edition and propagates subscription denial',
      () async {
    Map<String, Object?>? sent;
    final client = ProductCatalogClient.withTransport((request) async {
      sent = request;
      return {'ok': true, 'products': [], 'nextCursor': null};
    });
    final edition = ProductCatalogEdition(
        supplierId: 'dcs',
        generation: 'g1',
        productCount: 1,
        publishedAt: DateTime.now());
    final page = await client.listProducts(
        edition: edition, teamId: 'team', cursorAfter: 'cursor');
    expect(sent!['generation'], 'g1');
    expect(sent!['teamId'], 'team');
    expect(sent!['cursorAfter'], 'cursor');
    expect(page.edition, edition);
    final denied = ProductCatalogClient.withTransport(
        (_) async => {'ok': false, 'error': 'Subscription required'});
    await expectLater(denied.listEditions(), throwsA(isA<ShopException>()));
  });
  test('catalog refuses mixed generations from transport', () async {
    final entry = ProductCatalogEntry(
        productId: 'a',
        generation: 'wrong',
        supplierId: 'dcs',
        supplierSku: '1',
        title: 'Laptop',
        currency: 'SEK',
        vatIncluded: false,
        observedAt: DateTime.now(),
        priceContext: 'account');
    final client = ProductCatalogClient.withTransport((_) async => {
          'ok': true,
          'products': [entry.toJson()]
        });
    await expectLater(
        client.listProducts(
            edition: ProductCatalogEdition(
                supplierId: 'dcs',
                generation: 'g1',
                productCount: 1,
                publishedAt: DateTime.now())),
        throwsFormatException);
  });
}
