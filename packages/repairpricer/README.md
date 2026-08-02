# repairpricer

The RepairPricer **subscriber SDK** — one dependency that gives a Dart/Flutter
app the whole subscriber surface: authenticate with a Team-member session,
read the shared catalog / offers / prices, apply your per-team configuration,
and write that configuration back.

Built on the Flutter `appwrite` **client** SDK, so it compiles to Flutter
web/mobile/desktop. It drags no `dart:io`, no server SDK (`dart_appwrite`),
and none of the RepairPricer crawlers — just the read/write surface a
subscriber needs.

## The model

RepairPricer is **read-through-a-session**: you authenticate as a Team-member
user and read shared, pre-computed projection rows under row security. There
is no REST surface and no server to run — this SDK is a thin typed reader (and
a Function-backed writer) over the Appwrite project.

> **Never ship the project API key to a client.** A key bypasses the row
> security that isolates each team. This SDK only ever uses a user *session*;
> it has no code path that accepts an API key.

| | |
|---|---|
| Endpoint | `https://appwrite.heid.se/v1` |
| Project | `6a57c373003e0ba11db4` |
| Database | `repair_pricer` |

What RepairPricer does **not** do, by design — these are yours: convert
supplier currency to your shop currency (offers are stored in the currency
they were fetched in), apply your margin/tax/rounding (or let the SDK do it in
`custom` pricing mode), and link your products to slots.

## Install

This package is distributed as a **public git dependency** — it is not on
pub.dev. No credentials or token are required.

```yaml
dependencies:
  repairpricer:
    git:
      url: https://github.com/daslaller/RepairPricer-Client-SDK
      path: packages/repairpricer
      ref: v0.1.0
```

Pin a release tag, as above — `ref: main` floats, so an upstream push would
change what your build resolves to without you touching anything. Bump the
tag deliberately, then `flutter pub upgrade repairpricer` and commit your
lockfile.

`Client`, `Account`, and `Query` are re-exported from this package, so this
one import is all you need.

## Quickstart

```dart
import 'package:repairpricer/repairpricer.dart';

final client = Client()
  ..setEndpoint('https://appwrite.heid.se/v1')
  ..setProject('6a57c373003e0ba11db4');

// Session auth — never an API key.
await Account(client).createEmailPasswordSession(
  email: '<your-subscriber-email>',
  password: '<your-password>',
);

final rp = RepairPricerClient(client);

// Per-team configuration (pricing mode, strategy, filters, tier renames).
final config = await rp.loadClientConfig();

// Browse the shared catalog — exclusions and tier labels applied per config.
final catalog = await rp.listCatalog(config: config, limit: 50);

// Pick a slot winner among every supplier offer, by your strategy.
final winner = await rp.winnerForSlot('rp-6869', config?.strategy, config);

// The price you should DISPLAY for a slot, per your config
// (platform winning price, or your own margin pipeline in custom mode).
final priceMinor =
    config == null ? null : await rp.displayPriceForSlot('rp-6869', config);
```

For the whole catalog in one fetch, prefer the snapshot:

```dart
final snapshot = await rp.loadCatalogSnapshot();   // ~one static file
final live = rp.watchCatalogSnapshot();            // re-emits on each sync
```

## What you get

**Reads**
- `loadClientConfig()` → `ClientConfigBundle?` (config row + filter rules + tier renames)
- `loadCatalogSnapshot()` / `watchCatalogSnapshot()` → the whole catalog in one fetch
- `listCatalog(...)` → `List<CatalogSlotView>` (search, paging, config-aware exclusions + labels)
- `getCatalogSlot(code)` → `CatalogSlotView?`
- `listOffersForSlot(code, ...)` → `List<OfferView>` (every supplier offer)
- `winnerForSlot(code, [strategy, config])` → `OfferView?`
- `displayPriceForSlot(code, config)` → `int?` (minor units)
- `listDevices(...)` → `List<RepairPricerDevice>` (the "which models" surface)
- `loadTranslations()` → `TranslationDictionary`

**Writes** (routed through the `subscriber_config_admin` Function — the tables
have no client write permission)
- `saveConfig(fields)` / `saveWidgetSettings(fields)`
- `regenerateWidgetKey()`
- `addFilterRule(kind, value)` / `removeFilterRule(kind, value)`
- `setTierNames(tierKey:, en:, sv:)`

**Pure logic** (re-exported from
[`repairpricer_contract`](../repairpricer_contract)): `WinnerStrategy`,
`PricingConfig`, `computeOfferPricing`, `selectWinner`, `SubscriberConfig`,
`ClientConfigBundle`, `FilterRule`/`FilterKind`, `VerificationStatus`.

## Money & currency

All money is **minor units** (öre/cents). Offers are stored in the currency
they were fetched in (`OfferView.currency`) — convert client-side with
`OfferView.costInTargetMinor(rate)`. `winnerForSlot` compares converted cost
and prefers in-stock offers.

## Scope

This package is the **client contract only**: models, the HTTP/Appwrite
client, session auth, and the read-time math that runs in your app. How the
platform *produces* prices — supplier ingest and crawling, slot matching,
service-fee derivation, AI price verification — is not part of the subscriber
surface and is not distributed here.

## Example

`example/` is a minimal Flutter-web app that consumes the SDK and builds with
`flutter build web` — the proof that the SDK carries no `dart:io`
entanglement.

## Tests

```bash
flutter test
```

Covers the read-projection mapping, config application (platform/custom), and
winner selection over canned offer rows.

## License

MIT — see [LICENSE](LICENSE).
