/// The RepairPricer **client contract**: the pure-Dart types and read-time
/// math that a subscriber's app and the RepairPricer platform must agree on.
///
/// This package is deliberately small and dependency-free (no Appwrite, no
/// Flutter, no `dart:io`) so both sides can share one definition instead of
/// keeping parallel copies that drift:
///
/// * the [`repairpricer`](https://github.com/daslaller/RepairPricer-Client-SDK)
///   Flutter SDK, which subscribers depend on, and
/// * the RepairPricer server engine, which is closed-source.
///
/// Everything here executes **client-side** in a subscriber's app today — it
/// is compiled into their JavaScript bundle — so it is published as source
/// rather than pretending to be a secret. What decides *platform* prices
/// (supplier ingest, slot matching, service-fee derivation, verification) is
/// not part of the contract and is not in this package.
///
/// Most consumers do not depend on this directly: add `repairpricer`, which
/// re-exports all of it.
library;

export 'src/catalog_snapshot_codec.dart';
export 'src/pricing_config.dart';
export 'src/pricing_pipeline.dart';
export 'src/subscriber_config.dart';
export 'src/verification.dart';
export 'src/winner_selector.dart';
