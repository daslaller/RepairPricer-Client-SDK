import 'dart:convert';

import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

ProductCatalogEntry entry({String? colour, String? colourLabel}) =>
    ProductCatalogEntry(
      productId: 'p1',
      generation: 'g1',
      supplierId: 'gsp',
      supplierSku: 'IP12039',
      title: 'iPhone 12/12 Pro Laddkontakt Flexkabel - Svart',
      currency: 'SEK',
      vatIncluded: false,
      observedAt: DateTime.utc(2026, 10, 21),
      priceContext: 'default',
      colour: colour,
      colourLabel: colourLabel,
    );

void main() {
  group('colour keys', () {
    test('parse ignores case and whitespace, drops unknown keys', () {
      expect(parseColourKey(' Black '), 'black');
      expect(parseColourKey('midnight'), isNull); // a label, not a key
      expect(parseColourKey('magenta'), isNull); // not (yet) a key
      expect(parseColourKey(3), isNull);
      expect(parseColourKey(null), isNull);
    });

    test('a list keeps order, drops unknown and repeated keys', () {
      expect(parseColourKeys(['blue', 'BLACK', 'teal', 'blue']),
          ['blue', 'black']);
      expect(parseColourKeys('black'), isEmpty);
      // The same list JSON-encoded in a text column reads the same.
      expect(parseColourKeys('["blue","BLACK","teal"]'), ['blue', 'black']);
      expect(parseColourKeys('[not json'), isEmpty);
      expect(parseColourKeys(null), isEmpty);
    });

    test('model colours pair by position, so an unknown key cannot shift a name',
        () {
      final colours = ModelColour.fromColumns(
        ['black', 'teal', 'white', 'blue'],
        ['Midnight', 'Teal', 'Starlight'],
      );
      expect(colours, [
        ModelColour(key: 'black', label: 'Midnight'),
        ModelColour(key: 'white', label: 'Starlight'),
        ModelColour(key: 'blue'), // no label recorded: falls back to the key
      ]);
      expect(colours.last.label, 'blue');
      expect(ModelColour.fromColumns(null, ['x']), isEmpty);
      expect(ModelColour.fromColumns('["black"]', '["Midnight"]'),
          [ModelColour(key: 'black', label: 'Midnight')]);
    });

    test('a model colour refuses an unknown key', () {
      expect(() => ModelColour(key: 'midnight'), throwsArgumentError);
    });
  });

  group('ProductCatalogEntry colour (additive)', () {
    test('a record without a colour serializes exactly as before', () {
      final json = entry().toJson();
      expect(json.containsKey('colour'), isFalse);
      expect(json.containsKey('colourLabel'), isFalse);
    });

    test('round-trips key and supplier label', () {
      final back = ProductCatalogEntry.fromJson(jsonDecode(
              jsonEncode(entry(colour: 'black', colourLabel: 'Svart').toJson()))
          as Map<String, dynamic>);
      expect(back.colour, 'black');
      expect(back.colourLabel, 'Svart');
    });

    test('a newer platform key reads as unplaced, label and all, never throws',
        () {
      final json = entry().toJson()
        ..['colour'] = 'teal'
        ..['colourLabel'] = 'Teal';
      final back = ProductCatalogEntry.fromJson(json);
      expect(back.colour, isNull);
      expect(back.colourLabel, isNull);
    });

    test('writers cannot produce an unknown key or a label without a colour',
        () {
      expect(() => entry(colour: 'midnight'), throwsArgumentError);
      expect(() => entry(colourLabel: 'Svart'), throwsArgumentError);
    });
  });

  group('ShopProduct colour (additive)', () {
    ShopProduct shop({String? colour, String? label}) => ShopProduct(
          productId: 'p1',
          title: 'Baksida',
          priceMinor: 100,
          currency: 'SEK',
          vatIncluded: true,
          observedAt: DateTime.utc(2026),
          colour: colour,
          colourLabel: label,
        );

    test('omitted when absent, round-trips when set', () {
      expect(shop().toJson().containsKey('colour'), isFalse);
      final back = ShopProduct.fromJson(
          shop(colour: 'red', label: '(PRODUCT)RED').toJson());
      expect(back.colour, 'red');
      expect(back.colourLabel, '(PRODUCT)RED');
    });

    test('an unknown key from a newer platform is dropped', () {
      final json = shop().toJson()
        ..['colour'] = 'teal'
        ..['colourLabel'] = 'Teal';
      expect(ShopProduct.fromJson(json).colour, isNull);
    });
  });
}
