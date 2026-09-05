import 'package:repairpricer_contract/repairpricer_contract.dart';

/// One row from the shared `catalog_projection` master set.
class CatalogSlotView {
  const CatalogSlotView({
    required this.code,
    required this.categoryPath,
    required this.modelName,
    required this.repairName,
    required this.tierName,
    required this.costPriceMinor,
    required this.winningPriceMinor,
    required this.currency,
    required this.inStock,
    this.deviceTypeName,
    this.manufacturerName,
    this.tierKey,
    this.displayTierName,
    this.displayPriceMinor,
    this.displayCurrency,
    this.displayPriceUnavailable = false,
    this.suggestedServiceFeeMinor,
    this.finalPriceToCustomerMinor,
    this.estimatedWorkMinutes,
    this.estimatedWorkHours,
    this.verificationStatus = VerificationStatus.generic,
    this.verificationLevel,
    this.verificationTimestamp,
  });

  final String code;
  final String categoryPath;
  final String? deviceTypeName;
  final String? manufacturerName;
  final String modelName;
  final String repairName;
  final String tierName;

  /// Frozen `tiers.key` mirrored into the projection — the lookup key for
  /// per-subscriber tier renames. Null on rows written before the column
  /// existed (falls back to [tierName]).
  final String? tierKey;

  /// Set only when a [ClientConfigBundle] was applied: the subscriber's own
  /// tier label ([displayTierName], defaults to [tierName] when no
  /// override) and — in custom pricing mode — their own margin pipeline run
  /// on [costPriceMinor] ([displayPriceMinor]; null in platform mode when no
  /// conversion was needed, in which case [winningPriceMinor] already is the
  /// display price).
  final String? displayTierName;
  final int? displayPriceMinor;

  /// The currency [displayPriceMinor] is stated in — the subscriber's
  /// [SubscriberConfig.displayCurrency] — set only when a config was applied.
  ///
  /// When the config carried rates and the row was in another currency,
  /// [applyClientConfig] restates **every** money field on the returned view
  /// and updates [currency] to match, so the view is never a mix.
  final String? displayCurrency;

  /// True when a config was applied, the row needed converting into
  /// [SubscriberConfig.displayCurrency], and no rate was available.
  ///
  /// This exists so a null [displayPriceMinor] is not ambiguous. Without it,
  /// "nothing to convert" and "could not convert" look identical, and a UI
  /// falling back to [winningPriceMinor] would print a foreign-currency
  /// number under the shop's own currency symbol — the exact bug conversion
  /// is here to end. Show "price unavailable", not a number.
  final bool displayPriceUnavailable;
  final int costPriceMinor;
  final int winningPriceMinor;
  final String currency;
  final bool inStock;
  final int? suggestedServiceFeeMinor;
  final int? finalPriceToCustomerMinor;
  final int? estimatedWorkMinutes;
  final double? estimatedWorkHours;
  final VerificationStatus verificationStatus;
  final VerificationLevel? verificationLevel;
  final DateTime? verificationTimestamp;

  /// Badge for UI: Verified | Generic | Not-Verifiable.
  String get verificationBadge => verificationStatus.badgeLabel;

  factory CatalogSlotView.fromRow(Map<String, dynamic> row) {
    final ts = row['verification_timestamp'];
    return CatalogSlotView(
      code: row['code'] as String? ?? '',
      categoryPath: row['category_path'] as String? ?? '',
      deviceTypeName: row['device_type_name'] as String?,
      manufacturerName: row['manufacturer_name'] as String?,
      modelName: row['model_name'] as String? ?? '',
      repairName: row['repair_name'] as String? ?? '',
      tierName: row['tier_name'] as String? ?? '',
      tierKey: row['tier_key'] as String?,
      costPriceMinor: (row['cost_price'] as num?)?.toInt() ?? 0,
      winningPriceMinor: (row['winning_price'] as num?)?.toInt() ?? 0,
      currency: row['currency'] as String? ?? 'SEK',
      inStock: row['in_stock'] as bool? ?? false,
      suggestedServiceFeeMinor: (row['suggested_service_fee'] as num?)?.toInt(),
      finalPriceToCustomerMinor: (row['final_price_to_customer'] as num?)?.toInt(),
      estimatedWorkMinutes: (row['estimated_work_minutes'] as num?)?.toInt(),
      estimatedWorkHours: (row['estimated_work_hours'] as num?)?.toDouble(),
      verificationStatus: VerificationStatus.fromKey(row['verification_status'] as String?),
      verificationLevel: VerificationLevel.fromKey(row['verification_level'] as String?),
      verificationTimestamp: ts is String ? DateTime.tryParse(ts)?.toUtc() : null,
    );
  }

