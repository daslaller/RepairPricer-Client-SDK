# RepairPricer SDK

The public client SDK for RepairPricer. Subscribers depend on this
repository; it contains no part of the commercial product's server side.

Two packages:

| Package | What it is |
|---|---|
| [`packages/repairpricer`](packages/repairpricer) | The Flutter subscriber SDK. **This is the one you depend on.** |
| [`packages/repairpricer_contract`](packages/repairpricer_contract) | The pure-Dart client contract it is built on — pricing config, the read-time margin pipeline, winner selection, the snapshot codec. Pulled in transitively; you do not add it yourself. |

## Install

Distributed as a **public git dependency** — not on pub.dev. No token, no
credential helper, nothing to configure.

```yaml
dependencies:
  repairpricer:
    git:
      url: https://github.com/daslaller/RepairPricer-Client-SDK
      path: packages/repairpricer
      ref: v0.1.0
```

Pin a release tag rather than `main` — a branch ref floats, so an upstream
push would silently change what your build resolves to.

Then see [the SDK README](packages/repairpricer/README.md) for a usage
example.

## What is and is not here

**Here** — the client contract: models and request/response types, the
Appwrite-backed HTTP client, session authentication (never credentials), and
the read-time math that already executes inside a subscriber's app.

**Not here, deliberately** — anything that produces platform prices or
implements broker behaviour: supplier clients and crawlers, catalog slot
matching and part classification, service-fee derivation, AI price
verification, and every server-side Appwrite Function. Those stay in the
closed product repository.

## License

MIT — see [LICENSE](LICENSE).
