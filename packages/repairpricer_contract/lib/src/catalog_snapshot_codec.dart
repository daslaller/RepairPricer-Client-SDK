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
  });

  final int version;
  final DateTime generatedAt;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> slots;
}

/// Builds the snapshot document from raw projection rows. Only the
/// whitelisted columns survive, so a snapshot can never leak system fields
/// or permission arrays whatever the source rows carried.
Map<String, dynamic> encodeCatalogSnapshot({
  required DateTime generatedAt,
  required Iterable<Map<String, dynamic>> devices,
  required Iterable<Map<String, dynamic>> slots,
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

  return CatalogSnapshotData(
    version: version,
    generatedAt: generatedAt.toUtc(),
    devices: rows('devices'),
    slots: rows('slots'),
  );
}
