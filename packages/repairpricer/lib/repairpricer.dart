/// RepairPricer subscriber SDK — one dependency that gives a Dart/Flutter
/// app the whole subscriber surface: authenticate with a Team-member
/// session, read the shared catalog / offers / prices, apply per-team
/// configuration, and write config back through the admin Function.
///
/// Built on the Flutter `appwrite` client SDK, so it compiles to Flutter
/// web/mobile/desktop. Re-exports
/// [`repairpricer_contract`](../repairpricer_contract) — the pure client
/// contract — so consumers get [WinnerStrategy], [PricingConfig],
/// [SubscriberConfig], [ClientConfigBundle], the read-time margin pipeline,
/// and [VerificationStatus] from this single import.
///
/// How the *platform* derives prices — supplier ingest, slot matching,
/// service-fee derivation, price verification — is not part of the
/// subscriber surface and is not in this package.
library;

// Re-exported so a subscriber needs only this one dependency: `Client`,
// `Account` (session auth), and `Query` come from here too.
export 'package:appwrite/appwrite.dart';
export 'package:repairpricer_contract/repairpricer_contract.dart';

export 'src/catalog_tree.dart';
export 'src/client.dart';
export 'src/snapshot.dart';
export 'src/translations.dart';
export 'src/views.dart';
