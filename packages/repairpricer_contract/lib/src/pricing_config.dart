/// How a slot's winning offer is chosen among its competing supplier offers.
enum WinnerStrategy {
  cheapest,
  mostExpensive,
  average;

  static WinnerStrategy fromKey(String key) {
    switch (key) {
      case 'cheapest':
        return WinnerStrategy.cheapest;
      case 'most_expensive':
        return WinnerStrategy.mostExpensive;
      case 'average':
        return WinnerStrategy.average;
      default:
        throw ArgumentError.value(key, 'key', 'Unknown winner strategy');
    }
  }

  String get key => switch (this) {
        WinnerStrategy.cheapest => 'cheapest',
        WinnerStrategy.mostExpensive => 'most_expensive',
        WinnerStrategy.average => 'average',
      };
}

/// How the margin is computed on top of the (converted) supplier cost.
enum MarginType {
  fixed,
  percentage;

  static MarginType fromKey(String key) {
    switch (key) {
      case 'fixed':
        return MarginType.fixed;
      case 'percentage':
        return MarginType.percentage;
      default:
        throw ArgumentError.value(key, 'key', 'Unknown margin type');
    }
  }

  String get key => name;
}

enum RoundingMethod {
  ceil,
  floor,
  nearest;

  static RoundingMethod fromKey(String key) {
    switch (key) {
      case 'ceil':
        return RoundingMethod.ceil;
      case 'floor':
        return RoundingMethod.floor;
      case 'nearest':
        return RoundingMethod.nearest;
      default:
        throw ArgumentError.value(key, 'key', 'Unknown rounding method');
    }
  }

  String get key => name;
}

/// Mirrors the Appwrite `pricing_config` row (`docs/appwrite-handoff.md`
/// §3/§5), plus one field the original schema was missing: [marginValueMinor]
/// — the actual flat/percentage margin to apply. `margin_min`/`margin_max`
/// alone can't drive a pipeline; they only make sense as a clamp on the
/// *computed* margin amount, so this adds the value they clamp.
///
/// Units, explicit because this schema mixes several without saying so:
/// - [marginValueMinor]: minor units (öre/cents) when [marginType] is
///   `fixed`; **basis points** (1/100 of a percent — `2000` = 20.00%) when
///   `percentage`, for sub-percent precision without floats.
/// - [marginMinMinor] / [marginMaxMinor]: minor units, clamping the
///   *resulting monetary margin* (not the percentage). `0`/`0` (the
///   provisioned default) means "no clamp".
/// - [roundingStepMajor]: **major** currency units (matches the handoff
///   doc's "step 5/10" example, e.g. round to the nearest 5 kr), converted
///   to minor units internally.
class PricingConfig {
  const PricingConfig({
    required this.strategy,
    required this.marginType,
    required this.marginValueMinor,
    required this.marginMinMinor,
    required this.marginMaxMinor,
    required this.taxRatePercent,
    required this.roundingEnabled,
    required this.roundingMethod,
    required this.roundingStepMajor,
    required this.shopCurrency,
  });

  factory PricingConfig.fromRow(Map<String, dynamic> row) {
    return PricingConfig(
      strategy: WinnerStrategy.fromKey(row['strategy'] as String? ?? 'cheapest'),
      marginType: MarginType.fromKey(row['margin_type'] as String? ?? 'percentage'),
      marginValueMinor: (row['margin_value'] as num?)?.toInt() ?? 0,
      marginMinMinor: (row['margin_min'] as num?)?.toInt() ?? 0,
      marginMaxMinor: (row['margin_max'] as num?)?.toInt() ?? 0,
      taxRatePercent: (row['tax_rate'] as num?)?.toDouble() ?? 0.0,
      roundingEnabled: row['rounding_enabled'] as bool? ?? true,
      roundingMethod: RoundingMethod.fromKey(row['rounding_method'] as String? ?? 'nearest'),
      roundingStepMajor: (row['rounding_step'] as num?)?.toInt() ?? 5,
      shopCurrency: row['shop_currency'] as String? ?? 'SEK',
    );
  }

  /// A reasonable default for local runs/tests when no `pricing_config` row
  /// exists yet: 20% margin, no tax, round to the nearest 5.
  factory PricingConfig.defaults({String shopCurrency = 'SEK'}) => PricingConfig(
        strategy: WinnerStrategy.cheapest,
        marginType: MarginType.percentage,
        marginValueMinor: 2000, // 20.00%
        marginMinMinor: 0,
        marginMaxMinor: 0,
        taxRatePercent: 0,
        roundingEnabled: true,
        roundingMethod: RoundingMethod.nearest,
        roundingStepMajor: 5,
        shopCurrency: shopCurrency,
      );

  final WinnerStrategy strategy;
  final MarginType marginType;
  final int marginValueMinor;
  final int marginMinMinor;
  final int marginMaxMinor;
  final double taxRatePercent;
  final bool roundingEnabled;
  final RoundingMethod roundingMethod;
  final int roundingStepMajor;
  final String shopCurrency;

  int get roundingStepMinor => roundingStepMajor * 100;

  /// `true` when [marginMinMinor]/[marginMaxMinor] are both `0` — the
  /// provisioned default, meaning "no clamp" rather than "clamp to zero".
  bool get hasMarginClamp => marginMinMinor != 0 || marginMaxMinor != 0;

  /// Inverse of [PricingConfig.fromRow] — used to write a default row the
  /// first time `pricing_config` is read and found empty.
  Map<String, dynamic> toRow() => {
        'strategy': strategy.key,
        'margin_type': marginType.key,
        'margin_value': marginValueMinor,
        'margin_min': marginMinMinor,
        'margin_max': marginMaxMinor,
        'tax_rate': taxRatePercent,
        'rounding_enabled': roundingEnabled,
        'rounding_method': roundingMethod.key,
        'rounding_step': roundingStepMajor,
        'shop_currency': shopCurrency,
      };
}
