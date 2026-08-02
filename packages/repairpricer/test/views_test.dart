import 'package:flutter_test/flutter_test.dart';
import 'package:repairpricer/repairpricer.dart';

/// Pure-level coverage of the view models the SDK's network reads produce.
/// The `RepairPricerClient` methods are thin wrappers: read rows → `fromRow`
/// → (`applyClientConfig` / `selectWinner`). Exercising the mapping and the
/// config application here proves that pipeline without a live Appwrite.
void main() {
  group('CatalogSlotView.fromRow', () {
    test('maps a projection row, defaulting missing fields', () {
      final view = CatalogSlotView.fromRow(const {
        'code': 'rp-1',
        'model_name': 'iPhone 13',
        'repair_name': 'Screen',
        'tier_name': 'OEM',
        'tier_key': 'oem',
        'cost_price': 1200,
        'winning_price': 1800,
        'in_stock': true,
        'verification_status': 'verified',
      });
      expect(view.code, 'rp-1');
      expect(view.modelName, 'iPhone 13');
      expect(view.costPriceMinor, 1200);
      expect(view.winningPriceMinor, 1800);
      expect(view.currency, 'SEK'); // default
      expect(view.verificationStatus, VerificationStatus.verified);
      expect(view.verificationBadge, 'Verified');
    });
  });

  group('applyClientConfig', () {
    CatalogSlotView slot() => CatalogSlotView.fromRow(const {
          'code': 'rp-1',
          'model_name': 'iPhone 13',
          'tier_name': 'OEM',
          'tier_key': 'oem',
          'cost_price': 1000,
          'winning_price': 1800,
          'in_stock': true,
        });

    test('platform mode relabels the tier but leaves displayPrice null', () {
      final bundle = ClientConfigBundle(
        config: SubscriberConfig.defaults(teamId: 't1'), // platform mode
        tierNames: const [TierNameOverride(tierKey: 'oem', sv: 'Original-del')],
      );
      final view = slot().applyClientConfig(bundle, locale: 'sv');
      expect(view.displayTierName, 'Original-del');
      expect(view.displayPriceMinor, isNull); // use winningPriceMinor
    });

    test('custom mode runs the subscriber margin pipeline over cost', () {
      final base = SubscriberConfig.defaults(teamId: 't1');
      final custom = SubscriberConfig(
        teamId: base.teamId,
        pricingMode: PricingMode.custom,
        strategy: base.strategy,
        marginType: MarginType.percentage,
        marginValueMinor: 2000, // 20%
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: false,
        roundingMethod: base.roundingMethod,
        roundingStepMajor: base.roundingStepMajor,
        displayCurrency: 'SEK',
      );
      final view = slot().applyClientConfig(ClientConfigBundle(config: custom), locale: 'sv');
      expect(view.displayPriceMinor, 1200); // 1000 + 20%
    });
  });

  group('mocked read → winner selection', () {
    // Canned rows exactly as `TablesDB.listRows(offer_projection)` would return
    // them; the SDK maps each with OfferView.fromRow then runs selectWinner —
    // the body of winnerForSlot, minus the network hop.
    final offerRows = <Map<String, dynamic>>[
      {'code': 'rp-1', 'offer_id': 'o1', 'supplier_name': 'supplier-a', 'cost_price': 1500, 'in_stock': true},
      {'code': 'rp-1', 'offer_id': 'o2', 'supplier_name': 'supplier-b', 'cost_price': 900, 'in_stock': false},
      {'code': 'rp-1', 'offer_id': 'o3', 'supplier_name': 'supplier-c', 'cost_price': 1100, 'in_stock': true},
    ];

    OfferView? pickWinner(Iterable<Map<String, dynamic>> rows, WinnerStrategy strategy, {Set<String> excludeSuppliers = const {}}) {
      final offers = [
        for (final row in rows)
          if (!excludeSuppliers.contains(row['supplier_name'])) OfferView.fromRow(row),
      ];
      if (offers.isEmpty) return null;
      final byId = {for (final o in offers) o.offerId: o};
      final winner = selectWinner(
        [for (final o in offers) WinnerCandidate(offerId: o.offerId, stockPriceMinor: o.costPriceMinor, inStock: o.inStock)],
        strategy,
      );
      return winner == null ? null : byId[winner.offerId];
    }

    test('cheapest picks the lowest in-stock offer', () {
      expect(pickWinner(offerRows, WinnerStrategy.cheapest)?.offerId, 'o3');
    });

    test('supplier exclusion removes a candidate before selection', () {
      final winner = pickWinner(offerRows, WinnerStrategy.cheapest, excludeSuppliers: {'supplier-c'});
      expect(winner?.offerId, 'o1'); // o3 excluded, o2 out of stock → o1
    });
  });

  group('RepairPricerDevice + TranslationDictionary', () {
    test('device projection row maps', () {
      final device = RepairPricerDevice.fromRow(const {
        'manufacturer_name': 'Apple',
        'model_name': 'iPhone 13',
        'device_type_name': 'Mobiltelefon',
      });
      expect(device.manufacturerName, 'Apple');
      expect(device.modelName, 'iPhone 13');
    });

    test('translation falls back locale → fallbackLocale → key', () {
      final dict = TranslationDictionary.fromRows(const [
        {'namespace': 'part_type', 'key': 'display', 'en': 'Display', 'sv': 'Skärm'},
        {'namespace': 'part_type', 'key': 'battery', 'en': 'Battery'},
      ]);
      expect(dict.label('part_type', 'display', locale: 'sv'), 'Skärm');
      expect(dict.label('part_type', 'battery', locale: 'sv'), 'Battery'); // fallback en
      expect(dict.label('part_type', 'unknown', locale: 'sv'), 'unknown'); // key
    });
  });
}
