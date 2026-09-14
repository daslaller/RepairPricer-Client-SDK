import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:repairpricer_contract/repairpricer_contract.dart';
import 'products.dart';

/// Session-authenticated shop management. The server verifies the selected
/// team's product entitlement and owner/admin role on every call. No keys.
class ShopAdminClient {
  ShopAdminClient(Client client, {String functionId = 'shop_admin'})
      : _transport = ((body) async {
          final result = await Functions(client).createExecution(
              functionId: functionId, body: jsonEncode(body), xasync: false);
          return Map<String, dynamic>.from(
              jsonDecode(result.responseBody) as Map);
        });
  ShopAdminClient.withTransport(this._transport);
  final ShopTransport _transport;
  Future<Map<String, dynamic>> call(String action,
      {String? teamId, Map<String, Object?> fields = const {}}) async {
    final result =
        await _transport({...fields, 'action': action, 'teamId': teamId});
    if (result['ok'] != true) {
      throw ShopException(
          result['error'] as String? ?? 'Shop management unavailable');
    }
    return result;
  }

  Future<Map<String, dynamic>> load({String? teamId}) =>
      call('load', teamId: teamId);
  Future<Map<String, dynamic>> saveSettings(ShopSettings settings,
          {String? teamId, required int revision}) =>
      call('saveSettings',
          teamId: teamId,
          fields: {'settings': settings.toJson(), 'revision': revision});
  Future<Map<String, dynamic>> saveProduct(ManagedShopProduct product,
          {String? teamId, required int revision}) =>
      call('saveProduct',
          teamId: teamId,
          fields: {'product': product.toJson(), 'revision': revision});
  Future<Map<String, dynamic>> removeProduct(String productId,
          {String? teamId, required int revision}) =>
      call('removeProduct',
          teamId: teamId,
          fields: {'productId': productId, 'revision': revision});
  Future<Map<String, dynamic>> connectStripe({String? teamId}) =>
      call('connectStripe', teamId: teamId);
  Future<Map<String, dynamic>> stripeStatus({String? teamId}) =>
      call('stripeStatus', teamId: teamId);
  Future<Map<String, dynamic>> enrichImages(String productId,
          {String? teamId, String? productPageUrl, required int revision}) =>
      call('enrichImages', teamId: teamId, fields: {
        'productId': productId,
        'productPageUrl': productPageUrl,
        'revision': revision
      });
}
