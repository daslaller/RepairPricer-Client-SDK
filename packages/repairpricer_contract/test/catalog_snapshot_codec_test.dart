import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 7, 31, 1, 0);

  Map<String, dynamic> encode() => encodeCatalogSnapshot(
        generatedAt: generatedAt,
        devices: [
          {
            '\$id': 'dev_1', // system field — must NOT survive
            '\$permissions': ['read("label:subscriber")'],
            'device_type_name': 'Mobil',
            'manufacturer_name': 'Samsung',
            'model_name': 'Galaxy Z Fold4',
          },
        ],
        slots: [
          {
            '\$id': 'rp_1',
            'code': 'rp_1',
            'category_path': 'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Speaker',
            'manufacturer_name': 'Samsung',
            'model_name': 'Galaxy Z Fold4',
            'repair_name': 'Speaker',
            'tier_name': 'OEM',
            'cost_price': 1200,
            'winning_price': 1800,
            'currency': 'SEK',
            'in_stock': true,
            'not_a_snapshot_column': 'dropped',
          },
        ],
      );

  test('round-trips through encode/decode', () {
    final data = decodeCatalogSnapshot(encode());
    expect(data.version, catalogSnapshotVersion);
    expect(data.generatedAt, generatedAt);
    expect(data.devices.single['model_name'], 'Galaxy Z Fold4');
    expect(data.slots.single['winning_price'], 1800);
  });

  test('encode strips system fields and non-whitelisted columns', () {
    final doc = encode();
    final device = (doc['devices'] as List).single as Map;
    final slot = (doc['slots'] as List).single as Map;
    expect(device.containsKey('\$id'), isFalse);
    expect(device.containsKey('\$permissions'), isFalse);
    expect(slot.containsKey('not_a_snapshot_column'), isFalse);
    expect(slot['category_path'], contains('Reparation'));
  });

  test('decode rejects a newer version than this reader understands', () {
    final doc = encode()..['version'] = catalogSnapshotVersion + 1;
    expect(() => decodeCatalogSnapshot(doc), throwsFormatException);
  });

  test('decode rejects malformed documents', () {
    expect(() => decodeCatalogSnapshot({}), throwsFormatException);
    expect(
      () => decodeCatalogSnapshot({'version': 1, 'generated_at': 'nope'}),
      throwsFormatException,
    );
    expect(
      () => decodeCatalogSnapshot(
          {'version': 1, 'generated_at': '2026-07-31T01:00:00Z'}),
      throwsFormatException, // missing devices/slots lists
    );
  });

  group('currency rates (additive, non-breaking)', () {
    Map<String, dynamic> withRates() => encodeCatalogSnapshot(
          generatedAt: DateTime.utc(2026, 8, 3),
          devices: const [],
          slots: const [],
          shopCurrency: 'sek',
          rates: const {'eur': 11.3, 'USD': 9.5},
        );

    test('round-trips, upper-casing codes', () {
      final d = decodeCatalogSnapshot(withRates());
      expect(d.shopCurrency, 'SEK');
      expect(d.rates, {'EUR': 11.3, 'USD': 9.5});
    });

    test('an edition WITHOUT rates still decodes — old blobs keep working', () {
      final doc = encodeCatalogSnapshot(
          generatedAt: DateTime.utc(2026, 8, 3), devices: const [], slots: const []);
      expect(doc.containsKey('rates'), isFalse, reason: 'omitted, not empty');
      final d = decodeCatalogSnapshot(doc);
      expect(d.rates, isEmpty);
      expect(d.shopCurrency, '');
    });

    test('a malformed rate is skipped, not fatal', () {
      final doc = withRates()..['rates'] = {'EUR': 11.3, 'GBP': 'nonsense', 'JPY': -1};
      final d = decodeCatalogSnapshot(doc);
      expect(d.rates, {'EUR': 11.3},
          reason: 'a bad FX row must not cost the whole catalog');
    });

    test('converts via the shop currency, both directions', () {
      final r = decodeCatalogSnapshot(withRates()).rates;
      // EUR 2.59 -> SEK
      expect(convertMinor(259, from: 'EUR', to: 'SEK', rates: r, shopCurrency: 'SEK'), 2927);
      // and back
      expect(convertMinor(2927, from: 'SEK', to: 'EUR', rates: r, shopCurrency: 'SEK'), 259);
      // cross pair routes through the shop currency
      expect(rateBetween(from: 'EUR', to: 'USD', rates: r, shopCurrency: 'SEK'),
          closeTo(11.3 / 9.5, 1e-9));
    });

    test('an unknown currency returns null, NEVER 1.0', () {
      final r = decodeCatalogSnapshot(withRates()).rates;
      expect(convertMinor(100, from: 'GBP', to: 'SEK', rates: r, shopCurrency: 'SEK'), isNull);
      expect(rateBetween(from: 'GBP', to: 'SEK', rates: r, shopCurrency: 'SEK'), isNull);
      // Same currency needs no rate.
      expect(convertMinor(100, from: 'GBP', to: 'GBP', rates: r, shopCurrency: 'SEK'), 100);
    });
  });
}
