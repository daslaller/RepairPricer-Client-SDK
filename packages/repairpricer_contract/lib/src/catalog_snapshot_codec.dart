/// The catalog snapshot's JSON shape — shared by the engine (which writes
/// the file after every `pricing_sync`) and the subscriber SDK (which
/// bootstraps from it instead of paging the Documents API).
///
/// Why a snapshot at all (measured 2026-07-31 against the live self-host):
/// Appwrite serves *bytes* fast — a 23.6 MB bucket file streamed at
/// ~10 MB/s with ~0.5 s to first byte — but serves *rows* slowly, because
/// every `listRows` pays per-row hydration, ACL decoding, and a COUNT at
/// request time (~1 s for the 4.5k-slot catalog, per request, per client).
/// Prepaying that work once per sync into a static gzipped file gives every
/// reader dp_cache-class latency; realtime bucket events then tell clients
/// when a fresh snapshot exists (Firestore-style: bootstrap + deltas).
///
/// This codec is deliberately dumb: plain maps in, plain maps out, no
/// Appwrite and no Flutter, so both sides share one definition of "what a
/// snapshot is" and the tests can prove compatibility without a server.
library;

/// Bump on breaking shape changes. Readers reject anything newer than what
/// they understand instead of mis-parsing it.
const int catalogSnapshotVersion = 1;

/// Columns copied per `device_projection` row. Everything else (system
/// fields, permissions) is deliberately dropped.
const List<String> snapshotDeviceColumns = [
  'device_type_name',
  'manufacturer_name',
  'model_name',
  'external_uid',
];

/// Columns copied per `catalog_projection` row — the set
/// `CatalogSlotView.fromRow` reads.
const List<String> snapshotSlotColumns = [
  'code',
  'category_path',
  'device_type_name',
  'manufacturer_name',
  'model_name',
  'repair_name',
  'tier_name',
  'tier_key',
  'cost_price',
  'winning_price',
  'currency',
  'in_stock',
  'suggested_service_fee',
  'final_price_to_customer',
  'estimated_work_minutes',
  'estimated_work_hours',
  'verification_status',
  'verification_level',
  'verification_timestamp',
];

/// A decoded snapshot: raw projection rows plus provenance. Typed wrapping
/// (into `CatalogSlotView` etc.) is the SDK's job — core stays view-free.
class CatalogSnapshotData {
  const CatalogSnapshotData({
    required this.version,
    required this.generatedAt,
    required this.devices,
    required this.slots,
    this.shopCurrency = '',
    this.rates = const {},
    this.ratesAsOf,
  });

  final int version;
  final DateTime generatedAt;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> slots;

  /// The platform's own currency — what [rates] convert *into*.
  /// Empty on editions published before rates existed.
  final String shopCurrency;

  /// FX rates, `CURRENCY -> units of [shopCurrency] per 1 unit of it`.
  /// e.g. `{'EUR': 11.3}` means €1 = 11.3 SEK when shopCurrency is SEK.
  ///
  /// Why the catalog needs these at all: a row's prices are stored in
  /// whatever currency its winning supplier was fetched in and are never
  /// normalised, so the catalog is genuinely mixed-currency. Publishing the
  /// rates alongside is what lets each subscriber convert into *their* shop
  /// currency — a single normalisation upstream could only ever serve one.
  ///
  /// Empty on editions published before rates existed, and possibly missing
  /// a currency the platform has no rate for. Treat a missing entry as
  /// "cannot convert", never as 1.0 — see [rateBetween].
  final Map<String, double> rates;

  /// The date the FX feed itself published [rates] — **not** when the
  /// snapshot was written.
  ///
  /// The two come apart, and that is the whole point of carrying this. The
  /// platform re-publishes a snapshot on every sync whether or not the rate
  /// refresh succeeded, so [generatedAt] can be minutes old while [rates]
  /// are weeks old. Without this field a stale rate is indistinguishable
  /// from a fresh one, and the reader converts at it silently — the one
  /// failure mode [rateBetween]'s null-never-1.0 rule cannot catch, because
  /// there IS a rate, it is just wrong now.
  ///
  /// Null on editions published before this field existed, and on any
  /// edition whose rates predate the platform recording a date. Null means
  /// **age unknown**, and every staleness check here treats that as "the
  /// rule does not apply" rather than as stale.
  ///
  /// That is a deliberate choice against the stricter reading. "Refuse
  /// unless proven fresh" is the safer instinct, but applied here it would
  /// black out every subscriber still holding a snapshot published before
  /// this field existed — an outage caused by the fix, not the bug. The real
  /// enforcement point is the platform, which reads `currency_rates.as_of`
  /// directly and always has a date; this check is the second line, and it
  /// engages by itself once editions start carrying one.
  final DateTime? ratesAsOf;

  /// How old [rates] are relative to [now] (defaults to the current time),
  /// or null when [ratesAsOf] is absent.
  Duration? ratesAge({DateTime? now}) => ratesAsOf == null
      ? null
      : (now ?? DateTime.now().toUtc()).difference(ratesAsOf!);

  /// True when [rates] are demonstrably older than [maxAge].
  ///
  /// False when there are no rates (nothing to be stale) and when
  /// [ratesAsOf] is null (age unknown — see that field for why unknown is
  /// not read as stale).
  ///
  /// A reader that enforces this should behave as though the rate were
  /// missing (refuse to convert, show "price unavailable"), not fall back to
  /// the unconverted figure. Both are honest; a stale conversion is not.
  bool ratesOlderThan(Duration maxAge, {DateTime? now}) {
    if (rates.isEmpty) return false;
    final age = ratesAge(now: now);
    return age != null && age > maxAge;
  }
}

