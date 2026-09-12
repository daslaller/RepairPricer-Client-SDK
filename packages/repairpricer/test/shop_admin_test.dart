import 'package:flutter_test/flutter_test.dart';
import 'package:repairpricer/repairpricer.dart';

void main() {
  test(
      'management sends the explicit team and revision with shared contract fields',
      () async {
    Map<String, Object?>? body;
    final client = ShopAdminClient.withTransport((request) async {
      body = request;
      return {'ok': true};
    });
    await client.saveSettings(ShopSettings.defaults(),
        teamId: 'team', revision: 4);
    expect(body!['action'], 'saveSettings');
    expect(body!['revision'], 4);
    expect(body!['teamId'], 'team');
    expect((body!['settings'] as Map)['defaultPricing'],
        {'mode': 'markup', 'value': 2000});
    await client.connectStripe(teamId: 'team');
    expect(body!['action'], 'connectStripe');
    expect(body!.keys, isNot(contains('secretKey')));
  });
  test('permission and stale-edit errors are surfaced without local success',
      () async {
    final client = ShopAdminClient.withTransport(
        (_) async => {'ok': false, 'error': 'Reload before saving'});
    await expectLater(client.saveSettings(ShopSettings.defaults(), revision: 1),
        throwsA(isA<ShopException>()));
  });
  test(
      'Stripe handoff carries identities, expected total and retry identity only',
      () async {
    Map<String, Object?>? sent;
    final shop = ShopClient(
        widgetKey: 'shop',
        transport: (body) async {
          sent = body;
          return {'ok': true, 'url': 'https://checkout.stripe.com/c/pay/test'};
        });
    final uri = await shop.stripeCheckout(
        [ShopCartLine(productId: 'p1', quantity: 2)],
        requestId: 'checkout_attempt_123', expectedSubtotalMinor: 15000);
    expect(uri.host, 'checkout.stripe.com');
    expect(sent!['action'], 'checkout');
    expect(sent!['lines'], [
      {'productId': 'p1', 'quantity': 2}
    ]);
    expect(sent!['requestId'], 'checkout_attempt_123');
    expect(sent!.keys, isNot(contains('accountId')));
  });
  test('Stripe handoff rejects redirection to another host', () async {
    final shop = ShopClient(
        widgetKey: 'shop',
        transport: (_) async =>
            {'ok': true, 'url': 'https://bad.example/checkout'});
    await expectLater(
        shop.stripeCheckout([ShopCartLine(productId: 'p1', quantity: 1)],
            requestId: 'checkout_attempt_123', expectedSubtotalMinor: 100),
        throwsA(isA<ShopException>()));
  });
  test('finished checkout tells the caller when to start a new attempt',
      () async {
    final shop = ShopClient(
        widgetKey: 'shop',
        transport: (_) async => {
              'ok': false,
              'error': 'Review your cart',
              'resetCheckout': true,
            });
    await expectLater(
        shop.stripeCheckout([ShopCartLine(productId: 'p1', quantity: 1)],
            requestId: 'checkout_attempt_123', expectedSubtotalMinor: 100),
        throwsA(isA<ShopException>()
            .having((e) => e.resetCheckout, 'resetCheckout', true)));
  });
}
