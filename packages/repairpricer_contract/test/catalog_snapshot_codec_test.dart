import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 7, 31, 1, 0);

  Map<String, dynamic> encode() => encodeCatalogSnapshot(
        generatedAt: generatedAt,
        devices: [
          {
            '\$id': 'dev_1', // system field — must NOT survive
            '\$permissions': ['read("label:subscriber")'],
            'device_type_name': 'Mobil',
            'manufacturer_name': 'Samsung',
            'model_name': 'Galaxy Z Fold4',
          },
        ],
        slots: [
          {
            '\$id': 'rp_1',
            'code': 'rp_1',
            'category_path': 'Mobil > Samsung > Galaxy Z Fold4 > Reparation > Speaker',
            'manufacturer_name': 'Samsung',
            'model_name': 'Galaxy Z Fold4',
            'repair_name': 'Speaker',
            'tier_name': 'OEM',
            'cost_price': 1200,
            'winning_price': 1800,
            'currency': 'SEK',
            'in_stock': true,
            'not_a_snapshot_column': 'dropped',
          },
        ],
      );

  test('round-trips through encode/decode', () {
    final data = decodeCatalogSnapshot(encode());
    expect(data.version, catalogSnapshotVersion);
    expect(data.generatedAt, generatedAt);
    expect(data.devices.single['model_name'], 'Galaxy Z Fold4');
    expect(data.slots.single['winning_price'], 1800);
  });

  test('encode strips system fields and non-whitelisted columns', () {
    final doc = encode();
    final device = (doc['devices'] as List).single as Map;
    final slot = (doc['slots'] as List).single as Map;
    expect(device.containsKey('\$id'), isFalse);
    expect(device.containsKey('\$permissions'), isFalse);
    expect(slot.containsKey('not_a_snapshot_column'), isFalse);
    expect(slot['category_path'], contains('Reparation'));
  });

  test('decode rejects a newer version than this reader understands', () {
    final doc = encode()..['version'] = catalogSnapshotVersion + 1;
    expect(() => decodeCatalogSnapshot(doc), throwsFormatException);
  });

  test('decode rejects malformed documents', () {
    expect(() => decodeCatalogSnapshot({}), throwsFormatException);
    expect(
      () => decodeCatalogSnapshot({'version': 1, 'generated_at': 'nope'}),
      throwsFormatException,
    );
    expect(
      () => decodeCatalogSnapshot(
          {'version': 1, 'generated_at': '2026-07-31T01:00:00Z'}),
      throwsFormatException, // missing devices/slots lists
    );
  });
}