/// A sensible ceiling on FX age for a repair-price display, and the default
/// [ClientConfigBundle] applies when rates come from a snapshot.
///
/// The ECB publishes every business day and the platform refreshes on a
/// several-hour cadence, so rates this old do not mean a transient outage —
/// they mean the refresh has been broken for a fortnight. Chosen to never
/// fire on a blip and still catch real rot.
const Duration defaultMaxRateAge = Duration(days: 14);

/// Converts [amountMinor] from [from] into [to] using [rates] expressed in
/// [shopCurrency]. Returns null when either leg has no rate — the caller
/// must decide what to show rather than being handed a silently wrong
/// number, which is why this is nullable and not `?? 1.0`.
int? convertMinor(
  int amountMinor, {
  required String from,
  required String to,
  required Map<String, double> rates,
  required String shopCurrency,
}) {
  final f = from.trim().toUpperCase();
  final t = to.trim().toUpperCase();
  if (f.isEmpty || t.isEmpty) return null;
  if (f == t) return amountMinor;
  final rate = rateBetween(from: f, to: t, rates: rates, shopCurrency: shopCurrency);
  return rate == null ? null : (amountMinor * rate).round();
}

/// The multiplier taking 1 unit of [from] to [to]. Null when unknown.
///
/// Rates are stored against the shop currency, so a cross pair (EUR->USD
/// with a SEK shop) routes through it: EUR->SEK->USD.
double? rateBetween({
  required String from,
  required String to,
  required Map<String, double> rates,
  required String shopCurrency,
}) {
  final f = from.trim().toUpperCase();
  final t = to.trim().toUpperCase();
  final shop = shopCurrency.trim().toUpperCase();
  if (f.isEmpty || t.isEmpty) return null;
  if (f == t) return 1.0;

  // A currency's rate against itself is 1 even when absent from the map.
  double? toShop(String c) => c == shop ? 1.0 : rates[c];

  final fromRate = toShop(f);
  final toRate = toShop(t);
  if (fromRate == null || toRate == null || toRate == 0) return null;
  return fromRate / toRate;
}

/// Builds the snapshot document from raw projection rows. Only the
/// whitelisted columns survive, so a snapshot can never leak system fields
/// or permission arrays whatever the source rows carried.
Map<String, dynamic> encodeCatalogSnapshot({
  required DateTime generatedAt,
  required Iterable<Map<String, dynamic>> devices,
  required Iterable<Map<String, dynamic>> slots,
  String shopCurrency = '',
  Map<String, double> rates = const {},
  DateTime? ratesAsOf,
}) {
  List<Map<String, dynamic>> strip(
          Iterable<Map<String, dynamic>> rows, List<String> columns) =>
      [
        for (final row in rows)
          {
            for (final c in columns)
              if (row[c] != null) c: row[c],
          },
      ];
  return {
    'version': catalogSnapshotVersion,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'devices': strip(devices, snapshotDeviceColumns),
    'slots': strip(slots, snapshotSlotColumns),
    // Additive: readers that predate these ignore unknown keys, so no
    // version bump and no coordinated deploy. Omitted entirely when empty
    // rather than written as {} so an edition without rates is obvious.
    if (shopCurrency.isNotEmpty) 'shop_currency': shopCurrency.toUpperCase(),
    if (rates.isNotEmpty)
      'rates': {
        for (final e in rates.entries) e.key.toUpperCase(): e.value,
      },
    // The FEED's publication date, not this snapshot's. Only written
    // alongside actual rates — a date with nothing to date is noise.
    if (rates.isNotEmpty && ratesAsOf != null)
      'rates_as_of': ratesAsOf.toUtc().toIso8601String(),
  };
}

/// Parses a snapshot document. Throws [FormatException] on a malformed
/// document or one written by a NEWER codec than this reader understands —
/// callers treat that exactly like "no snapshot" and fall back to live
/// queries.
CatalogSnapshotData decodeCatalogSnapshot(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! int || version < 1) {
    throw const FormatException('snapshot: missing/invalid version');
  }
  if (version > catalogSnapshotVersion) {
    throw FormatException(
        'snapshot: version $version is newer than supported ($catalogSnapshotVersion)');
  }
  final generatedAt = DateTime.tryParse('${json['generated_at'] ?? ''}');
  if (generatedAt == null) {
    throw const FormatException('snapshot: missing/invalid generated_at');
  }
  List<Map<String, dynamic>> rows(String key) {
    final raw = json[key];
    if (raw is! List) throw FormatException('snapshot: missing "$key" list');
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  // Rates are optional and additive: an edition published before they
  // existed simply has none, and a malformed entry is skipped rather than
  // failing the whole snapshot — a bad FX row must not cost a subscriber
  // their entire catalog.
  final rawRates = json['rates'];
  final rates = <String, double>{};
  if (rawRates is Map) {
    for (final e in rawRates.entries) {
      final v = e.value;
      final d = v is num ? v.toDouble() : double.tryParse('$v');
      if (d == null || d <= 0) continue;
      rates['${e.key}'.toUpperCase()] = d;
    }
  }

  return CatalogSnapshotData(
    version: version,
    generatedAt: generatedAt.toUtc(),
    devices: rows('devices'),
    slots: rows('slots'),
    shopCurrency: '${json['shop_currency'] ?? ''}'.toUpperCase(),
    rates: rates,
    // Unparseable is left null — "age unknown" — which ratesOlderThan
    // treats as stale. An invented date would be the same lie as a 1.0 rate.
    ratesAsOf: DateTime.tryParse('${json['rates_as_of'] ?? ''}')?.toUtc(),
  );
}
