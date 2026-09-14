import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

ShopProduct product(String id,
        {int amount = 12345,
        String currency = 'SEK',
        bool vat = true,
        ProductAvailability stock = ProductAvailability.inStock,
        int cap = 5}) =>
    ShopProduct(
        productId: id,
        title: 'Laptop variant $id',
        modelCode: 'shared',
        priceMinor: amount,
        currency: currency,
        vatIncluded: vat,
        observedAt: DateTime.utc(2026),
        availability: stock,
        maxQuantity: cap);

void main() {
  test('cart keeps variants independent and sends only identity and quantity',
      () {
    final cart = ShopCart()
      ..add(product('16GB'))
      ..add(product('32GB'), quantity: 2);
    expect(cart.lines.map((l) => l.toJson()), [
      {'productId': '16GB', 'quantity': 1},
      {'productId': '32GB', 'quantity': 2}
    ]);
    expect(cart.estimatedSubtotalMinor, 37035);
    cart.remove('16GB');
    expect(cart.lines.length, 1);
    cart.clear();
    expect(cart.isEmpty, true);
  });
  test(
      'cart refuses unavailable, fractional JSON quantities, mixed money and overflow',
      () {
    final cart = ShopCart()..add(product('a'));
    for (final p in [
      product('b', currency: 'EUR'),
      product('b', vat: false),
      product('b', stock: ProductAvailability.unknown)
    ]) {
      expect(() => cart.add(p), throwsArgumentError);
    }
    expect(() => cart.add(product('a'), quantity: 6), throwsArgumentError);
    expect(() => ShopCartLine.fromJson({'productId': 'a', 'quantity': 1.5}),
        throwsA(isA<TypeError>()));
    expect(
        () => ShopCart()
            .add(product('big', amount: 9007199254740991), quantity: 2),
        throwsArgumentError);
    expect(cart.estimatedSubtotalMinor, 12345);
  });
  test('quote rejects tampered line totals, aggregate and duplicate identities',
      () {
    final quote = ShopQuote(
        lines: [ShopQuoteLine(product: product('a'), quantity: 2)],
        expiresAt: DateTime.utc(2030));
    expect(ShopQuote.fromJson(quote.toJson()).subtotalMinor, 24690);
    expect(() => ShopQuote.fromJson({...quote.toJson(), 'subtotalMinor': 1}),
        throwsFormatException);
    final line = quote.lines.single.toJson();
    expect(
        () => ShopQuote.fromJson({
              ...quote.toJson(),
              'lines': [
                {...line, 'totalMinor': 1}
              ]
            }),
        throwsFormatException);
    expect(
        () => ShopQuote(
            lines: [quote.lines.single, quote.lines.single],
            expiresAt: DateTime.utc(2030)),
        throwsArgumentError);
    expect(quote.isExpired(DateTime.utc(2030)), true);
  });
  test(
      'unknown future kinds and availability fail safely and public JSON has no source fields',
      () {
    final json = product('a').toJson();
    final decoded = ShopProduct.fromJson({
      ...json,
      'kind': 'future-kind',
      'availability': 'new-status',
      'supplierId': 'private',
      'unitPriceMinor': 1
    });
    expect(decoded.kind, ProductKind.unknown);
    expect(decoded.canAddToCart, false);
    expect(decoded.toJson().containsKey('supplierId'), false);
    expect(decoded.toJson().containsKey('unitPriceMinor'), false);
  });
  test(
      'catalog serialization preserves SKU, generation, unknown identity and VAT',
      () {
    final entry = ProductCatalogEntry(
        productId: 'a',
        generation: 'edition',
        supplierId: 'source',
        supplierSku: '123',
        title: 'A',
        currency: 'SEK',
        vatIncluded: false,
        observedAt: DateTime.utc(2026),
        priceContext: 'account');
    final decoded = ProductCatalogEntry.fromJson(entry.toJson());
    expect(decoded.toJson(), entry.toJson());
    expect(decoded.modelCode, null);
    expect(decoded.quantity, null);
    expect(decoded.unitPriceMinor, null);
    expect(decoded.kind, ProductKind.unknown);
  });
}
