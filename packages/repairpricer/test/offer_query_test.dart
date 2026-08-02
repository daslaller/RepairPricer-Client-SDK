import 'package:flutter_test/flutter_test.dart';
import 'package:repairpricer/repairpricer.dart';

/// Query-building and winner re-selection, over canned rows. These are the
/// parts with rules in them — the Appwrite round-trip is not what breaks.
void main() {
  ClientConfigBundle bundleExcluding(List<String> suppliers) {
    return ClientConfigBundle(
      config: SubscriberConfig.defaults(teamId: 't1'),
      filterRules: [
        for (final s in suppliers)
          FilterRule(kind: FilterKind.supplier, value: s),
      ],
      tierNames: const [],
    );
  }

  group('OfferQuery.toQueries', () {
    test('empty query filters nothing', () {
      final queries = const OfferQuery().toQueries(null);
      expect(queries, isNotNull);
      expect(queries, isEmpty);
    });

    test('includes are one equal() so the supplier index can serve them', () {
      final queries = const OfferQuery(suppliers: {'spares'}).toQueries(null)!;
      expect(queries, hasLength(1));
      expect(queries.single, contains('supplier_name'));
      expect(queries.single, contains('spares'));
    });

    test("a team's saved exclusions apply even when the caller passed none", () {
      final queries =
          const OfferQuery().toQueries(bundleExcluding(['g-sp']))!;
      expect(queries.single, contains('g-sp'));
      expect(queries.single, contains('notEqual'));
    });

    test('saved exclusions win over a caller asking for that supplier', () {
      // The region-lock case: a tenant excluded g-sp, so a stray call asking
      // for it must not quietly re-enable it.
      final queries = const OfferQuery(suppliers: {'g-sp'})
          .toQueries(bundleExcluding(['g-sp']));
      expect(queries, isNull, reason: 'knowably empty — skip the round-trip');
    });

    test('respectSavedExclusions: false opts out deliberately', () {
      final queries = const OfferQuery(
        suppliers: {'g-sp'},
        respectSavedExclusions: false,
      ).toQueries(bundleExcluding(['g-sp']))!;
      expect(queries.single, contains('g-sp'));
      expect(queries.single, contains('equal'));
    });

    test('a partially-excluded include set keeps the survivors', () {
      final queries = const OfferQuery(suppliers: {'spares', 'g-sp'})
          .toQueries(bundleExcluding(['g-sp']))!;
      expect(queries.single, contains('spares'));
      expect(queries.single, isNot(contains('g-sp')));
    });

    test('effectiveExclusions merges caller and saved rules', () {
      final effective = const OfferQuery(excludeSuppliers: {'foneday'})
          .effectiveExclusions(bundleExcluding(['g-sp']));
      expect(effective, {'foneday', 'g-sp'});
    });

    test('stock and winner flags are additive', () {
      final queries = const OfferQuery(inStockOnly: true, winnersOnly: true)
          .toQueries(null)!;
      expect(queries, hasLength(2));
      expect(queries.join(), contains('in_stock'));
      expect(queries.join(), contains('is_winner'));
    });
  });

  group('winner re-selection over a supplier set', () {
    // Mirrors what winnersFrom does client-side once the rows are in hand.
    Map<String, OfferView> winnersAmong(
      List<Map<String, dynamic>> rows,
      Set<String> suppliers,
      WinnerStrategy strategy,
    ) {
      final offers = [for (final r in rows) OfferView.fromRow(r)];
      final bySlot = <String, List<OfferView>>{};
      for (final o in offers) {
        (bySlot[o.code] ??= []).add(o);
      }
      final winners = <String, OfferView>{};
      for (final entry in bySlot.entries) {
        final byId = {for (final o in entry.value) o.offerId: o};
        final winner = selectWinner(
          [
            for (final o in entry.value)
              WinnerCandidate(
                offerId: o.offerId,
                stockPriceMinor: o.costPriceMinor,
                inStock: o.inStock,
              ),
          ],
          strategy,
        );
        final view = winner == null ? null : byId[winner.offerId];
        if (view != null && suppliers.contains(view.supplierName)) {
          winners[entry.key] = view;
        }
      }
      return winners;
    }

    final rows = [
      // slot-1: supplier-a is cheapest
      {'code': 'slot-1', 'offer_id': 'a1', 'supplier_name': 'supplier-a', 'cost_price': 900, 'in_stock': true},
      {'code': 'slot-1', 'offer_id': 'b1', 'supplier_name': 'supplier-b', 'cost_price': 1500, 'in_stock': true},
      // slot-2: supplier-b is cheapest
      {'code': 'slot-2', 'offer_id': 'a2', 'supplier_name': 'supplier-a', 'cost_price': 2000, 'in_stock': true},
      {'code': 'slot-2', 'offer_id': 'b2', 'supplier_name': 'supplier-b', 'cost_price': 1200, 'in_stock': true},
    ];

    test('returns only the slots the asked-for supplier actually wins', () {
      final winners = winnersAmong(rows, {'supplier-a'}, WinnerStrategy.cheapest);
      expect(winners.keys, ['slot-1']);
      expect(winners['slot-1']!.offerId, 'a1');
    });

    test('strategy changes who wins — the platform flag would not', () {
      // The reason winnersFrom re-selects instead of trusting is_winner: a
      // team on mostExpensive has a different winner than the cached one.
      final winners = winnersAmong(rows, {'supplier-a'}, WinnerStrategy.mostExpensive);
      expect(winners.keys, ['slot-2'], reason: 'supplier-a is dearest on slot-2');
    });

    test('judging against rivals matters — a filtered set would over-report', () {
      // If winnersFrom had only fetched supplier-a's rows, supplier-a would
      // have "won" both slots by default. It must see supplier-b to lose.
      final onlyA = rows.where((r) => r['supplier_name'] == 'supplier-a').toList();
      final naive = winnersAmong(onlyA, {'supplier-a'}, WinnerStrategy.cheapest);
      expect(naive.keys, hasLength(2), reason: 'demonstrates the wrong answer');

      final correct = winnersAmong(rows, {'supplier-a'}, WinnerStrategy.cheapest);
      expect(correct.keys, hasLength(1));
    });

    test('an out-of-stock cheaper offer loses to an in-stock dearer one', () {
      final winners = winnersAmong([
        {'code': 's', 'offer_id': 'x', 'supplier_name': 'supplier-a', 'cost_price': 100, 'in_stock': false},
        {'code': 's', 'offer_id': 'y', 'supplier_name': 'supplier-b', 'cost_price': 800, 'in_stock': true},
      ], {'supplier-b'}, WinnerStrategy.cheapest);
      expect(winners['s']!.offerId, 'y');
    });
  });

  group('SupplierInfo', () {
    test('maps a row', () {
      final s = SupplierInfo.fromRow({
        'external_id': 'sup-1',
        'name': 'supplier-a',
        'currency': 'EUR',
        'is_active': true,
      });
      expect(s.externalId, 'sup-1');
      expect(s.name, 'supplier-a');
      expect(s.currency, 'EUR');
      expect(s.isActive, isTrue);
    });

    test('tolerates a legacy row missing is_active', () {
      expect(SupplierInfo.fromRow({'name': 'x'}).isActive, isTrue);
    });
  });
}
