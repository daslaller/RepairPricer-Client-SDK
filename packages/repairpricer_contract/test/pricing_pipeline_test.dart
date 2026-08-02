import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

void main() {
  group('computeOfferPricing', () {
    test('same-currency, percentage margin, no tax, rounds to nearest 5', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.percentage,
        marginValueMinor: 2000, // 20.00%
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: true,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      // 100.00 SEK cost, 20% margin -> 120.00, rounded to nearest 5 -> 120.00.
      final result = computeOfferPricing(rawPriceMinor: 10000, config: config, rateToShop: 1.0);

      expect(result.stockPriceMinor, 10000);
      expect(result.finalPriceMinor, 12000);
    });

    test('converts currency before applying margin', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.fixed,
        marginValueMinor: 0,
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: false,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      // 9.19 EUR at rate 11.0 -> 101.09 SEK, no margin/tax/rounding.
      final result = computeOfferPricing(rawPriceMinor: 919, config: config, rateToShop: 11.0);

      expect(result.stockPriceMinor, 10109);
      expect(result.finalPriceMinor, 10109);
    });

    test('fixed margin adds a flat amount regardless of cost', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.fixed,
        marginValueMinor: 1500, // 15.00 flat
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: false,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      final result = computeOfferPricing(rawPriceMinor: 10000, config: config, rateToShop: 1.0);

      expect(result.finalPriceMinor, 11500);
    });

    test('percentage margin is clamped to margin_max', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.percentage,
        marginValueMinor: 5000, // 50% -> would be 500.00 margin on 1000.00 cost
        marginMinMinor: 0,
        marginMaxMinor: 20000, // clamp margin to at most 200.00
        taxRatePercent: 0,
        roundingEnabled: false,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      final result = computeOfferPricing(rawPriceMinor: 100000, config: config, rateToShop: 1.0);

      // Uncapped margin would be 50000 (500.00); clamp caps it at 20000 (200.00).
      expect(result.finalPriceMinor, 100000 + 20000);
    });

    test('percentage margin is clamped to margin_min', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.percentage,
        marginValueMinor: 500, // 5%
        marginMinMinor: 3000, // floor the margin at 30.00
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: false,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      final result = computeOfferPricing(rawPriceMinor: 10000, config: config, rateToShop: 1.0);

      // Uncapped margin would be 500 (5.00); floor raises it to 3000 (30.00).
      expect(result.finalPriceMinor, 10000 + 3000);
    });

    test('applies tax after margin', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.fixed,
        marginValueMinor: 0,
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 25,
        roundingEnabled: false,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      final result = computeOfferPricing(rawPriceMinor: 10000, config: config, rateToShop: 1.0);

      expect(result.finalPriceMinor, 12500);
    });

    test('rounding: ceil to nearest step', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.fixed,
        marginValueMinor: 0,
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: true,
        roundingMethod: RoundingMethod.ceil,
        roundingStepMajor: 5,
        shopCurrency: 'SEK',
      );

      // 92.63 -> ceil to nearest 5 -> 95.00, matching the handoff doc's own example.
      final result = computeOfferPricing(rawPriceMinor: 9263, config: config, rateToShop: 1.0);

      expect(result.finalPriceMinor, 9500);
    });

    test('rounding: floor to nearest step', () {
      const config = PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.fixed,
        marginValueMinor: 0,
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: true,
        roundingMethod: RoundingMethod.floor,
        roundingStepMajor: 10,
        shopCurrency: 'SEK',
      );

      // 98.99, floor to the nearest 10 kr -> 90.00.
      final result = computeOfferPricing(rawPriceMinor: 9899, config: config, rateToShop: 1.0);

      expect(result.finalPriceMinor, 9000);
    });
  });
}
