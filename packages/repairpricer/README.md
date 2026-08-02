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
      ref: v0.2.0
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

**Suppliers** (see [Working with suppliers](#working-with-suppliers))
- `listSuppliers()` → `List<SupplierInfo>`
- `listIncludedSuppliers(config)` → the ones this team hasn't excluded
- `listOffers(OfferQuery)` → offers across the catalog, not one slot
- `offersFrom(suppliers)` / `winnersFrom(suppliers)`
- `excludeSuppliers(...)` / `includeSuppliers(...)` — persistent, per team

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

## Working with suppliers

Every offer names its supplier, so you can ask supplier-shaped questions
directly rather than walking slots.

```dart
// What can we buy, and from whom?
final suppliers = await rp.listSuppliers();   // [SupplierInfo(foneday), ...]

// Everything one supplier sells, in stock.
final inStock = await rp.offersFrom({'spares'}, config: config, inStockOnly: true);

// The slots where they actually win, under YOUR strategy.
final wins = await rp.winnersFrom({'spares'}, config: config);
// → {'rp-6869': OfferView(...), ...}
```

For anything more specific, `OfferQuery` combines the filters:

```dart
await rp.listOffers(const OfferQuery(
  suppliers: {'spares', 'foneday'},
  inStockOnly: true,
), config: config);
```

### Excluding a supplier for good

A distributor that can't ship to your region shouldn't need filtering out at
every call site. Exclude it once and it applies everywhere:

```dart
await rp.excludeSuppliers({'g-sp'});
final config = await rp.loadClientConfig();   // reload to pick it up
```

From then on, every read passed that `config` — `listCatalog`,
`winnerForSlot`, `displayPriceForSlot`, `listOffers` — leaves them out. The
setting lives on the team, so it follows every user and device.

**Saved exclusions win.** Asking for an excluded supplier returns nothing
rather than quietly overriding the team's setting, and the SDK skips the
round-trip entirely when it can tell the answer is empty. When you genuinely
want to look past them (an admin or preview view), be explicit:

```dart
const OfferQuery(suppliers: {'g-sp'}, respectSavedExclusions: false)
```

### Winners: cached vs. re-selected

`OfferQuery(winnersOnly: true)` uses the platform's cached `is_winner` flag —
one query, but it reflects the *platform's* default strategy.

`winnersFrom(...)` re-runs selection under the subscriber's own
`WinnerStrategy`, so a team on `mostExpensive` gets their winners, not the
platform's. It costs two reads (candidate slots, then those slots' full offer
sets) because a winner can only be judged against its rivals. Prefer it
whenever the answer is shown to a subscriber.

## Mirroring the catalog into your own project

`loadCatalogSnapshot()` / `watchCatalog()` read RepairPricer's project
directly, which means every end-user client needs a RepairPricer session.
If your product has its own Appwrite project and many end users, the
better shape is a **mirror**: one scheduled Function in *your* project
copies the snapshot blob into *your* bucket, and your users read it with
the credentials and realtime connection they already have. One upstream
fetch per edition for your whole deployment, no second websocket in the
browser, no RepairPricer sessions for end users at all.

Create a bucket once (here `repairpricer_mirror`) with `fileSecurity:
false` and read for `Role.users()` — the catalog is deliberately
tenant-agnostic, identical for every reader, so a broad read grant on the
*mirror* leaks nothing. Then a scheduled Dart Function (`dart_appwrite`,
e.g. every 15 minutes):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/enums.dart' as enums;

Future<dynamic> main(final context) async {
  final env = Platform.environment;

  // 1. Trade your rp_live_… API token for a read session at the broker.
  //    The token stays server-side; it never reaches a browser.
  final rp = Client()
      .setEndpoint('https://appwrite.heid.se/v1')
      .setProject('6a57c373003e0ba11db4');
  final exec = await Functions(rp).createExecution(
    functionId: 'subscriber_session',
    body: jsonEncode({'token': env['REPAIRPRICER_API_TOKEN']}),
    xasync: false,
    path: '/',
    method: enums.ExecutionMethod.pOST,
    headers: {'content-type': 'application/json'},
  );
  final broker = jsonDecode(exec.responseBody) as Map<String, dynamic>;
  if (broker['ok'] != true) throw StateError('broker: ${broker['error']}');
  rp.setSession(broker['secret'] as String);

  // 2. Pull the published snapshot blob.
  final bytes = await Storage(rp)
      .getFileDownload(bucketId: 'snapshots', fileId: 'catalog_snapshot');
  String edition(List<int> gz) =>
      '${(jsonDecode(utf8.decode(gzip.decode(gz))) as Map)['generated_at']}';

  // 3. Republish in YOUR project — only when the edition actually
  //    changed, so browsers' realtime doorbells only ring for real news.
  final own = Storage(Client()
      .setEndpoint(env['APPWRITE_FUNCTION_API_ENDPOINT']!)
      .setProject(env['APPWRITE_FUNCTION_PROJECT_ID']!)
      .setKey(context.req.headers['x-appwrite-key']));
  try {
    final current = await own.getFileDownload(
        bucketId: 'repairpricer_mirror', fileId: 'catalog_snapshot');
    if (edition(current) == edition(bytes)) {
      return context.res.json({'ok': true, 'changed': false});
    }
    await own.deleteFile(
        bucketId: 'repairpricer_mirror', fileId: 'catalog_snapshot');
  } on AppwriteException catch (e) {
    if (e.code != 404) rethrow; // first run — nothing mirrored yet
  }
  await own.createFile(
    bucketId: 'repairpricer_mirror',
    fileId: 'catalog_snapshot',
    file: InputFile.fromBytes(
        bytes: bytes, filename: 'catalog_snapshot.json.gz'),
  );
  return context.res.json({'ok': true, 'changed': true});
}
```

(Function scopes: `buckets.read`, `buckets.write`, `files.read`,
`files.write`. One variable: `REPAIRPRICER_API_TOKEN`.)

Your clients then bootstrap from the mirror and treat its bucket event as
the wake-up — same file format, so `CatalogSnapshot.fromBytes` parses it
as-is:

```dart
final bytes = await Storage(ownClient).getFileDownload(
    bucketId: 'repairpricer_mirror', fileId: 'catalog_snapshot');
final snapshot = CatalogSnapshot.fromBytes(bytes);

Realtime(ownClient).subscribe(['buckets.repairpricer_mirror.files'])
  ..stream.listen((m) {
    if (m.events.any((e) => e.endsWith('.create'))) {
      // re-fetch and swap the in-memory snapshot
    }
  });
```

Skip the mirror and use `watchCatalog()` directly when your app is a
single-operator tool (the operator *is* the subscriber session) or you
have no Appwrite project of your own. This mirror pattern is what RepairX
runs in production.

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
