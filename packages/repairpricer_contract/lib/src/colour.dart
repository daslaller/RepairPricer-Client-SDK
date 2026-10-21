/// Normalised colours: the shared vocabulary that makes two suppliers' red
/// the same red.
///
/// Suppliers write "Svart", "Black", "Midnight", "Phantom Black". The platform
/// reduces each to one key from [colourKeys] and keeps the supplier's own word
/// beside it as a label, so a marketing name can still be shown while matching
/// is done on the key.
///
/// **Absent means "no colour stated", never "colourless".** The platform
/// leaves a colour empty whenever it cannot read one with certainty, because a
/// guessed colour orders the wrong part. Consumers must treat an absent
/// colour as unplaced and never fall back to a default.
///
/// Turning a supplier title into a key is platform ingest and is not part of
/// this contract; only the vocabulary and its parsing are.
library;

/// Every key the platform may send, in display order (dark to light, then
/// hues, then metals and materials).
///
/// Rules that keep older readers safe:
/// * a key is only ever **added**, never renamed and never given a new
///   meaning;
/// * a reader that meets a key it does not know drops it (see
///   [parseColourKey]), exactly as `ProductKind.parse` maps an unknown kind
///   to `unknown`.
///
/// `graphite` is kept apart from `grey` because devices sell both as distinct
/// finishes ("Space Grey"/"Graphite" against a light "Grey"), and `titanium`
/// covers the natural, unpainted finish only: "Black Titanium" is `black`.
const List<String> colourKeys = [
  'black',
  'graphite',
  'grey',
  'silver',
  'white',
  'beige',
  'brown',
  'red',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
  'pink',
  'gold',
  'bronze',
  'titanium',
];

const Set<String> _known = {...colourKeys};

/// [value] as a known colour key, or null. Case and surrounding whitespace
/// are ignored; anything else not in [colourKeys] is null.
String? parseColourKey(Object? value) {
  if (value is! String) return null;
  final key = value.trim().toLowerCase();
  return _known.contains(key) ? key : null;
}

/// Throws when [key] is not one of [colourKeys]. For writers: a reader drops
/// unknown keys silently, so a writer that produces one loses data quietly.
void validateColourKey(String key) {
  if (!_known.contains(key)) {
    throw ArgumentError.value(key, 'colour', 'Not a known colour key');
  }
}

/// A list of keys as stored (an Appwrite string array) parsed into known
/// keys: unknown and repeated entries dropped, order kept. Anything that is
/// not a list reads as empty.
List<String> parseColourKeys(Object? value) {
  if (value is! List) return const [];
  final out = <String>[];
  for (final item in value) {
    final key = parseColourKey(item);
    if (key != null && !out.contains(key)) out.add(key);
  }
  return List.unmodifiable(out);
}

/// One colour a device model is sold in: the shared [key] and the
/// manufacturer's own name for it ("Midnight" for `black` on an iPhone 13).
class ModelColour {
  ModelColour({required this.key, String? label})
      : label = (label == null || label.trim().isEmpty) ? key : label.trim() {
    validateColourKey(key);
  }

  final String key;

  /// Never empty: falls back to [key] when no name was recorded.
  final String label;

  /// Pairs `colours` (keys) with `colour_labels` (names at the same
  /// positions) as a projection row stores them. Pairing is by position, so
  /// an unknown key is dropped together with its own label and never shifts
  /// the others; a missing or short label list falls back to the key.
  static List<ModelColour> fromColumns(Object? keys, Object? labels) {
    if (keys is! List) return const [];
    final names = labels is List ? labels : const [];
    final seen = <String>{};
    final out = <ModelColour>[];
    for (var i = 0; i < keys.length; i++) {
      final key = parseColourKey(keys[i]);
      if (key == null || !seen.add(key)) continue;
      final name = i < names.length ? names[i] : null;
      out.add(ModelColour(key: key, label: name is String ? name : null));
    }
    return List.unmodifiable(out);
  }

  @override
  bool operator ==(Object other) =>
      other is ModelColour && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);

  @override
  String toString() => label == key ? key : '$key ($label)';
}
