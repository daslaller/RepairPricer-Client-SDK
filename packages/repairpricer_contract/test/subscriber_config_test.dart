import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

void main() {
  group('SubscriberConfig', () {
    test('defaults mirror PricingConfig.defaults in platform mode', () {
      final config = SubscriberConfig.defaults(teamId: 'repairx');
      final base = PricingConfig.defaults();
      expect(config.pricingMode, PricingMode.platform);
      expect(config.strategy, base.strategy);
      expect(config.marginType, base.marginType);
      expect(config.marginValueMinor, base.marginValueMinor);
      expect(config.taxRatePercent, base.taxRatePercent);
      expect(config.roundingMethod, base.roundingMethod);
      expect(config.roundingStepMajor, base.roundingStepMajor);
      expect(config.displayCurrency, base.shopCurrency);
      expect(config.widgetEnabled, isFalse);
    });

    test('fromRow/toRow round-trips', () {
      final row = {
        'team_id': 'repairx',
        'pricing_mode': 'custom',
        'strategy': 'most_expensive',
        'margin_type': 'fixed',
        'margin_value': 5000,
        'margin_min': 1000,
        'margin_max': 20000,
        'tax_rate': 25.0,
        'rounding_enabled': false,
        'rounding_method': 'ceil',
        'rounding_step': 10,
        'display_currency': 'EUR',
        'widget_key': 'abc123',
        'widget_enabled': true,
        'widget_theme': 'dark',
        'widget_accent_color': '#FF0000',
        'widget_locale': 'en',
        'widget_title': 'Repair prices',
        'updated_at': '2026-07-22T10:00:00.000Z',
      };
      final config = SubscriberConfig.fromRow(row);
      expect(config.pricingMode, PricingMode.custom);
      expect(config.strategy, WinnerStrategy.mostExpensive);
      expect(config.marginType, MarginType.fixed);
      expect(config.widgetTheme, WidgetTheme.dark);
      expect(config.updatedAt, DateTime.utc(2026, 7, 22, 10));

      final back = config.toRow();
      for (final key in row.keys) {
        expect(back[key], row[key], reason: 'column $key should round-trip');
      }
    });

    test('fromRow degrades gracefully on missing/unknown optional fields', () {
      final config = SubscriberConfig.fromRow({'team_id': 't1'});
      expect(config.pricingMode, PricingMode.platform);
      expect(config.strategy, WinnerStrategy.cheapest);
      expect(config.widgetTheme, WidgetTheme.auto);
      expect(config.widgetKey, isNull);
      expect(config.updatedAt, isNull);
    });

    test('toPricingConfig feeds the shared pipeline with identical math', () {
      final config = SubscriberConfig.fromRow({
        'team_id': 't1',
        'pricing_mode': 'custom',
        'margin_type': 'percentage',
        'margin_value': 3000, // 30.00%
        'tax_rate': 25.0,
        'rounding_enabled': true,
        'rounding_method': 'nearest',
        'rounding_step': 5,
      });
      final result = computeOfferPricing(
        rawPriceMinor: 10000, // 100 kr cost
        config: config.toPricingConfig(),
        rateToShop: 1.0,
      );
      // 100 kr + 30% = 130 kr, +25% tax = 162.50 kr, round to nearest 5 kr.
      expect(result.finalPriceMinor, 16500);
    });
  });

  group('FilterKind', () {
    test('wire keys and projection columns line up', () {
      expect(FilterKind.fromKey('device_type'), FilterKind.deviceType);
      expect(FilterKind.deviceType.key, 'device_type');
      expect(FilterKind.manufacturer.projectionColumn, 'manufacturer_name');
      expect(FilterKind.device.projectionColumn, 'model_name');
      expect(FilterKind.supplier.projectionColumn, 'supplier_name');
    });
  });

  group('ClientConfigBundle', () {
    final bundle = ClientConfigBundle(
      config: SubscriberConfig.defaults(teamId: 't1'),
      filterRules: const [
        FilterRule(kind: FilterKind.manufacturer, value: 'Huawei'),
        FilterRule(kind: FilterKind.supplier, value: 'ExampleSupplier'),
      ],
      tierNames: const [
        TierNameOverride(tierKey: 'Compatible Budget', en: 'Budget', sv: 'Budget'),
        TierNameOverride(tierKey: 'Official', sv: 'Original'),
      ],
    );

    test('excludes matches only the rule kind and value', () {
      expect(bundle.excludes(FilterKind.manufacturer, 'Huawei'), isTrue);
      expect(bundle.excludes(FilterKind.manufacturer, 'Samsung'), isFalse);
      expect(bundle.excludes(FilterKind.device, 'Huawei'), isFalse);
      expect(bundle.excludes(FilterKind.supplier, 'ExampleSupplier'), isTrue);
      expect(bundle.excludes(FilterKind.supplier, null), isFalse);
    });

    test('tierLabel prefers the requested locale, then en, then fallback', () {
      expect(bundle.tierLabel('Compatible Budget', 'Compatible Budget', locale: 'sv'), 'Budget');
      // 'Official' has only sv — sv locale gets it, en locale falls back to
      // the global name because no en override exists.
      expect(bundle.tierLabel('Official', 'Official', locale: 'sv'), 'Original');
      expect(bundle.tierLabel('Official', 'Official', locale: 'en'), 'Official');
      // No override at all -> global name untouched.
      expect(bundle.tierLabel('Pulled', 'Pulled', locale: 'sv'), 'Pulled');
      expect(bundle.tierLabel(null, 'Refurbished', locale: 'sv'), 'Refurbished');
    });
  });
}
