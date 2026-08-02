/// Display labels for the catalog's frozen vocabulary keys (part types,
/// tiers, device types). Canonical values everywhere else are opaque keys
/// that must never be renamed (they feed deterministic-ID hashing); this
/// is the presentation layer over them. Proper nouns (device/manufacturer
/// names) are never translated and never appear here.
class TranslationDictionary {
  TranslationDictionary(this._labels, {this.fallbackLocale = 'en'});

  /// Rows are WIDE: one row per (namespace, key) with one column per
  /// locale (`en`, `sv`, …) — a row is the complete map for its word, per
  /// the catalog owner's curation workflow (view/edit the whole word in
  /// one console row). Adding a language is one new column + refill.
  factory TranslationDictionary.fromRows(
    Iterable<Map<String, dynamic>> rows, {
    String fallbackLocale = 'en',
  }) {
    const nonLocaleColumns = {
      'namespace', 'key', // identity
      r'$id', r'$createdAt', r'$updatedAt', r'$permissions', r'$databaseId', r'$tableId', r'$sequence',
    };
    final labels = <String, String>{};
    for (final row in rows) {
      final ns = row['namespace'] as String?;
      final key = row['key'] as String?;
      if (ns == null || key == null) continue;
      for (final entry in row.entries) {
        if (nonLocaleColumns.contains(entry.key)) continue;
        final label = entry.value;
        if (label is String && label.isNotEmpty) {
          labels['$ns|$key|${entry.key.toLowerCase()}'] = label;
        }
      }
    }
    return TranslationDictionary(labels, fallbackLocale: fallbackLocale);
  }

  final Map<String, String> _labels;
  final String fallbackLocale;

  /// Label for a vocabulary key, degrading gracefully: requested locale →
  /// [fallbackLocale] → the raw key itself. A missing translation never
  /// breaks a client — it just shows the key until curation catches up.
  String label(String namespace, String key, {required String locale}) {
    return _labels['$namespace|$key|${locale.toLowerCase()}'] ??
        _labels['$namespace|$key|$fallbackLocale'] ??
        key;
  }

  /// Locales that have at least one label — what a UI's language picker
  /// should offer.
  Set<String> get locales => {for (final k in _labels.keys) k.split('|').last};
}
