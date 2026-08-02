import 'package:flutter/material.dart';
import 'package:repairpricer/repairpricer.dart';

/// Minimal Flutter-web sample that consumes the `repairpricer` SDK.
///
/// Its real job in this repo is to prove the SDK compiles to Flutter web
/// (`flutter build web`) — i.e. it drags no `dart:io` / server-SDK code. The
/// `signInAndLoad` flow shows the full subscriber quickstart end to end; it
/// is not run at startup (no live credentials in a build check).
void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RepairPricer SDK example',
      home: Scaffold(
        appBar: AppBar(title: const Text('RepairPricer subscriber SDK')),
        body: const Center(
          child: Text('SDK wired. See signInAndLoad for the quickstart.'),
        ),
      ),
    );
  }
}

/// The subscriber quickstart: authenticate with a Team-member session, then
/// read config, catalog, a slot winner, and the display price.
Future<void> signInAndLoad({required String email, required String password}) async {
  final client = Client()
    ..setEndpoint('https://appwrite.heid.se/v1')
    ..setProject('6a57c373003e0ba11db4');
  await Account(client).createEmailPasswordSession(email: email, password: password);

  final rp = RepairPricerClient(client);
  final config = await rp.loadClientConfig();

  final catalog = await rp.listCatalog(config: config, limit: 20);
  if (catalog.isEmpty) return;

  final code = catalog.first.code;
  final winner = await rp.winnerForSlot(code, config?.strategy, config);
  final priceMinor = config == null ? null : await rp.displayPriceForSlot(code, config);

  debugPrint('slot $code: winner ${winner?.supplierName}, display price $priceMinor');
}
