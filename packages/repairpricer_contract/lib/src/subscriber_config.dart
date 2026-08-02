/// Per-subscriber (per-Team) pricing configuration — the read-time layer a
/// client's own settings apply over the shared master projections.
///
/// Pure Dart on purpose: no `dart_appwrite`/`appwrite`/Flutter import, so it
/// lives in `repairpricer_contract` and is shared verbatim by the server
/// engine and the `repairpricer` Flutter SDK (portal, embeddable widget)
/// instead of being copied. The source of truth for winner selection and the
/// margin pipeline stays `winner_selector.dart` / `pricing_pipeline.dart`;
/// [SubscriberConfig.toPricingConfig] adapts into them so the math is never
/// duplicated.
///
/// Config is applied at READ time only. The global recompute keeps writing
/// the platform winner (`is_winner`, `winning_price`) as informational
/// defaults; a subscriber with a config row re-selects/re-prices in-client.
/// A team without a config row behaves exactly as before this layer existed.
library;

import 'pricing_config.dart';

/// Whether the subscriber shows the platform's precomputed `winning_price`
/// as-is, or re-runs the margin pipeline on the winner's `cost_price` with
/// their own margin/tax/rounding at read time.
enum PricingMode {
  platform,
  custom;

  static PricingMode fromKey(String? key) {
    switch (key) {
      case 'custom':
        return PricingMode.custom;
      case 'platform':
      default:
        return PricingMode.platform;
    }
  }

  String get key => name;
}

/// What a [FilterRule] excludes. Wire values match the enum provisioned on
/// `subscriber_filter_rules.kind`; [projectionColumn] is the
/// `catalog_projection` / `offer_projection` column the rule's value is
/// compared against (rules store display NAMES — the projections carry no
/// external_uids, and names allow server-side `Query.notEqual` pushdown).
enum FilterKind {
  manufacturer,
  deviceType,
  device,
  supplier;

  static FilterKind fromKey(String key) {
    switch (key) {
      case 'manufacturer':
        return FilterKind.manufacturer;
      case 'device_type':
        return FilterKind.deviceType;
      case 'device':
        return FilterKind.device;
      case 'supplier':
        return FilterKind.supplier;
      default:
        throw ArgumentError.value(key, 'key', 'Unknown filter kind');
    }
  }

  String get key => switch (this) {
        FilterKind.manufacturer => 'manufacturer',
        FilterKind.deviceType => 'device_type',
        FilterKind.device => 'device',
        FilterKind.supplier => 'supplier',
      };

  String get projectionColumn => switch (this) {
        FilterKind.manufacturer => 'manufacturer_name',
        FilterKind.deviceType => 'device_type_name',
        FilterKind.device => 'model_name',
        FilterKind.supplier => 'supplier_name',
      };
}

enum WidgetTheme {
  light,
  dark,
  auto;

  static WidgetTheme fromKey(String? key) {
    switch (key) {
      case 'light':
        return WidgetTheme.light;
      case 'dark':
        return WidgetTheme.dark;
      case 'auto':
      default:
        return WidgetTheme.auto;
    }
  }

  String get key => name;
}

/// Mirrors one `subscriber_config` row — the wide 1:1-with-team settings
/// row. Self-contained semantics: values are seeded from
/// [PricingConfig.defaults] at provisioning and never inherit from the
/// global `pricing_config` row afterwards (no null-means-inherit).
class SubscriberConfig {
  const SubscriberConfig({
    required this.teamId,
    required this.pricingMode,
    required this.strategy,
    required this.marginType,
    required this.marginValueMinor,
    required this.marginMinMinor,
    required this.marginMaxMinor,
    required this.taxRatePercent,
    required this.roundingEnabled,
    required this.roundingMethod,
    required this.roundingStepMajor,
    required this.displayCurrency,
    this.widgetKey,
    this.widgetEnabled = false,
    this.widgetTheme = WidgetTheme.auto,
    this.widgetAccentColor,
    this.widgetLocale = 'sv',
    this.widgetTitle,
    this.updatedAt,
  });

  final String teamId;
  final PricingMode pricingMode;
  final WinnerStrategy strategy;
  final MarginType marginType;

  /// Same units as the global config: minor units when [marginType] is
  /// `fixed`, basis points (2000 = 20.00%) when `percentage`.
  final int marginValueMinor;
  final int marginMinMinor;
  final int marginMaxMinor;
  final double taxRatePercent;
  final bool roundingEnabled;
  final RoundingMethod roundingMethod;
  final int roundingStepMajor;
  final String displayCurrency;

