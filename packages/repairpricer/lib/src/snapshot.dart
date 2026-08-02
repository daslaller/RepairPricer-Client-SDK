import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:repairpricer_contract/repairpricer_contract.dart';

import 'catalog_tree.dart';
import 'views.dart';

/// The typed, SDK-side view of one published catalog snapshot — the whole
/// subscriber-visible catalog (devices + slots) as of [generatedAt].
///
/// Snapshots exist because Appwrite serves bucket *bytes* at line rate but
/// pays per-row work on every Documents-API read (measured: ~0.5 s TTFB and
/// ~10 MB/s for a bucket file vs ~1 s server time for the same rows via
/// `listRows`, every time, per client). The engine prepays that per-row cost
/// once per `pricing_sync` and publishes the result as one gzipped file;
/// clients here bootstrap from it and use live queries only as fallback.
///
/// THE BOUNDARY — do not generalise this pattern. A blob snapshot fits this
/// catalog because it is GLOBAL (every subscriber sees the same rows),
/// READ-MOSTLY, and SLOW-CHANGING (batch writes, then quiet). Per-tenant,
/// write-heavy, permission-filtered data (e.g. RepairX's operational rows,
/// which carry row-level team grants a shared blob cannot express) belongs
/// on the opposite pattern: normal queries + realtime-driven cache
/// invalidation. The two share only the signalling rule: realtime is a
/// wake-up, never a data channel.
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.generatedAt,
    required this.devices,
    required this.slots,
  });

  final DateTime generatedAt;
  final List<RepairPricerDevice> devices;
  final List<CatalogSlotView> slots;

  /// Parses the raw bucket file (gzipped JSON, written by the engine's
  /// `CatalogSnapshotWriter`). Throws [FormatException] on garbage or on a
  /// snapshot newer than this SDK understands — callers treat both as
  /// "no snapshot" and fall back to live queries.
  factory CatalogSnapshot.fromBytes(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(bytes)));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('snapshot: not a JSON object');
    }
    final data = decodeCatalogSnapshot(json);
    return CatalogSnapshot(
      generatedAt: data.generatedAt,
      devices: [for (final row in data.devices) RepairPricerDevice.fromRow(row)],
      slots: [for (final row in data.slots) CatalogSlotView.fromRow(row)],
    );
  }
}

/// Applies row-level changes (realtime event payloads or watermark-query
/// rows, both raw snake_case maps) to an edition, returning the patched
/// edition. Slots key on `code`; devices key on manufacturer+model (unique
/// per device by design). Unknown deletes and stale duplicates are no-ops,
/// so replaying the same change is safe.
CatalogSnapshot applyCatalogChanges(
  CatalogSnapshot base, {
  List<Map<String, dynamic>> upsertDevices = const [],
  List<Map<String, dynamic>> deleteDevices = const [],
  List<Map<String, dynamic>> upsertSlots = const [],
  List<Map<String, dynamic>> deleteSlots = const [],
}) {
  String deviceKey(String? m, String? mo) =>
      '${(m ?? '').toLowerCase()}|${(mo ?? '').toLowerCase()}';

  final devices = {
    for (final d in base.devices)
      deviceKey(d.manufacturerName, d.modelName): d,
  };
  for (final row in upsertDevices) {
    final d = RepairPricerDevice.fromRow(row);
    if (d.manufacturerName.isEmpty || d.modelName.isEmpty) continue;
    devices[deviceKey(d.manufacturerName, d.modelName)] = d;
  }
  for (final row in deleteDevices) {
    devices.remove(deviceKey(
        row['manufacturer_name'] as String?, row['model_name'] as String?));
  }

  final slots = {for (final s in base.slots) s.code: s};
  for (final row in upsertSlots) {
    final s = CatalogSlotView.fromRow(row);
    if (s.code.isEmpty) continue;
    slots[s.code] = s;
  }
  for (final row in deleteSlots) {
    slots.remove('${row['code'] ?? ''}');
  }

  return CatalogSnapshot(
    generatedAt: base.generatedAt,
    devices: devices.values.toList(),
    slots: slots.values.toList(),
  );
}

/// Answers a `getCatalogs` depth window from an in-memory [snapshot] — the
/// same windowing as the live path ([aggregateCatalogPaths]), zero network.
///
/// Windows entirely above the repair levels are built from [CatalogSnapshot.devices]
/// (mirroring the live path's device_projection routing, and covering
/// devices that have no priced slots yet); anything touching level 4+ walks
/// the slots' `category_path`.
List<CatalogNode> catalogNodesFromSnapshot(
  CatalogSnapshot snapshot, {
  List<String> filter = const [],
  required int depth,
  int maxDepth = 0,
}) {
  final deviceLevelsSuffice = maxDepth != 0 &&
      maxDepth <= CatalogLevel.model &&
      filter.length <= CatalogLevel.model;
  final Iterable<List<String>> paths = deviceLevelsSuffice
      ? snapshot.devices.map((d) => [
            if ((d.deviceTypeName ?? '').isNotEmpty) d.deviceTypeName!,
            if (d.manufacturerName.isNotEmpty) d.manufacturerName,
            if (d.modelName.isNotEmpty) d.modelName,
          ])
      : snapshot.slots.map((s) => splitCategoryPath(s.categoryPath));
  return aggregateCatalogPaths(paths, depth: depth, maxDepth: maxDepth, filter: filter);
}
