import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

void main() {
  test('markup and profit margin use different denominators before VAT', () {
    expect(
        ShopPriceRule(mode: ShopPriceMode.markup, value: 2000)
            .price(10000, vatBasisPoints: 2500, vatIncluded: true),
        15000);
    expect(
        ShopPriceRule(mode: ShopPriceMode.margin, value: 2000)
            .price(10000, vatBasisPoints: 2500, vatIncluded: true),
        15625);
  });
  test('fractional totals round up once and fixed prices use display VAT basis',
      () {
    expect(
        ShopPriceRule(mode: ShopPriceMode.markup, value: 1)
            .price(1, vatBasisPoints: 2500, vatIncluded: true),
        2);
    expect(
        ShopPriceRule(mode: ShopPriceMode.fixed, value: 12345)
            .price(10000, vatBasisPoints: 2500, vatIncluded: true),
        12345);
    expect(
        ShopPriceRule().price(10000,
            vatBasisPoints: 0,
            vatIncluded: false,
            defaults: ShopPriceRule(mode: ShopPriceMode.margin, value: 2000)),
        12500);
  });
  test('invalid or overflowing money is refused', () {
    expect(() => ShopPriceRule(mode: ShopPriceMode.margin, value: 10000),
        throwsArgumentError);
    expect(() => ShopPriceRule(mode: ShopPriceMode.markup, value: -1),
        throwsArgumentError);
    expect(
        () => ShopPriceRule().price(10, vatBasisPoints: 0, vatIncluded: false),
        throwsArgumentError);
    expect(
        () => ShopPriceRule(mode: ShopPriceMode.markup, value: 10000)
            .price(9007199254740991, vatBasisPoints: 2500, vatIncluded: true),
        throwsArgumentError);
  });
  test('shop defaults and merchant products round-trip', () {
    final settings = ShopSettings.defaults();
    expect(
        ShopSettings.fromJson(settings.toJson()).toJson(), settings.toJson());
    final product = ManagedShopProduct(
        productId: 'm_keyboard123',
        source: ShopProductSource.own,
        title: 'Keyboard',
        category: 'Accessories',
        kind: ProductKind.accessory,
        enabled: false,
        purchaseLimit: 5,
        pricing: ShopPriceRule(),
        costExVatMinor: 15000,
        stockQuantity: 8);
    expect(ManagedShopProduct.fromJson(product.toJson()).toJson(),
        product.toJson());
  });
  test('supplier stock/cost cannot be set by the merchant', () {
    expect(
        () => ManagedShopProduct(
            productId: 'p123',
            source: ShopProductSource.supplier,
            supplierId: 'dcs',
            supplierSku: '123',
            title: 'Laptop',
            category: 'Devices',
            kind: ProductKind.completeDevice,
            enabled: true,
            purchaseLimit: 5,
            pricing: ShopPriceRule(),
            costExVatMinor: 1),
        throwsArgumentError);
  });
  test('bundles require distinct existing references, not self references', () {
    for (final parts in <List<ShopBundleItem>>[
      [],
      [ShopBundleItem(productId: 'b', quantity: 1)],
      [
        ShopBundleItem(productId: 'p', quantity: 1),
        ShopBundleItem(productId: 'p', quantity: 2)
      ]
    ]) {
      expect(
          () => ManagedShopProduct(
              productId: 'b',
              source: ShopProductSource.bundle,
              title: 'Bundle',
              category: 'Bundles',
              kind: ProductKind.other,
              enabled: true,
              purchaseLimit: 5,
              pricing: ShopPriceRule(),
              components: parts),
          throwsArgumentError);
    }
  });
  test('Stripe mode requires VAT-inclusive prices and an allowed return origin',
      () {
    final json = ShopSettings.defaults().toJson();
    expect(() => ShopSettings.fromJson({...json, 'checkoutMode': 'stripe'}),
        throwsArgumentError);
    expect(
        () => ShopSettings.fromJson({
              ...json,
              'checkoutMode': 'stripe',
              'checkoutReturnUrl': 'https://attacker.example',
              'allowedOrigins': ['https://shop.example']
            }),
        throwsArgumentError);
    expect(
        ShopSettings.fromJson({
          ...json,
          'checkoutMode': 'stripe',
          'checkoutReturnUrl': 'https://shop.example/thanks',
          'allowedOrigins': ['https://shop.example']
        }).checkoutMode,
        ShopCheckoutMode.stripe);
  });
}
