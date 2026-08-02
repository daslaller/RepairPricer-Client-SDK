import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'package:test/test.dart';

void main() {
  group('selectWinner', () {
    const candidates = [
      WinnerCandidate(offerId: 'a', stockPriceMinor: 10000, inStock: true),
      WinnerCandidate(offerId: 'b', stockPriceMinor: 8000, inStock: true),
      WinnerCandidate(offerId: 'c', stockPriceMinor: 12000, inStock: true),
    ];

    test('cheapest picks the lowest cost', () {
      final winner = selectWinner(candidates, WinnerStrategy.cheapest);
      expect(winner?.offerId, 'b');
    });

    test('mostExpensive picks the highest cost', () {
      final winner = selectWinner(candidates, WinnerStrategy.mostExpensive);
      expect(winner?.offerId, 'c');
    });

    test('average picks the offer closest to the mean', () {
      // mean = (10000 + 8000 + 12000) / 3 = 10000 -> offer "a" is exact.
      final winner = selectWinner(candidates, WinnerStrategy.average);
      expect(winner?.offerId, 'a');
    });

    test('prefers in-stock offers over out-of-stock ones even if cheaper', () {
      const mixed = [
        WinnerCandidate(offerId: 'cheap-oos', stockPriceMinor: 1000, inStock: false),
        WinnerCandidate(offerId: 'pricier-in-stock', stockPriceMinor: 5000, inStock: true),
      ];
      final winner = selectWinner(mixed, WinnerStrategy.cheapest);
      expect(winner?.offerId, 'pricier-in-stock');
    });

    test('falls back to out-of-stock offers when nothing is in stock', () {
      const allOos = [
        WinnerCandidate(offerId: 'a', stockPriceMinor: 1000, inStock: false),
        WinnerCandidate(offerId: 'b', stockPriceMinor: 500, inStock: false),
      ];
      final winner = selectWinner(allOos, WinnerStrategy.cheapest);
      expect(winner?.offerId, 'b');
    });

    test('returns null for no candidates', () {
      expect(selectWinner(const [], WinnerStrategy.cheapest), isNull);
    });
  });
}