  /// Public revocable key for the future embeddable widget. Generated
  /// server-side at provisioning; regenerated only through the
  /// `subscriber_config_admin` Function. Team-readable by design (the
  /// portal's snippet preview shows it) — the widget endpoint resolves it
  /// server-side, it is never a grant of database access by itself.
  final String? widgetKey;
  final bool widgetEnabled;
  final WidgetTheme widgetTheme;
  final String? widgetAccentColor;
  final String widgetLocale;
  final String? widgetTitle;
  final DateTime? updatedAt;

  /// Seeds a fresh config row for [teamId] with the same values
  /// [PricingConfig.defaults] uses, in `platform` mode (behave like today
  /// until the subscriber opts into custom pricing).
  factory SubscriberConfig.defaults({required String teamId, String? widgetKey}) {
    final base = PricingConfig.defaults();
    return SubscriberConfig(
      teamId: teamId,
      pricingMode: PricingMode.platform,
      strategy: base.strategy,
      marginType: base.marginType,
      marginValueMinor: base.marginValueMinor,
      marginMinMinor: base.marginMinMinor,
      marginMaxMinor: base.marginMaxMinor,
      taxRatePercent: base.taxRatePercent,
      roundingEnabled: base.roundingEnabled,
      roundingMethod: base.roundingMethod,
      roundingStepMajor: base.roundingStepMajor,
      displayCurrency: base.shopCurrency,
      widgetKey: widgetKey,
    );
  }

  factory SubscriberConfig.fromRow(Map<String, dynamic> row) {
    final ts = row['updated_at'];
    return SubscriberConfig(
      teamId: row['team_id'] as String? ?? '',
      pricingMode: PricingMode.fromKey(row['pricing_mode'] as String?),
      strategy: WinnerStrategy.fromKey(row['strategy'] as String? ?? 'cheapest'),
      marginType: MarginType.fromKey(row['margin_type'] as String? ?? 'percentage'),
      marginValueMinor: (row['margin_value'] as num?)?.toInt() ?? 0,
      marginMinMinor: (row['margin_min'] as num?)?.toInt() ?? 0,
      marginMaxMinor: (row['margin_max'] as num?)?.toInt() ?? 0,
      taxRatePercent: (row['tax_rate'] as num?)?.toDouble() ?? 0.0,
      roundingEnabled: row['rounding_enabled'] as bool? ?? true,
      roundingMethod: RoundingMethod.fromKey(row['rounding_method'] as String? ?? 'nearest'),
      roundingStepMajor: (row['rounding_step'] as num?)?.toInt() ?? 5,
      displayCurrency: row['display_currency'] as String? ?? 'SEK',
      widgetKey: row['widget_key'] as String?,
      widgetEnabled: row['widget_enabled'] as bool? ?? false,
      widgetTheme: WidgetTheme.fromKey(row['widget_theme'] as String?),
      widgetAccentColor: row['widget_accent_color'] as String?,
      widgetLocale: row['widget_locale'] as String? ?? 'sv',
      widgetTitle: row['widget_title'] as String?,
      updatedAt: ts is String ? DateTime.tryParse(ts)?.toUtc() : null,
    );
  }

  /// Full row payload. `team_id` and `widget_key` are included because the
  /// server-side repository owns writes; the `subscriber_config_admin`
  /// Function whitelists which of these fields a subscriber may change.
  Map<String, dynamic> toRow() => {
        'team_id': teamId,
        'pricing_mode': pricingMode.key,
        'strategy': strategy.key,
        'margin_type': marginType.key,
        'margin_value': marginValueMinor,
        'margin_min': marginMinMinor,
        'margin_max': marginMaxMinor,
        'tax_rate': taxRatePercent,
        'rounding_enabled': roundingEnabled,
        'rounding_method': roundingMethod.key,
        'rounding_step': roundingStepMajor,
        'display_currency': displayCurrency,
        if (widgetKey != null) 'widget_key': widgetKey,
        'widget_enabled': widgetEnabled,
        'widget_theme': widgetTheme.key,
        if (widgetAccentColor != null) 'widget_accent_color': widgetAccentColor,
        'widget_locale': widgetLocale,
        if (widgetTitle != null) 'widget_title': widgetTitle,
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  /// Adapter into the shared pure pricing math ([selectWinner],
  /// `computeOfferPricing`) so per-subscriber pricing never re-implements
  /// the pipeline.
  PricingConfig toPricingConfig() => PricingConfig(
        strategy: strategy,
        marginType: marginType,
        marginValueMinor: marginValueMinor,
        marginMinMinor: marginMinMinor,
        marginMaxMinor: marginMaxMinor,
        taxRatePercent: taxRatePercent,
        roundingEnabled: roundingEnabled,
        roundingMethod: roundingMethod,
        roundingStepMajor: roundingStepMajor,
        shopCurrency: displayCurrency,
      );
}

/// One exclusion on a subscriber's catalog view — mirrors a
/// `subscriber_filter_rules` row. Exclude-only by design (allow-lists are a
/// later additive change if ever needed).
class FilterRule {
  const FilterRule({required this.kind, required this.value, this.id});

