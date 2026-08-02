import 'pricing_config.dart';

/// Result of running one supplier offer's cost through the pricing pipeline:
/// optional FX → margin → tax → round.
///
/// Production sync stores offers in the **fetched supplier currency**
/// (`rateToShop: 1.0`). Subscribers convert to their target currency client-side.
class OfferPricingResult {
  const OfferPricingResult({required this.stockPriceMinor, required this.finalPriceMinor});

  /// Cost in the working currency (minor units), before margin/tax/rounding.
  final int stockPriceMinor;

  /// Shelf hint after margin, tax, and rounding (same currency as stock).
  final int finalPriceMinor;
}

/// Applies optional FX then margin → tax → rounding. Pure function.
/// Pass [rateToShop] = 1.0 to keep the supplier's fetched currency.
OfferPricingResult computeOfferPricing({
  required int rawPriceMinor,
  required PricingConfig config,
  required double rateToShop,
}) {
  final stockPriceMinor = (rawPriceMinor * rateToShop).round();

  final margin = _computeMargin(stockPriceMinor, config);
  final withMargin = stockPriceMinor + margin;

  final withTax = (withMargin * (1 + config.taxRatePercent / 100)).round();

  final rounded = config.roundingEnabled ? _round(withTax, config) : withTax;

  return OfferPricingResult(stockPriceMinor: stockPriceMinor, finalPriceMinor: rounded);
}

int _computeMargin(int stockPriceMinor, PricingConfig config) {
  final raw = switch (config.marginType) {
    MarginType.fixed => config.marginValueMinor,
    MarginType.percentage => (stockPriceMinor * config.marginValueMinor / 10000).round(),
  };
  if (!config.hasMarginClamp) return raw;
  var clamped = raw;
  if (config.marginMinMinor != 0 && clamped < config.marginMinMinor) clamped = config.marginMinMinor;
  if (config.marginMaxMinor != 0 && clamped > config.marginMaxMinor) clamped = config.marginMaxMinor;
  return clamped;
}

int _round(int priceMinor, PricingConfig config) {
  final step = config.roundingStepMinor;
  if (step <= 0) return priceMinor;
  final quotient = priceMinor / step;
  final rounded = switch (config.roundingMethod) {
    RoundingMethod.ceil => quotient.ceil(),
    RoundingMethod.floor => quotient.floor(),
    RoundingMethod.nearest => quotient.round(),
  };
  return rounded * step;
}