  /// `?? this.x` cannot express "set this back to null", and
  /// [applyClientConfig] genuinely needs to: applying a platform-mode config
  /// to a view that already carries a display price must clear it, or a
  /// second application would keep a stale figure from the first. Hence the
  /// sentinel on the one field where null is a meaningful value to write.
  static const Object _unset = Object();

  CatalogSlotView _copyWith({
    int? costPriceMinor,
    int? winningPriceMinor,
    String? currency,
    Object? suggestedServiceFeeMinor = _unset,
    Object? finalPriceToCustomerMinor = _unset,
    String? displayTierName,
    Object? displayPriceMinor = _unset,
    String? displayCurrency,
    bool? displayPriceUnavailable,
  }) =>
      CatalogSlotView(
        code: code,
        categoryPath: categoryPath,
        deviceTypeName: deviceTypeName,
        manufacturerName: manufacturerName,
        modelName: modelName,
        repairName: repairName,
        tierName: tierName,
        tierKey: tierKey,
        displayTierName: displayTierName ?? this.displayTierName,
        displayPriceMinor:
            identical(displayPriceMinor, _unset) ? this.displayPriceMinor : displayPriceMinor as int?,
        displayCurrency: displayCurrency ?? this.displayCurrency,
        displayPriceUnavailable: displayPriceUnavailable ?? this.displayPriceUnavailable,
        costPriceMinor: costPriceMinor ?? this.costPriceMinor,
        winningPriceMinor: winningPriceMinor ?? this.winningPriceMinor,
        currency: currency ?? this.currency,
        inStock: inStock,
        suggestedServiceFeeMinor: identical(suggestedServiceFeeMinor, _unset)
            ? this.suggestedServiceFeeMinor
            : suggestedServiceFeeMinor as int?,
        finalPriceToCustomerMinor: identical(finalPriceToCustomerMinor, _unset)
            ? this.finalPriceToCustomerMinor
            : finalPriceToCustomerMinor as int?,
        estimatedWorkMinutes: estimatedWorkMinutes,
        estimatedWorkHours: estimatedWorkHours,
        verificationStatus: verificationStatus,
        verificationLevel: verificationLevel,
        verificationTimestamp: verificationTimestamp,
      );

  /// This row with **every** money field restated in [target], and
  /// [currency] updated to match — so the view is never a mix of two
  /// currencies wearing one label.
  ///
  /// Returns **null** when [rates] cannot reach [target] from [currency].
  /// That is deliberate and is the whole contract of this method: the
  /// alternative to a null is a number that is wrong by an exchange rate, and
  /// there is no safe default to substitute. `rateToShop: 1.0` is exactly the
  /// assumption that presented EUR prices as SEK.
  ///
  /// [rates] and [shopCurrency] are the pair [CatalogSnapshot] publishes.
  CatalogSlotView? inCurrency(
    String target, {
    required Map<String, double> rates,
    required String shopCurrency,
  }) {
    final from = currency.trim().toUpperCase();
    final to = target.trim().toUpperCase();
    if (to.isEmpty) return null;
    if (from == to) return this;

    int? at(int? amount) => amount == null
        ? null
        : convertMinor(amount, from: from, to: to, rates: rates, shopCurrency: shopCurrency);

    final cost = at(costPriceMinor);
    final winning = at(winningPriceMinor);
    if (cost == null || winning == null) return null;

    return _copyWith(
      costPriceMinor: cost,
      winningPriceMinor: winning,
      currency: to,
      suggestedServiceFeeMinor: at(suggestedServiceFeeMinor),
      finalPriceToCustomerMinor: at(finalPriceToCustomerMinor),
    );
  }