  /// Row `$id` when loaded from Appwrite; null for locally built rules.
  final String? id;
  final FilterKind kind;

  /// The excluded display name, matching [FilterKind.projectionColumn].
  final String value;

  factory FilterRule.fromRow(Map<String, dynamic> row) => FilterRule(
        id: row[r'$id'] as String?,
        kind: FilterKind.fromKey(row['kind'] as String? ?? ''),
        value: row['value'] as String? ?? '',
      );

  Map<String, dynamic> toRow(String teamId) => {
        'team_id': teamId,
        'kind': kind.key,
        'value': value,
      };
}

/// Per-subscriber display name for one tier — mirrors a
/// `subscriber_tier_names` row. Keyed by the frozen `tiers.key` (never the
/// display name); a null locale column falls back to the global tier name.
class TierNameOverride {
  const TierNameOverride({required this.tierKey, this.en, this.sv});

  final String tierKey;
  final String? en;
  final String? sv;

  factory TierNameOverride.fromRow(Map<String, dynamic> row) => TierNameOverride(
        tierKey: row['tier_key'] as String? ?? '',
        en: row['en'] as String?,
        sv: row['sv'] as String?,
      );

  Map<String, dynamic> toRow(String teamId) => {
        'team_id': teamId,
        'tier_key': tierKey,
        if (en != null) 'en': en,
        if (sv != null) 'sv': sv,
      };

  /// Locale lookup mirroring the `translations` WIDE pattern. Returns null
  /// when this override has nothing for [locale] (caller falls back to the
  /// global name).
  String? labelFor(String locale) {
    final l = switch (locale.toLowerCase()) {
      'sv' => sv,
      'en' => en,
      _ => null,
    };
    if (l != null && l.isNotEmpty) return l;
    if (en != null && en!.isNotEmpty) return en;
    return null;
  }
}

/// Everything a client needs to apply its configuration at read time —
/// the config row plus its filter rules and tier renames, loaded together
/// by `RepairPricerClient.loadClientConfig()` (or the portal/widget).
class ClientConfigBundle {
  ClientConfigBundle({
    required this.config,
    List<FilterRule> filterRules = const [],
    List<TierNameOverride> tierNames = const [],
  })  : filterRules = List.unmodifiable(filterRules),
        _excludedByKind = {
          for (final kind in FilterKind.values)
            kind: {
              for (final rule in filterRules)
                if (rule.kind == kind) rule.value,
            },
        },
        _tierNamesByKey = {for (final t in tierNames) t.tierKey: t};

  final SubscriberConfig config;
  final List<FilterRule> filterRules;
  final Map<FilterKind, Set<String>> _excludedByKind;
  final Map<String, TierNameOverride> _tierNamesByKey;

  WinnerStrategy get strategy => config.strategy;

  List<TierNameOverride> get tierNames => List.unmodifiable(_tierNamesByKey.values);

  /// Whether this subscriber excludes [value] (a projection display name)
  /// for [kind].
  bool excludes(FilterKind kind, String? value) =>
      value != null && (_excludedByKind[kind]?.contains(value) ?? false);

  Set<String> excludedValues(FilterKind kind) => _excludedByKind[kind] ?? const {};

  /// Display label for a tier: the subscriber's override for [locale] when
  /// set, else [fallback] (the global `tier_name` from the projection).
  String tierLabel(String? tierKey, String fallback, {required String locale}) {
    if (tierKey == null || tierKey.isEmpty) return fallback;
    return _tierNamesByKey[tierKey]?.labelFor(locale) ?? fallback;
  }
}
