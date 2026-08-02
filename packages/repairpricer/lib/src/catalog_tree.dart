/// Depth-windowed views over `category_path` — the pure half of
/// [RepairPricerClient.getCatalogs].
///
/// Every catalog slot carries a five-level path
/// (`device_type > manufacturer > model > Reparation > repair`, e.g.
/// `Mobil > Samsung > Galaxy Z Fold4 > Reparation > Speaker`). A tree UI
/// almost never wants all five levels at once: the fast pattern is
/// "manufacturers first, collapsed", then one narrow fetch per expansion.
/// [aggregateCatalogPaths] turns raw paths into that windowed view; the
/// client picks the cheapest projection to read the paths from.
library;

/// Absolute 1-based positions inside a full `category_path`. Useful when
/// calling [RepairPricerClient.getCatalogs] so call sites read as intent
/// (`depth: CatalogLevel.model`) instead of bare numbers.
abstract final class CatalogLevel {
  static const int deviceType = 1;
  static const int manufacturer = 2;
  static const int model = 3;
  static const int repairGroup = 4; // the literal "Reparation" segment
  static const int repair = 5;
}

/// One distinct node (or trimmed sub-path) of the catalog tree.
class CatalogNode {
  const CatalogNode({required this.path, required this.count});

  /// The path segments this node covers, starting at the requested depth —
  /// NOT at the root. `getCatalogs('', 3, 0)` yields paths like
  /// `[Galaxy Z Fold4, Reparation, Speaker]`.
  final List<String> path;

  /// How many source rows collapsed into this node (devices when served from
  /// `device_projection`, slots when served from `catalog_projection`).
  final int count;

  /// First segment — the node's own label when a single level was requested.
  String get name => path.isEmpty ? '' : path.first;

  /// The full trimmed path re-joined with the canonical ` > ` separator.
  String get joined => path.join(' > ');
}

/// Splits a `category_path` (or a filter prefix) into trimmed segments.
/// Empty input → empty list.
List<String> splitCategoryPath(String path) => [
      for (final s in path.split('>'))
        if (s.trim().isNotEmpty) s.trim(),
    ];

/// Collapses raw category paths into the distinct nodes of the depth window
/// `[depth, maxDepth]` (both 1-based, absolute from the root).
///
/// - [depth]: first level to keep — `3` skips device type + manufacturer.
/// - [maxDepth]: last level to keep; `0` means "to the leaf".
/// - [filter]: leading segments every path must match (case-insensitive),
///   i.e. the already-known prefix of the tree the caller is expanding.
///
/// Paths shorter than [depth] (or not matching [filter]) are dropped. Equal
/// trimmed paths merge into one node whose [CatalogNode.count] is the number
/// of source rows behind it. Output is sorted by path.
List<CatalogNode> aggregateCatalogPaths(
  Iterable<List<String>> paths, {
  required int depth,
  int maxDepth = 0,
  List<String> filter = const [],
}) {
  if (depth < 1) {
    throw ArgumentError.value(depth, 'depth', 'must be >= 1');
  }
  if (maxDepth != 0 && maxDepth < depth) {
    throw ArgumentError.value(maxDepth, 'maxDepth', 'must be 0 or >= depth');
  }
  final counts = <String, int>{};
  final firstSeen = <String, List<String>>{};
  for (final path in paths) {
    if (path.length < depth) continue;
    if (!_matchesPrefix(path, filter)) continue;
    final end = maxDepth == 0
        ? path.length
        : (maxDepth < path.length ? maxDepth : path.length);
    final trimmed = path.sublist(depth - 1, end);
    if (trimmed.isEmpty) continue;
    final key = trimmed.map((s) => s.toLowerCase()).join(' > ');
    counts[key] = (counts[key] ?? 0) + 1;
    firstSeen.putIfAbsent(key, () => trimmed);
  }
  final keys = counts.keys.toList()..sort();
  return [
    for (final k in keys)
      CatalogNode(path: firstSeen[k]!, count: counts[k]!),
  ];
}

bool _matchesPrefix(List<String> path, List<String> filter) {
  if (filter.length > path.length) return false;
  for (var i = 0; i < filter.length; i++) {
    if (path[i].toLowerCase() != filter[i].toLowerCase()) return false;
  }
  return true;
}