  /// Applies a subscriber's [ClientConfigBundle] to this row: their tier
  /// label for [locale], their display currency, and — when `pricing_mode`
  /// is `custom` — their own margin/tax/rounding pipeline over
  /// [costPriceMinor].
  ///
  /// ## Currency
  ///
  /// Projection rows are stored in the **winning supplier's** currency and
  /// are never normalised, so a row is routinely not in the shop's currency.
  /// When [config] carries rates (see [ClientConfigBundle.withRates]) and the
  /// two differ, the row is restated into
  /// [SubscriberConfig.displayCurrency] via [inCurrency] **before** the
  /// margin pipeline runs — the subscriber's rounding step and fixed margin
  /// are denominated in their own currency, so converting first is what makes
  /// "round to the nearest 5" mean five of the right unit.
  ///
  /// A bundle with no rates does not convert and behaves exactly as before
  /// this existed. When conversion is needed but no rate is available — or
  /// the bundle's rates are older than [ClientConfigBundle.maxRateAge] —
  /// [displayPriceUnavailable] is set and [displayPriceMinor] is left null —
  /// show that as "price unavailable" rather than falling back to
  /// [winningPriceMinor], which would be a foreign-currency number under the
  /// shop's own symbol.
  CatalogSlotView applyClientConfig(ClientConfigBundle config, {required String locale}) {
    final target = config.config.displayCurrency;
    final tierName_ = config.tierLabel(tierKey, tierName, locale: locale);
    final needsFx = config.canConvert && currency.trim().toUpperCase() != target.trim().toUpperCase();

    // Stale rates are refused, not used: a rate that exists but is weeks old
    // converts to a confidently wrong number, which is the one failure the
    // null-never-1.0 rule cannot catch. Treated exactly like a missing rate.
    final base = needsFx && !config.ratesAreStale()
        ? inCurrency(target, rates: config.rates, shopCurrency: config.shopCurrency)
        : (needsFx ? null : this);
    if (base == null) {
      return _copyWith(
        displayTierName: tierName_,
        displayPriceMinor: null,
        displayCurrency: target,
        displayPriceUnavailable: true,
      );
    }

    final displayPrice = switch (config.config.pricingMode) {
      PricingMode.custom => computeOfferPricing(
          rawPriceMinor: base.costPriceMinor,
          config: config.config.toPricingConfig(),
          // The cost is already in the subscriber's currency by here — a
          // second FX factor would double-convert.
          rateToShop: 1.0,
        ).finalPriceMinor,
      // Platform mode publishes `winningPriceMinor` as the display price, so
      // there is nothing to add when no conversion happened. When one did,
      // this is the converted figure and the caller needs it.
      PricingMode.platform => needsFx ? base.winningPriceMinor : null,
    };

    return base._copyWith(
      displayTierName: tierName_,
      displayPriceMinor: displayPrice,
      displayCurrency: target,
    );
  }
}

/// One row from `offer_projection` — the database stores every offer;
/// [RepairPricerClient.winnerForSlot] picks among them by strategy.
class OfferView {
  const OfferView({
    required this.code,
    required this.offerId,
    required this.isWinnerCached,
    required this.supplierName,
    required this.costPriceMinor,
    required this.shelfPriceMinor,
    required this.currency,
    required this.inStock,
    this.sku,
    this.productName,
    this.productUrl,
    this.rawAttributeLabel,
  });

  final String code;
  final String offerId;

  /// Cached flag from the last platform sync — informational only.
  /// Prefer [RepairPricerClient.winnerForSlot] with an explicit strategy.
  final bool isWinnerCached;
  final String supplierName;
  final String? sku;
  final String? productName;

  /// Link to the offer on the supplier's own site, when the supplier
  /// exposes one — not every supplier does.
  final String? productUrl;
  final String? rawAttributeLabel;

  /// Cost in [currency] (supplier fetched currency — convert client-side).
  final int costPriceMinor;
  final int shelfPriceMinor;

  /// ISO currency of [costPriceMinor] / [shelfPriceMinor] as fetched.
  final String currency;
  final bool inStock;

  /// Convert [costPriceMinor] into [targetCurrency] using [rateFromOfferToTarget]
  /// (units of target per 1 unit of offer currency).
  int costInTargetMinor(double rateFromOfferToTarget) =>
      (costPriceMinor * rateFromOfferToTarget).round();

  factory OfferView.fromRow(Map<String, dynamic> row) {
    return OfferView(
      code: row['code'] as String? ?? '',
      offerId: row['offer_id'] as String? ?? '',
      isWinnerCached: row['is_winner'] as bool? ?? false,
      supplierName: row['supplier_name'] as String? ?? '',
      sku: row['sku'] as String?,
      productName: row['product_name'] as String?,
      productUrl: row['product_url'] as String?,
      rawAttributeLabel: row['raw_attribute_label'] as String?,
      costPriceMinor: (row['cost_price'] as num?)?.toInt() ?? 0,
      shelfPriceMinor: (row['shelf_price'] as num?)?.toInt() ?? 0,
      currency: row['currency'] as String? ?? 'SEK',
      inStock: row['in_stock'] as bool? ?? false,
    );
  }
}

/// One row from `device_projection` — the "which models does the owner
/// carry" surface, independent of pricing. One row per device.
class RepairPricerDevice {
  const RepairPricerDevice({
    required this.manufacturerName,
    required this.modelName,
    this.deviceTypeName,
    this.externalUid,
  });

  final String manufacturerName;
  final String modelName;
  final String? deviceTypeName;

  /// The owner-catalog device's stable external id, when the projection
  /// carries it.
  final String? externalUid;

  factory RepairPricerDevice.fromRow(Map<String, dynamic> row) {
    return RepairPricerDevice(
      manufacturerName: row['manufacturer_name'] as String? ?? '',
      modelName: row['model_name'] as String? ?? '',
      deviceTypeName: row['device_type_name'] as String?,
      externalUid: row['external_uid'] as String?,
    );
  }
}
