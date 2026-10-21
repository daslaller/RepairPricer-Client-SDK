## 0.2.0

Colours on parts and models. Additive only: no `catalogSnapshotVersion`
bump, and an older reader ignores every new field.

- `colourKeys`, `parseColourKey`, `parseColourKeys`, `ModelColour`: the shared
  colour vocabulary. A key is only ever added, never renamed; a reader drops
  keys it does not know. Lists parse from an Appwrite string array or the
  same list JSON-encoded in a text column.
- `ProductCatalogEntry` and `ShopProduct`: optional `colour` / `colourLabel`,
  omitted from JSON when absent, so existing records serialize unchanged.
- Snapshot columns: `colours`, `colour_labels` (devices), `offered_colours`
  (slots).

An absent colour means unplaced, never colourless: the platform leaves it
empty whenever it cannot read one with certainty.

