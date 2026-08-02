import 'package:appwrite/appwrite.dart';
import 'package:repairpricer_contract/repairpricer_contract.dart';

/// A supplier that can appear on offers.
///
/// Read from the shared `suppliers` table. Only active suppliers are
/// returned by [RepairPricerClient.listSuppliers], so the list matches what
/// a subscriber can already infer from the catalog's `supplier_name` values.
class SupplierInfo {
  const SupplierInfo({
    required this.externalId,
    required this.name,
    required this.currency,
    required this.isActive,
  });

  /// Stable id. Prefer this over [name] when persisting a filter rule — a
  /// display name can be re-spelled, this should not be.
  final String externalId;

  /// The value that appears as `OfferView.supplierName`, and the value a
  /// [FilterKind.supplier] rule matches on.
  final String name;

  /// ISO currency this supplier's prices are fetched in.
  final String currency;

  final bool isActive;

  factory SupplierInfo.fromRow(Map<String, dynamic> row) {
    return SupplierInfo(
      externalId: row['external_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      currency: row['currency'] as String? ?? '',
      isActive: row['is_active'] as bool? ?? true,
    );
  }

  @override
  String toString() => 'SupplierInfo($name)';
}

/// Describes which offers you want, independent of any one slot.
///
/// Every field is optional; the default selects everything the subscriber is
/// allowed to see. Filters combine with AND — `suppliers: {'a'}` plus
/// `inStockOnly: true` means "in-stock offers from a".
///
/// ```dart
/// // everything from two suppliers, in stock only
/// await rp.listOffers(const OfferQuery(
///   suppliers: {'spares', 'foneday'},
///   inStockOnly: true,
/// ));
/// ```
///
/// **Precedence:** a subscriber's saved supplier exclusions (their
/// [ClientConfigBundle] filter rules — the region-locked-distributor case)
/// are applied on top of whatever you pass, and always win. Asking for a
/// supplier the team has excluded returns nothing rather than quietly
/// overriding their setting. Pass `respectSavedExclusions: false` to opt out
/// when you are deliberately building an admin/preview view.
class OfferQuery {
  const OfferQuery({
    this.slotCodes = const {},
    this.suppliers = const {},
    this.excludeSuppliers = const {},
    this.inStockOnly = false,
    this.winnersOnly = false,
    this.respectSavedExclusions = true,
  });

  /// Restrict to these slot codes. Empty means every slot.
  final Set<String> slotCodes;

  /// Only offers from these suppliers (by `supplier_name`). Empty means all.
  final Set<String> suppliers;

  /// Drop offers from these suppliers. Applied after [suppliers].
  final Set<String> excludeSuppliers;

  final bool inStockOnly;

  /// Only offers the last platform sync flagged as slot winner
  /// (`is_winner`). This is the platform's cached choice under *its* default
  /// strategy — if the subscriber uses a different [WinnerStrategy], prefer
  /// [RepairPricerClient.winnersFrom], which re-selects per their config.
  final bool winnersOnly;

  /// Whether the subscriber's saved supplier exclusions also apply.
  /// Defaults to true; see the class doc.
  final bool respectSavedExclusions;

  OfferQuery copyWith({
    Set<String>? slotCodes,
    Set<String>? suppliers,
    Set<String>? excludeSuppliers,
    bool? inStockOnly,
    bool? winnersOnly,
    bool? respectSavedExclusions,
  }) {
    return OfferQuery(
      slotCodes: slotCodes ?? this.slotCodes,
      suppliers: suppliers ?? this.suppliers,
      excludeSuppliers: excludeSuppliers ?? this.excludeSuppliers,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      winnersOnly: winnersOnly ?? this.winnersOnly,
      respectSavedExclusions: respectSavedExclusions ?? this.respectSavedExclusions,
    );
  }

  /// The effective exclusion set once the subscriber's saved rules are
  /// folded in. Exposed because a UI often needs to explain *why* a supplier
  /// produced no rows.
  Set<String> effectiveExclusions(ClientConfigBundle? config) {
    if (!respectSavedExclusions || config == null) return excludeSuppliers;
    return {...excludeSuppliers, ...config.excludedValues(FilterKind.supplier)};
  }

  /// Translates to Appwrite queries. Returns null when the filters cannot
  /// match anything — e.g. every requested supplier is also excluded — so
  /// the caller can skip the round-trip entirely instead of asking the
  /// server a question with a known-empty answer.
  List<String>? toQueries(ClientConfigBundle? config) {
    final excluded = effectiveExclusions(config);
    final wanted = suppliers.difference(excluded);
    if (suppliers.isNotEmpty && wanted.isEmpty) return null;

    return [
      if (slotCodes.isNotEmpty) Query.equal('code', slotCodes.toList()),
      // One `equal` with a list is OR across values, and it is what the
      // key_supplier_name index can serve. Excludes stay as notEqual (AND).
      if (wanted.isNotEmpty) Query.equal('supplier_name', wanted.toList()),
      if (wanted.isEmpty)
        for (final name in excluded) Query.notEqual('supplier_name', name),
      if (inStockOnly) Query.equal('in_stock', true),
      if (winnersOnly) Query.equal('is_winner', true),
    ];
  }
}
