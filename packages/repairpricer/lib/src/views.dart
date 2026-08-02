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
  /// on [costPriceMinor] ([displayPriceMinor]; null in platform mode, use
  /// [winningPriceMinor]).
  final String? displayTierName;
  final int? displayPriceMinor;
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

  /// Applies a subscriber's [ClientConfigBundle] to this row: their tier
  /// label for [locale], and — when `pricing_mode` is `custom` — their own
  /// margin/tax/rounding pipeline over [costPriceMinor].
  CatalogSlotView applyClientConfig(ClientConfigBundle config, {required String locale}) {
    final displayPrice = config.config.pricingMode == PricingMode.custom
        ? computeOfferPricing(
            rawPriceMinor: costPriceMinor,
            config: config.config.toPricingConfig(),
            rateToShop: 1.0,
          ).finalPriceMinor
        : null;
    return CatalogSlotView(
      code: code,
      categoryPath: categoryPath,
      deviceTypeName: deviceTypeName,
      manufacturerName: manufacturerName,
      modelName: modelName,
      repairName: repairName,
      tierName: tierName,
      tierKey: tierKey,
      displayTierName: config.tierLabel(tierKey, tierName, locale: locale),
      displayPriceMinor: displayPrice,
      costPriceMinor: costPriceMinor,
      winningPriceMinor: winningPriceMinor,
      currency: currency,
      inStock: inStock,
      suggestedServiceFeeMinor: suggestedServiceFeeMinor,
      finalPriceToCustomerMinor: finalPriceToCustomerMinor,
      estimatedWorkMinutes: estimatedWorkMinutes,
      estimatedWorkHours: estimatedWorkHours,
      verificationStatus: verificationStatus,
      verificationLevel: verificationLevel,
      verificationTimestamp: verificationTimestamp,
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
