import 'pricing_config.dart';

/// One slot's competing offer, reduced to exactly what winner selection
/// needs — the converted shop-currency cost ([stockPriceMinor]) and stock
/// state. Pure data, no Appwrite types, so this stays unit-testable.
class WinnerCandidate {
  const WinnerCandidate({required this.offerId, required this.stockPriceMinor, required this.inStock});

  final String offerId;
  final int stockPriceMinor;
  final bool inStock;
}

/// Picks the winning offer for one slot, per `docs/appwrite-handoff.md` §5:
/// among the slot's offers, choose by [WinnerStrategy] — cheapest, most
/// expensive, or whichever is closest to the average. Winner selection
/// compares [WinnerCandidate.stockPriceMinor] (converted cost), never the
/// post-margin final price — the strategy is about which *supplier* to buy
/// from, not which margin to apply.
///
/// Prefers in-stock offers when any exist (the handoff notes this is a
/// policy decision, not settled by the source data) — an all-out-of-stock
/// slot still gets a winner so a price is never silently dropped, matching
/// RepairPlugin's fallback-price behavior rather than "Price on Request" by
/// default.
///
/// Returns `null` only when [candidates] is empty.
WinnerCandidate? selectWinner(List<WinnerCandidate> candidates, WinnerStrategy strategy) {
  if (candidates.isEmpty) return null;

  final inStock = candidates.where((c) => c.inStock).toList();
  final pool = inStock.isNotEmpty ? inStock : candidates;

  switch (strategy) {
    case WinnerStrategy.cheapest:
      return pool.reduce((a, b) => a.stockPriceMinor <= b.stockPriceMinor ? a : b);
    case WinnerStrategy.mostExpensive:
      return pool.reduce((a, b) => a.stockPriceMinor >= b.stockPriceMinor ? a : b);
    case WinnerStrategy.average:
      final mean = pool.map((c) => c.stockPriceMinor).reduce((a, b) => a + b) / pool.length;
      return pool.reduce(
        (a, b) => (a.stockPriceMinor - mean).abs() <= (b.stockPriceMinor - mean).abs() ? a : b,
      );
  }
}
