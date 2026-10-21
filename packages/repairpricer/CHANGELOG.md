## 0.3.0

Colours on parts and models (contract 0.2.0).

- `OfferView.colour` / `colourLabel`, from `offer_projection.colour` /
  `colour_label`. This is what a subscriber matches sourcing rows on.
- `CatalogSlotView.offeredColours`, from `catalog_projection.offered_colours`:
  the colours a slot's offers come in, across suppliers.
- `RepairPricerDevice.colours`, from `device_projection.colours` +
  `colour_labels`: the colours a model is sold in.

Server prerequisites (RepairPricer): those columns, and the pricing pass that
fills them. Until then every colour reads as absent.

