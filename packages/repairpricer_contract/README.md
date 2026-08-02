# repairpricer_contract

The pure-Dart **RepairPricer client contract** — the types and read-time math
that a subscriber's app and the RepairPricer platform must agree on.

You normally do **not** depend on this directly. Add
[`repairpricer`](../repairpricer), which re-exports all of it.

It exists as its own package because both sides need it and neither can
depend on the other: the Flutter SDK is public and Flutter-bound, the server
engine is closed and pure Dart. One shared package means the margin pipeline
and winner selection cannot drift between what the platform computes and what
a subscriber's app renders.

No Appwrite, no Flutter, no `dart:io` — it stays web-safe and testable
without a server.

## Contents

- `PricingConfig`, `MarginType`, `RoundingMethod`, `WinnerStrategy`
- `computeOfferPricing(...)` — the read-time FX → margin → tax → rounding pipeline
- `selectWinner(...)` / `WinnerCandidate` — which supplier offer wins a slot
- `SubscriberConfig`, `ClientConfigBundle`, `FilterRule`/`FilterKind`, `TierNameOverride`, `PricingMode`, `WidgetTheme`
- `encodeCatalogSnapshot` / `decodeCatalogSnapshot` — the catalog snapshot shape
- `VerificationStatus`, `VerificationLevel` — the badge vocabulary

Everything here runs **client-side** in a subscriber's app and is compiled
into their JavaScript bundle. It is published as source rather than treated as
a secret. What decides *platform* prices — supplier ingest, slot matching,
service-fee derivation, price verification — is not part of the contract and
is not in this package.

## Tests

```bash
dart test
```

## License

MIT — see [LICENSE](LICENSE).
