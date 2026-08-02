import 'package:flutter_test/flutter_test.dart';
import 'package:repairpricer/repairpricer.dart';

/// Pure coverage of the depth-window aggregation behind
/// `RepairPricerClient.getCatalogs`. The client method is a thin wrapper:
/// pick a projection, push filter segments down, then run these exact
/// functions over the returned paths — so proving them here proves the
/// windowing without a live Appwrite.
void main() {
  const paths = [
    'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Speaker',
    'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Display',
    'Mobil > Samsung > Galaxy S10 > Reparation > Display',
    'Mobil > Apple > iPhone 12 > Reparation > Display',
    'Surfplatta > Apple > iPad Air > Reparation > Batteri',
  ];

  List<List<String>> split() => [for (final p in paths) splitCategoryPath(p)];

  group('splitCategoryPath', () {
    test('splits on > and trims whitespace', () {
      expect(
        splitCategoryPath('Mobil > Samsung >  Galaxy Z Fold4 '),
        ['Mobil', 'Samsung', 'Galaxy Z Fold4'],
      );
    });

    test('empty and blank input give an empty list', () {
      expect(splitCategoryPath(''), isEmpty);
      expect(splitCategoryPath('  '), isEmpty);
    });
  });

  group('aggregateCatalogPaths', () {
    test('single-level window returns distinct nodes with counts', () {
      final nodes = aggregateCatalogPaths(
        split(),
        depth: CatalogLevel.manufacturer,
        maxDepth: CatalogLevel.manufacturer,
      );
      expect([for (final n in nodes) n.name], ['Apple', 'Samsung']);
      expect([for (final n in nodes) n.count], [2, 3]);
    });

    test('depth 3 to leaf skips the first two levels (the user story)', () {
      final nodes = aggregateCatalogPaths(
        split(),
        depth: 3,
        filter: const ['Mobil', 'Samsung'],
      );
      expect(
        [for (final n in nodes) n.joined],
        [
          'Galaxy S10 > Reparation > Display',
          'Galaxy Z Fold4 > Reparation > Display',
          'Galaxy Z Fold4 > Reparation > Speaker',
        ],
      );
    });

    test('window can span levels and merges equal sub-paths', () {
      final nodes = aggregateCatalogPaths(
        split(),
        depth: CatalogLevel.deviceType,
        maxDepth: CatalogLevel.manufacturer,
      );
      expect(
        {for (final n in nodes) n.joined: n.count},
        {
          'Mobil > Apple': 1,
          'Mobil > Samsung': 3,
          'Surfplatta > Apple': 1,
        },
      );
    });

    test('filter matches case-insensitively, output keeps original casing',
        () {
      final nodes = aggregateCatalogPaths(
        split(),
        depth: 3,
        maxDepth: 3,
        filter: const ['mobil', 'samsung'],
      );
      expect(
        [for (final n in nodes) n.name],
        ['Galaxy S10', 'Galaxy Z Fold4'],
      );
    });

    test('paths shorter than the window are dropped', () {
      final nodes = aggregateCatalogPaths(
        [
          ['Mobil'],
          ['Mobil', 'Samsung'],
        ],
        depth: 3,
      );
      expect(nodes, isEmpty);
    });

    test('maxDepth 0 means to-the-leaf', () {
      final nodes = aggregateCatalogPaths(
        split(),
        depth: 1,
        filter: const ['Surfplatta'],
      );
      expect(nodes.single.joined,
          'Surfplatta > Apple > iPad Air > Reparation > Batteri');
    });

    test('rejects invalid windows', () {
      expect(() => aggregateCatalogPaths(const [], depth: 0),
          throwsArgumentError);
      expect(() => aggregateCatalogPaths(const [], depth: 3, maxDepth: 2),
          throwsArgumentError);
    });
  });
}
