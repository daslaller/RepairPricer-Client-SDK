# Changelog

Server-side prerequisites are listed per release: an SDK feature that reads a
column is inert until RepairPricer has provisioned and filled it.

## Unreleased — colours on parts and models

Contract `0.2.0`, SDK `0.3.0`. Additive only: no `catalogSnapshotVersion`
bump, and an older reader ignores every new field.

- `colourKeys`, `parseColourKey`, `parseColourKeys`, `ModelColour`: the shared
  colour vocabulary. A key is only ever added, never renamed; a reader drops
  keys it does not know.
- `OfferView.colour` / `colourLabel`, from `offer_projection.colour` /
  `colour_label`. This is what a subscriber matches sourcing rows on.
- `CatalogSlotView.offeredColours`, from `catalog_projection.offered_colours`:
  the colours a slot's offers come in, across suppliers.
- `RepairPricerDevice.colours`, from `device_projection.colours` +
  `colour_labels`: the colours a model is sold in.
- `ProductCatalogEntry` and `ShopProduct`: optional `colour` / `colourLabel`,
  omitted from JSON when absent.
- Snapshot columns: `colours`, `colour_labels` (devices), `offered_colours`
  (slots).

**Absent colour means unplaced, never colourless.** The platform leaves it
empty whenever it cannot read one with certainty.

Server prerequisites (RepairPricer): the columns above on `offer_projection`,
`catalog_projection` and `device_projection`, and the ingest that fills them.
Until then every colour reads as absent.
