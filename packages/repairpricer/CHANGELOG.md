## 0.2.0

Supplier-centric queries. Previously every offer read was keyed on a single
slot `code`, so "which parts does this supplier sell?" meant one request per
slot. Adds:

- `listSuppliers()` / `listIncludedSuppliers(config)` — the supplier list, so
  a "which suppliers do we buy from?" settings screen can be populated. Reads
  the shared `suppliers` table; active only by default.
- `listOffers(OfferQuery)` — offers across the whole catalog, filtered by
  supplier (include and exclude), stock, winner flag, or slot set.
- `offersFrom(suppliers)` — shorthand for the common case.
- `winnersFrom(suppliers)` — slots a supplier actually wins, re-selected
  under the subscriber's own `WinnerStrategy` rather than the platform's
  cached `is_winner` flag.
- `excludeSuppliers(...)` / `includeSuppliers(...)` — batch, persistent
  per-team supplier exclusions (the region-locked-distributor case).

A team's saved supplier exclusions apply to all of these automatically and
take precedence over per-call filters, so a tenant that has excluded a
supplier cannot have it re-enabled by a stray call. Opt out deliberately with
`OfferQuery(respectSavedExclusions: false)`.

**Requires** the `key_supplier_name` index on `offer_projection` and subscriber
read on `suppliers` — both ship in the RepairPricer provisioning tool. Without
them these calls still work but scan, and `listSuppliers()` returns empty.

## 0.1.0

- First public release. Extracted from the closed RepairPricer monorepo as a
  standalone package so subscribers can depend on it without access to the
  commercial product.
- Now depends on `repairpricer_contract` instead of the private
  `repairpricer_core`. The re-exported surface loses the platform-only
  service-fee calculator (`ServiceFeeCalculator`, `resolveServiceFeeForSync`);
  `VerificationStatus` / `VerificationLevel` are unchanged and still exported.
