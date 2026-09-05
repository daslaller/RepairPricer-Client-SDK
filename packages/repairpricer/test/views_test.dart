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

    // The catalog is mixed-currency: rows carry the WINNING SUPPLIER's
    // currency. Before this, applying a config relabelled a EUR row as SEK
    // and left the number alone — ~11x too cheap.
    group('currency conversion', () {
      // €1 = 11.5 SEK, $1 = 10.5 SEK.
      const shop = 'SEK';
      const rates = {'EUR': 11.5, 'USD': 10.5};

      CatalogSlotView eurSlot() => CatalogSlotView.fromRow(const {
            'code': 'rp-eur',
            'model_name': 'iPhone 13',
            'tier_name': 'OEM',
            'tier_key': 'oem',
            'cost_price': 10000, // €100.00
            'winning_price': 12000, // €120.00
            'final_price_to_customer': 20000,
            'suggested_service_fee': 8000,
            'currency': 'EUR',
            'in_stock': true,
          });

      ClientConfigBundle sekBundle({PricingMode mode = PricingMode.platform}) {
        final base = SubscriberConfig.defaults(teamId: 't1');
        return ClientConfigBundle(
          config: SubscriberConfig(
            teamId: base.teamId,
            pricingMode: mode,
            strategy: base.strategy,
            marginType: MarginType.percentage,
            marginValueMinor: 2000, // 20%
            marginMinMinor: 0,
            marginMaxMinor: 0,
            taxRatePercent: 0,
            roundingEnabled: false,
            roundingMethod: base.roundingMethod,
            roundingStepMajor: base.roundingStepMajor,
            displayCurrency: shop,
          ),
        ).withRates(shopCurrency: shop, rates: rates);
      }

      test('a bundle with no rates does not convert — unchanged behaviour', () {
        final plain = ClientConfigBundle(config: SubscriberConfig.defaults(teamId: 't1'));
        expect(plain.canConvert, isFalse);
        final view = eurSlot().applyClientConfig(plain, locale: 'sv');
        expect(view.currency, 'EUR', reason: 'no rates: nothing is restated');
        expect(view.winningPriceMinor, 12000);
        expect(view.displayPriceMinor, isNull);
        expect(view.displayPriceUnavailable, isFalse);
      });

      test('platform mode restates every money field and the label together', () {
        final view = eurSlot().applyClientConfig(sekBundle(), locale: 'sv');
        expect(view.currency, 'SEK');
        expect(view.costPriceMinor, (10000 * 11.5).round());
        expect(view.winningPriceMinor, (12000 * 11.5).round());
        expect(view.finalPriceToCustomerMinor, (20000 * 11.5).round());
        expect(view.suggestedServiceFeeMinor, (8000 * 11.5).round());
        expect(view.displayPriceMinor, (12000 * 11.5).round());
        expect(view.displayCurrency, 'SEK');
        expect(view.displayPriceUnavailable, isFalse);
      });

      test('custom mode converts BEFORE the margin pipeline', () {
        final view = eurSlot().applyClientConfig(
          sekBundle(mode: PricingMode.custom),
          locale: 'sv',
        );
        // €100 -> 1150 SEK, then +20% = 1380 SEK. Applying the margin first
        // and converting after would round in the wrong currency.
        expect(view.displayPriceMinor, 138000);
        expect(view.currency, 'SEK');
      });

      test('a missing rate flags unavailable rather than showing the raw number', () {
        final gbpSlot = CatalogSlotView.fromRow(const {
          'code': 'rp-gbp',
          'model_name': 'iPhone 13',
          'tier_name': 'OEM',
          'cost_price': 10000,
          'winning_price': 12000,
          'currency': 'GBP', // no rate
          'in_stock': true,
        });
        final view = gbpSlot.applyClientConfig(sekBundle(), locale: 'sv');
        expect(view.displayPriceUnavailable, isTrue);
        expect(view.displayPriceMinor, isNull);
        expect(view.currency, 'GBP', reason: 'left honest, not relabelled');
        expect(view.displayCurrency, 'SEK');
      });

      // A rate that EXISTS but is weeks old is the one wrong number the
      // null-never-1.0 rule cannot catch: it converts, confidently, at a
      // price that stopped being true. Refused, exactly like a missing rate.
      group('staleness', () {
        ClientConfigBundle aged(DateTime? asOf, {Duration? maxAge = defaultMaxRateAge}) =>
            ClientConfigBundle(config: SubscriberConfig.defaults(teamId: 't1')).withRates(
              shopCurrency: shop,
              rates: rates,
              asOf: asOf,
              maxAge: maxAge,
            );

        test('fresh rates convert normally', () {
          final bundle = aged(DateTime.now().toUtc().subtract(const Duration(days: 2)));
          expect(bundle.ratesAreStale(), isFalse);
          final view = eurSlot().applyClientConfig(bundle, locale: 'sv');
          expect(view.currency, 'SEK');
          expect(view.displayPriceUnavailable, isFalse);
        });

        test('rates past the max age are refused, not used', () {
          final bundle = aged(DateTime.now().toUtc().subtract(const Duration(days: 30)));
          expect(bundle.ratesAreStale(), isTrue);
          final view = eurSlot().applyClientConfig(bundle, locale: 'sv');
          expect(view.displayPriceUnavailable, isTrue);
          expect(view.displayPriceMinor, isNull);
          expect(view.currency, 'EUR', reason: 'left honest, not converted at a stale rate');
        });

        // The migration path: a snapshot published before the platform
        // recorded a feed date still converts, rather than every subscriber
        // on an older edition losing every price at once.
        test('an unknown rate date leaves the rule inapplicable', () {
          final bundle = aged(null);
          expect(bundle.ratesAreStale(), isFalse);
          expect(eurSlot().applyClientConfig(bundle, locale: 'sv').currency, 'SEK');
        });

        test('maxAge: null accepts rates of any age', () {
          final bundle = aged(DateTime.utc(2020), maxAge: null);
          expect(bundle.ratesAreStale(), isFalse);
          expect(eurSlot().applyClientConfig(bundle, locale: 'sv').currency, 'SEK');
        });

        test('staleness is not the same as having no rates', () {
          // No rates: do not convert, leave prices alone (pre-conversion
          // behaviour). Stale rates: refuse, and say so.
          final none = ClientConfigBundle(config: SubscriberConfig.defaults(teamId: 't1'));
          expect(none.canConvert, isFalse);
          expect(none.ratesAreStale(), isFalse);
          expect(eurSlot().applyClientConfig(none, locale: 'sv').displayPriceUnavailable, isFalse);

          final stale = aged(DateTime.utc(2020));
          expect(stale.canConvert, isTrue);
          expect(stale.ratesAreStale(), isTrue);
        });

        test('withRates defaults to the shared max age', () {
          final bundle = ClientConfigBundle(config: SubscriberConfig.defaults(teamId: 't1'))
              .withRates(shopCurrency: shop, rates: rates, asOf: DateTime.now().toUtc());
          expect(bundle.maxRateAge, defaultMaxRateAge);
        });
      });

      test('a same-currency row is untouched and adds no display price', () {
        final sekSlot = CatalogSlotView.fromRow(const {
          'code': 'rp-sek',
          'model_name': 'iPhone 13',
          'tier_name': 'OEM',
          'cost_price': 10000,
          'winning_price': 12000,
          'currency': 'SEK',
          'in_stock': true,
        });
        final view = sekSlot.applyClientConfig(sekBundle(), locale: 'sv');
        expect(view.winningPriceMinor, 12000);
        expect(view.displayPriceMinor, isNull,
            reason: 'platform mode with nothing to convert: winningPriceMinor IS the price');
        expect(view.displayPriceUnavailable, isFalse);
      });

      test('re-applying a config does not keep a stale display price', () {
        final once = eurSlot().applyClientConfig(sekBundle(mode: PricingMode.custom), locale: 'sv');
        expect(once.displayPriceMinor, isNotNull);
        // Now already in SEK, platform mode: nothing to convert, so the
        // display price must be cleared rather than carried over.
        final twice = once.applyClientConfig(sekBundle(), locale: 'sv');
        expect(twice.displayPriceMinor, isNull);
      });

      group('inCurrency', () {
        test('routes a cross pair through the shop currency', () {
          final usd = eurSlot().inCurrency('USD', rates: rates, shopCurrency: shop);
          // €100 -> 1150 SEK -> $109.52
          expect(usd!.costPriceMinor, (10000 * 11.5 / 10.5).round());
          expect(usd.currency, 'USD');
        });

        test('is null, never 1.0, when a leg has no rate', () {
          expect(eurSlot().inCurrency('GBP', rates: rates, shopCurrency: shop), isNull);
          expect(eurSlot().inCurrency('', rates: rates, shopCurrency: shop), isNull);
        });

        test('same currency returns the row itself', () {
          final slot = eurSlot();
          expect(identical(slot.inCurrency('eur', rates: rates, shopCurrency: shop), slot), isTrue);
        });
      });
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
