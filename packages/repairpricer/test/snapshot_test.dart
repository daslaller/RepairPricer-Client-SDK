import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repairpricer/repairpricer.dart';

/// Proves the SDK can consume exactly what the engine's snapshot writer
/// produces (same core codec + gzip framing), and that the snapshot answers
/// depth windows identically to the live path's routing rules.
void main() {
  Uint8List engineBytes() {
    // Mirrors CatalogSnapshotWriter: encodeCatalogSnapshot → JSON → gzip.
    final doc = encodeCatalogSnapshot(
      generatedAt: DateTime.utc(2026, 7, 31, 1, 0),
      devices: [
        {
          'device_type_name': 'Mobil',
          'manufacturer_name': 'Samsung',
          'model_name': 'Galaxy Z Fold4',
        },
        {
          'device_type_name': 'Mobil',
          'manufacturer_name': 'Samsung',
          'model_name': 'Galaxy S10',
        },
        {
          'device_type_name': 'Mobil',
          'manufacturer_name': 'Apple',
          'model_name': 'iPhone 12',
        },
        // A device with no priced slots yet — must still appear in
        // device-level windows.
        {
          'device_type_name': 'Surfplatta',
          'manufacturer_name': 'Apple',
          'model_name': 'iPad Air',
        },
      ],
      slots: [
        {
          'code': 'rp_1',
          'category_path':
              'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Speaker',
          'model_name': 'Galaxy Z Fold4',
          'repair_name': 'Speaker',
          'tier_name': 'OEM',
          'cost_price': 1200,
          'winning_price': 1800,
          'in_stock': true,
        },
        {
          'code': 'rp_2',
          'category_path':
              'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Display',
          'model_name': 'Galaxy Z Fold4',
          'repair_name': 'Display',
          'tier_name': 'OEM',
          'cost_price': 2400,
          'winning_price': 3600,
          'in_stock': true,
        },
      ],
    );
    return Uint8List.fromList(
        const GZipEncoder().encode(utf8.encode(jsonEncode(doc))));
  }

  test('fromBytes parses the engine wire format into typed views', () {
    final snap = CatalogSnapshot.fromBytes(engineBytes());
    expect(snap.generatedAt, DateTime.utc(2026, 7, 31, 1, 0));
    expect(snap.devices, hasLength(4));
    expect(snap.slots, hasLength(2));
    expect(snap.slots.first.winningPriceMinor, 1800);
    expect(snap.slots.first.categoryPath, contains('Reparation'));
  });

  test('fromBytes rejects garbage and newer versions', () {
    expect(() => CatalogSnapshot.fromBytes(Uint8List.fromList([1, 2, 3])),
        throwsA(anything));
    final newer = jsonDecode(utf8.decode(const GZipDecoder()
        .decodeBytes(engineBytes()))) as Map<String, dynamic>;
    newer['version'] = catalogSnapshotVersion + 1;
    final bytes = Uint8List.fromList(
        const GZipEncoder().encode(utf8.encode(jsonEncode(newer))));
    expect(() => CatalogSnapshot.fromBytes(bytes), throwsFormatException);
  });

  group('applyCatalogChanges (the delta layer)', () {
    late CatalogSnapshot base;
    setUp(() => base = CatalogSnapshot.fromBytes(engineBytes()));

    test('upserts a new slot and updates an existing one by code', () {
      final next = applyCatalogChanges(base, upsertSlots: [
        {'code': 'rp_1', 'winning_price': 2000, 'model_name': 'Galaxy Z Fold4',
         'repair_name': 'Speaker', 'category_path': 'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Speaker'},
        {'code': 'rp_9', 'winning_price': 500, 'model_name': 'iPhone 12',
         'repair_name': 'Batteri', 'category_path': 'Mobil > Apple > iPhone 12 > Reparation > Batteri'},
      ]);
      expect(next.slots, hasLength(3));
      expect(next.slots.firstWhere((s) => s.code == 'rp_1').winningPriceMinor, 2000);
      expect(next.slots.any((s) => s.code == 'rp_9'), isTrue);
      expect(base.slots, hasLength(2)); // immutably applied
    });

    test('deletes by code / device key; unknown deletes are no-ops', () {
      final next = applyCatalogChanges(base,
          deleteSlots: [{'code': 'rp_2'}, {'code': 'nope'}],
          deleteDevices: [
            {'manufacturer_name': 'Apple', 'model_name': 'iPad Air'},
            {'manufacturer_name': 'Ghost', 'model_name': 'Phone'},
          ]);
      expect(next.slots.map((s) => s.code), ['rp_1']);
      expect(next.devices, hasLength(3));
    });

    test('replaying the same change is idempotent', () {
      final change = [
        {'code': 'rp_1', 'winning_price': 2100, 'model_name': 'Galaxy Z Fold4',
         'repair_name': 'Speaker', 'category_path': 'x'},
      ];
      final once = applyCatalogChanges(base, upsertSlots: change);
      final twice = applyCatalogChanges(once, upsertSlots: change);
      expect(twice.slots.length, once.slots.length);
      expect(twice.slots.firstWhere((s) => s.code == 'rp_1').winningPriceMinor, 2100);
    });
  });

  group('catalogNodesFromSnapshot', () {
    late CatalogSnapshot snap;
    setUp(() => snap = CatalogSnapshot.fromBytes(engineBytes()));

    test('device-level window comes from devices, not slots', () {
      final nodes = catalogNodesFromSnapshot(
        snap,
        depth: CatalogLevel.manufacturer,
        maxDepth: CatalogLevel.manufacturer,
      );
      // Apple appears (2 devices) even though it has zero priced slots.
      expect({for (final n in nodes) n.name: n.count},
          {'Apple': 2, 'Samsung': 2});
    });

    test('repair-level window walks slot category paths (the user story)',
        () {
      final nodes = catalogNodesFromSnapshot(
        snap,
        filter: const ['Mobil', 'Samsung'],
        depth: 3,
      );
      expect(
        [for (final n in nodes) n.joined],
        [
          'Galaxy Z Fold4 > Reparation > Display',
          'Galaxy Z Fold4 > Reparation > Speaker',
        ],
      );
    });
  });
}