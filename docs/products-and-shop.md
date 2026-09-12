# Products, shop management and checkout

RepairPricer has two independent catalog surfaces. The existing device/repair
API and booking widget describe repairs. `RepairPricerClient.products` describes
sellable products, with no required device, repair or tier. Access requires a
Product Catalog subscription for the authenticated subscriber team.

These additions are on the product-catalog development branch; they are not in
the existing v0.2.0 tag. Pin the reviewed commit when testing them.

## Subscriber product catalog

Use an authenticated **team member session** (including a backend subscriber
session). Repair-widget read delegates intentionally cannot download the product
catalog. Access is checked on every request, including subscription expiry.
Do not put a subscriber token or team member session in an anonymous shop.

```dart
final rp = RepairPricerClient(appwriteClient);
final editions = await rp.products.listEditions(teamId: teamId);
final edition = editions.first;
String? cursor;
do {
  final page = await rp.products.listProducts(
    edition: edition, teamId: teamId, limit: 100, cursorAfter: cursor,
  );
  for (final product in page.products) {
    // Licensed sourcing information; do not send these objects to shoppers.
    print('${product.productId}: ${product.title}');
  }
  cursor = page.nextCursor;
} while (cursor != null);
```

Keep the same edition across pages. A refresh can publish a new generation while
you browse. If an old edition has been retired, restart from `listEditions`.
Search, category and `ProductKind` filters are optional. Unknown classification
does not discard a product. Identity is `productId`, never title or model code:
different capacity, generation or condition can remain separate products even
when the supplier reuses the same model code. `modelCode` is unverified source
text; it does not establish compatibility.

`ProductCatalogEntry` contains supplier/account price context, purchase price,
currency and an explicit VAT basis. `ShopProduct` is a separate public DTO with
the merchant's retail price; it has no supplier cost, account or margin fields.
All money is integer minor units. Neither type silently converts currencies.

## Shop browsing, cart and checkout

Inject a transport to the configured public shop endpoint. The web widget uses
the same requests and responses. An HTTP transport must POST JSON and decode the
response; never embed an admin key. If using an Appwrite Function transport:

```dart
final shop = ShopClient(
  widgetKey: publicWidgetKey,
  transport: (request) async {
    final execution = await Functions(publicAppwriteClient).createExecution(
      functionId: 'shop_resolve', body: jsonEncode(request), xasync: false,
    );
    return Map<String, dynamic>.from(jsonDecode(execution.responseBody) as Map);
  },
);
final page = await shop.listProducts(search: 'Laptop');
final cart = ShopCart();
cart.add(page.products.first); // Refuses unavailable stock and quantity limits.

await shop.checkout(cart, (handoff) async {
  // The application owns this method and the merchant's checkout screen.
  // Display handoff.quote for review; its merchandise subtotal excludes shipping.
  await merchantBackend.startCheckout(handoff.toCheckoutRequest());
});
```

The checkout request contains only `widgetKey` and `{productId, quantity}` lines.
The backend must resolve its own shop, validate the cart again, obtain current
authoritative retail prices/stock, add shipping and payment rules, then create
its own checkout. Ignore amounts or quotes supplied by a browser. A quote is a
short-lived display result, **not a signed authorization, stock reservation,
order, or payment**. Daily supplier catalog stock can change before fulfillment;
the merchant decides the final availability check and fulfillment policy.

`ShopClient.quote` verifies the exact requested identities/quantities, line
totals, aggregate, currency, VAT basis and expiry. Exceptions must be displayed
to the shopper. Calling `checkout` does not purchase anything from a supplier.
Origin restrictions configured by the shop must match the browser transport;
they are embedding controls, not authentication for a public widget key.

Repair configuration, pricing math and booking APIs remain separate.
## Shop management and optional Stripe checkout

`ShopAdminClient` is the authenticated owner/admin surface for a shop team.
It manages a selected supplier assortment, merchant-owned products, nested
bundles and shop settings independently of repair configuration. The private
server verifies membership, management role and product entitlement per call.
Subscribers cannot grant themselves an entitlement or set supplier costs/stock.

`ManagedShopProduct` distinguishes `supplier`, `own`, and `bundle` sources.
Bundles reference other products in the same shop with positive quantities;
the server rejects missing references and cycles. `ShopPriceRule` supports a
shop default, fixed display price, markup on cost and profit margin on selling
price. Rates use basis points and money uses integer minor units. The public
contract implements the same integer pricing math used by the server.

Save methods require the revision from `load()`. A conflict requires reloading
the shop before retrying. Console settings include VAT, allowed website origins,
retail pricing, shipping and `ShopCheckoutMode.merchant` or `.stripe`.

The merchant mode keeps the existing checkout callback. With Stripe,
`connectStripe()` requests a server-generated onboarding URL; `stripeStatus()`
returns readiness without exposing keys. The platform must configure its
server integration and webhook before live use. No Stripe secret belongs in
this Flutter SDK. The merchant remains responsible for fulfillment.

`ShopClient.stripeCheckout(lines, requestId: ..., expectedSubtotalMinor: ...)`
returns a validated Stripe Checkout URL. Generate a unique request ID for a new
cart and keep the same ID and payload when retrying an interrupted request.
The server independently re-prices and checks stock. Retry that checkout call
directly: a fresh quote may see stock held by the earlier attempt. `orders`,
`reconcileOrder` and `fulfillOrder` are available through `ShopAdminClient.call`.
Payment confirmation comes from the server's verified webhook, never a redirect.

If `ShopException.resetCheckout` is true, that attempt is finished or rejected
before a session was created. Re-quote, let the shopper review changes, and use a
new request ID. For timeouts and other ambiguous errors, retry the same request
ID and payload. Do not automatically create a second checkout attempt.

Owner/admin calls can use `call('previewProduct', fields: {'product': ...})` to
preview a draft using authoritative costs. `enrichImages` accepts an optional
canonical product page URL when a supplier's short SKU route is unavailable.
Own stock means total units stocked; the server deducts committed managed orders.
Custom checkout backends own their stock reservations and order workflow.
