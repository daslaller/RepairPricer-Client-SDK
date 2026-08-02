import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:repairpricer_contract/repairpricer_contract.dart';

import 'catalog_tree.dart';
import 'snapshot.dart';
import 'translations.dart';
import 'views.dart';

/// Subscriber-facing client over the RepairPricer Appwrite project, built on
/// the **client** SDK (`package:appwrite`).
///
/// Authenticate with a Team-member user **session** (never a project API
/// key), then read the shared master set. The database stores **all** offers;
/// pass a [WinnerStrategy] when you want a single slot winner. Writes are
/// never direct — the subscriber config tables have no client write
/// permission — so the `save*/…FilterRule/setTierNames` helpers route through
/// the `subscriber_config_admin` Function, which authorizes Team membership
/// server-side.
///
/// ```dart
/// final client = Client()
///   ..setEndpoint('https://appwrite.heid.se/v1')
///   ..setProject('6a57c373003e0ba11db4');
/// await Account(client).createEmailPasswordSession(email: ..., password: ...);
///
/// final rp = RepairPricerClient(client);
/// final config = await rp.loadClientConfig();
/// final winner = await rp.winnerForSlot('rp-6869', config?.strategy);
/// ```
class RepairPricerClient {
  RepairPricerClient(
    Client client, {
    this.databaseId = 'repair_pricer',
    this.configFunctionId = 'subscriber_config_admin',
    this.snapshotBucketId = 'snapshots',
    this.snapshotFileId = 'catalog_snapshot',
  })  : _db = TablesDB(client),
        _functions = Functions(client),
        _storage = Storage(client),
        _realtime = Realtime(client);

  final TablesDB _db;
  final Functions _functions;
  final Storage _storage;
  final Realtime _realtime;
  final String databaseId;

  /// The `subscriber_config_admin` Function the write helpers invoke.
  final String configFunctionId;

  /// Where the engine publishes the catalog snapshot (see
  /// `CatalogSnapshotWriter` in `repairpricer_engine`).
  final String snapshotBucketId;
  final String snapshotFileId;

  CatalogSnapshot? _snapshotCache;
  DateTime? _snapshotFetchedAt;
  String? _snapshotFileStamp; // the cached file's $updatedAt, for revalidation

  /// How long a downloaded snapshot is trusted before re-downloading. The
  /// file itself only changes when a sync runs, so this is just a bound on
  /// staleness for long-lived clients that don't use [watchCatalogSnapshot].
  static const _snapshotTtl = Duration(minutes: 15);

  // ── Config ────────────────────────────────────────────────────────────

  /// Loads this session's per-team configuration bundle (config row +
  /// filter rules + tier renames). Row security scopes every query to rows
  /// the session's team may read, so no team filter is needed for the
  /// config row itself; pass [teamId] only when the user belongs to several
  /// subscriber teams. Returns null when the team has no config row yet —
  /// callers then behave exactly as before this layer existed.
  Future<ClientConfigBundle?> loadClientConfig({String? teamId}) async {
    final configPage = await _db.listRows(
      databaseId: databaseId,
      tableId: 'subscriber_config',
      queries: [
        if (teamId != null && teamId.isNotEmpty) Query.equal('team_id', teamId),
        Query.limit(1),
      ],
    );
    if (configPage.rows.isEmpty) return null;
    final config = SubscriberConfig.fromRow(configPage.rows.first.data);
    // Independent reads — fetch concurrently so the config-load path pays one
    // round-trip's latency, not two.
    final [rules, tierNames] = await Future.wait([
      _listAllRows('subscriber_filter_rules', [Query.equal('team_id', config.teamId)]),
      _listAllRows('subscriber_tier_names', [Query.equal('team_id', config.teamId)]),
    ]);
    return ClientConfigBundle(
      config: config,
      filterRules: [for (final row in rules) FilterRule.fromRow(row)],
      tierNames: [for (final row in tierNames) TierNameOverride.fromRow(row)],
    );
  }

  // ── Catalog snapshot ──────────────────────────────────────────────────

  /// Downloads and parses the published catalog snapshot — the whole
  /// subscriber-visible catalog in ONE static fetch (~0.5s TTFB, line-rate
  /// transfer; measured 2026-07-31). Returns null when no snapshot exists
  /// yet, it can't be read, or it's newer than this SDK understands — treat
  /// null as "use live queries".
  ///
  /// The result is cached in this instance for 15 minutes; pass
  /// [refresh] to force a re-download (as [watchCatalogSnapshot] does when
  /// the bucket file changes).
  Future<CatalogSnapshot?> loadCatalogSnapshot({bool refresh = false}) async {
    final fetchedAt = _snapshotFetchedAt;
    if (!refresh &&
        _snapshotCache != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _snapshotTtl) {
      return _snapshotCache;
    }
    try {
      // REVALIDATE before re-downloading: the file's $updatedAt is a ~1 KB
      // metadata read, so an expired TTL (or a wake-up) only costs the full
      // blob when a NEW edition actually exists. This keeps
      // bootstrap-once-then-listen cheap even for clients that poll by TTL
      // instead of watching — the recurring bill is a metadata ping, not
      // the catalog.
      final meta = await _storage.getFile(
        bucketId: snapshotBucketId,
        fileId: snapshotFileId,
      );
      if (_snapshotCache != null && meta.$updatedAt == _snapshotFileStamp) {
        _snapshotFetchedAt = DateTime.now();
        return _snapshotCache;
      }
      final bytes = await _storage.getFileDownload(
        bucketId: snapshotBucketId,
        fileId: snapshotFileId,
      );
      _snapshotCache = CatalogSnapshot.fromBytes(bytes);
      _snapshotFetchedAt = DateTime.now();
      _snapshotFileStamp = meta.$updatedAt;
      return _snapshotCache;
    } catch (_) {
      // STALE BEATS BROKEN: a failed refresh degrades to the last-known
      // snapshot rather than pretending there is none (same rule as
      // RepairX's realtime streams, where surfacing a socket error once
      // signed out a whole shop). Null only when we never had one — that's
      // the "query live instead" signal. _snapshotFetchedAt is left old on
      // purpose so the next call retries the download.
      return _snapshotCache;
    }
  }

  /// The catalog as a SNAPSHOT STREAM, Firestore-style: emits the current
  /// snapshot immediately (when one exists), then a fresh one every time
  /// the engine re-publishes the bucket file (each `pricing_sync` run).
  /// Cancel the subscription to release the realtime channel.
  ///
  /// Realtime is a WAKE-UP SIGNAL only — the event payload is never
  /// trusted as data, and socket errors are swallowed: the stream degrades
  /// to the last emitted snapshot instead of erroring (stale beats broken).
  /// The next successful wake-up or TTL'd [loadCatalogSnapshot] call
  /// catches the client back up.
  Stream<CatalogSnapshot> watchCatalogSnapshot() {
    RealtimeSubscription? sub;
    late StreamController<CatalogSnapshot> controller;
    DateTime? lastEmitted;
    void emit(CatalogSnapshot? snap) {
      // Dedupe on generatedAt: a wake-up whose refresh failed hands back
      // the stale cache — re-emitting it would just churn listeners.
      if (snap == null || controller.isClosed) return;
      if (snap.generatedAt == lastEmitted) return;
      lastEmitted = snap.generatedAt;
      controller.add(snap);
    }

    controller = StreamController<CatalogSnapshot>(
      onListen: () async {
        emit(await loadCatalogSnapshot());
        sub = _realtime.subscribe(['buckets.$snapshotBucketId.files']);
        sub!.stream.listen((message) async {
          // Only the snapshot file's create matters (re-publish is
          // delete-then-create on a stable id).
          final isCreate = message.events.any((e) =>
              e.contains('.files.$snapshotFileId.') && e.endsWith('.create'));
          if (!isCreate) return;
          emit(await loadCatalogSnapshot(refresh: true));
        }, onError: (Object _) {
          // Swallowed by design — see the stale-beats-broken note above.
        });
      },
      onCancel: () {
        sub?.close();
        controller.close();
      },
    );
    return controller.stream;
  }

  /// The catalog as a LIVE snapshot stream with row-level ticks — correct
  /// under ANY write cadence (nightly batch, an audit AI writing all day,
  /// manual console edits), because freshness never depends on anyone
  /// remembering to republish:
  ///
  ///  1. **Bootstrap**: the published blob; if none exists, a full live scan.
  ///  2. **Catch-up**: an immediate watermark reconcile (`$updatedAt >`
  ///     the bootstrap's age) — rows written after the blob arrive before
  ///     the first emission settles.
  ///  3. **Ticks**: realtime row events on both projections, coalesced over
  ///     a short window and applied in memory ([applyCatalogChanges]).
  ///  4. **Healing**: a periodic watermark reconcile (usually two empty
  ///     queries) catches frames a dropped socket lost, and every blob
  ///     republish triggers an authoritative full reload (which also heals
  ///     deletes a watermark query can't see).
  ///
  /// Stale-beats-broken: errors are swallowed and the last state keeps
  /// serving. Cancel the subscription to release channels and timers.
  Stream<CatalogSnapshot> watchCatalog() {
    RealtimeSubscription? sub;
    Timer? flushTimer;
    Timer? reconcileTimer;
    late StreamController<CatalogSnapshot> controller;
    CatalogSnapshot? current;
    DateTime? watermark;
    final pendingUpserts = <String, List<Map<String, dynamic>>>{};
    final pendingDeletes = <String, List<Map<String, dynamic>>>{};
    var busy = false;

    void emit(CatalogSnapshot snap) {
      current = snap;
      if (!controller.isClosed) controller.add(snap);
    }

    Future<void> reconcile() async {
      final base = current;
      final since = watermark;
      if (base == null || since == null) return;
      try {
        // Small overlap so a clock-skewed write on the boundary isn't lost;
        // re-applying an already-known row is a no-op.
        final iso =
            since.subtract(const Duration(seconds: 5)).toIso8601String();
        final changed = await Future.wait([
          _scanRows('device_projection',
              [Query.greaterThan('\$updatedAt', iso)]),
          _scanRows('catalog_projection',
              [Query.greaterThan('\$updatedAt', iso)]),
        ]);
        watermark = DateTime.now().toUtc();
        if (changed[0].isEmpty && changed[1].isEmpty) return;
        emit(applyCatalogChanges(current!,
            upsertDevices: changed[0], upsertSlots: changed[1]));
      } catch (_) {
        // Swallowed — the next tick, reconcile, or edition reload heals.
      }
    }

    void flush() {
      final base = current;
      if (base == null) return;
      final up = Map.of(pendingUpserts)..removeWhere((_, v) => v.isEmpty);
      final del = Map.of(pendingDeletes)..removeWhere((_, v) => v.isEmpty);
      pendingUpserts.clear();
      pendingDeletes.clear();
      if (up.isEmpty && del.isEmpty) return;
      emit(applyCatalogChanges(
        base,
        upsertDevices: up['device_projection'] ?? const [],
        deleteDevices: del['device_projection'] ?? const [],
        upsertSlots: up['catalog_projection'] ?? const [],
        deleteSlots: del['catalog_projection'] ?? const [],
      ));
      watermark = DateTime.now().toUtc();
    }

    controller = StreamController<CatalogSnapshot>(
      onListen: () async {
        if (busy) return;
        busy = true;
        // 1. Bootstrap — blob preferred, full live scan when no blob exists
        // yet (a deployment that has never published still works).
        var snap = await loadCatalogSnapshot();
        if (snap == null) {
          try {
            final scanned = await Future.wait([
              _scanRows('device_projection', const []),
              _scanRows('catalog_projection', const []),
            ]);
            snap = applyCatalogChanges(
              CatalogSnapshot(
                  generatedAt: DateTime.now().toUtc(),
                  devices: const [],
                  slots: const []),
              upsertDevices: scanned[0],
              upsertSlots: scanned[1],
            );
          } catch (_) {
            snap = null;
          }
        }
        if (snap == null) return; // nothing readable at all — stream stays quiet
        watermark = snap.generatedAt;
        emit(snap);
        // 3. Row-event ticks + edition reloads.
        try {
          sub = _realtime.subscribe([
            'databases.$databaseId.tables.device_projection.rows',
            'databases.$databaseId.tables.catalog_projection.rows',
            'buckets.$snapshotBucketId.files',
          ]);
          sub!.stream.listen((message) async {
            final events = message.events;
            if (events.any((e) =>
                e.contains('.files.$snapshotFileId.') &&
                e.endsWith('.create'))) {
              final fresh = await loadCatalogSnapshot(refresh: true);
              if (fresh != null) {
                watermark = DateTime.now().toUtc();
                emit(fresh);
              }
              return;
            }
            final payload = message.payload;
            for (final table in const [
              'device_projection',
              'catalog_projection'
            ]) {
              if (!events.any((e) => e.contains('.tables.$table.'))) continue;
              final bucket = events.any((e) => e.endsWith('.delete'))
                  ? pendingDeletes
                  : pendingUpserts;
              (bucket[table] ??= []).add(Map<String, dynamic>.from(payload));
            }
            // Coalesce bursts: apply at most ~4×/second.
            flushTimer ??= Timer(const Duration(milliseconds: 250), () {
              flushTimer = null;
              flush();
            });
          }, onError: (Object _) {
            // Swallowed — the periodic reconcile below is the safety net.
          });
        } catch (_) {
          // No realtime: reconcile alone keeps the stream honest.
        }
        // 2. Catch-up past the bootstrap, then 4. the healing loop.
        await reconcile();
        reconcileTimer =
            Timer.periodic(const Duration(minutes: 5), (_) => reconcile());
      },
      onCancel: () {
        flushTimer?.cancel();
        reconcileTimer?.cancel();
        sub?.close();
        controller.close();
      },
    );
    return controller.stream;
  }

  // ── Catalog ───────────────────────────────────────────────────────────

  /// Browse / search the shared catalog (one row per slot).
  ///
  /// With a [config], the subscriber's exclusions are pushed down as
  /// server-side `notEqual` queries (AND semantics — pages stay full) and
  /// each returned view carries [CatalogSlotView.displayTierName] /
  /// [CatalogSlotView.displayPriceMinor] per [CatalogSlotView.applyClientConfig].
  Future<List<CatalogSlotView>> listCatalog({
    String? search,
    int limit = 50,
    String? cursorAfter,
    ClientConfigBundle? config,
    String locale = 'sv',
  }) async {
    final queries = <String>[Query.limit(limit)];
    if (search != null && search.isNotEmpty) {
      queries.add(Query.search('model_name', search));
    }
    if (cursorAfter != null && cursorAfter.isNotEmpty) {
      queries.add(Query.cursorAfter(cursorAfter));
    }
    if (config != null) {
      for (final kind in const [FilterKind.manufacturer, FilterKind.deviceType, FilterKind.device]) {
        for (final value in config.excludedValues(kind)) {
          queries.add(Query.notEqual(kind.projectionColumn, value));
        }
      }
    }
    final page = await _db.listRows(
      databaseId: databaseId,
      tableId: 'catalog_projection',
      queries: queries,
    );
    return [
      for (final row in page.rows)
        config == null
            ? CatalogSlotView.fromRow(row.data)
            : CatalogSlotView.fromRow(row.data).applyClientConfig(config, locale: locale),
    ];
  }

  /// The catalog as a TREE, one depth window at a time — built for lazy tree
  /// UIs that want "manufacturers first, collapsed" instead of paying for
  /// every slot up front.
  ///
  /// Every slot's `category_path` is five levels:
  /// `device_type > manufacturer > model > Reparation > repair` (see
  /// [CatalogLevel]). [filter] is the ` > `-separated prefix already known
  /// (empty for all), [depth] the first level to return (1-based), and
  /// [maxDepth] the last (`0` = down to the leaf). So:
  ///
  /// ```dart
  /// // Top of the tree: just manufacturers, one cheap read.
  /// await rp.getCatalogs('', CatalogLevel.manufacturer, CatalogLevel.manufacturer);
  /// // Everything under one model, skipping the two levels already shown:
  /// //   Galaxy Z Fold4 > Reparation > Speaker, …
  /// await rp.getCatalogs('Mobil > Samsung', 3, 0);
  /// ```
  ///
  /// Answers from the published catalog SNAPSHOT when one exists (one
  /// static fetch for the whole catalog, then pure in-memory windowing —
  /// see [loadCatalogSnapshot]), falling back to live queries otherwise:
  /// windows entirely above the repair levels come from `device_projection`
  /// (one row per device, ~1.8k) while anything touching level 4+ needs
  /// `catalog_projection` (one row per slot). On the live path the first
  /// three filter segments are pushed down as indexed-column equality
  /// queries and only the path columns cross the wire.
  Future<List<CatalogNode>> getCatalogs([
    String filter = '',
    int depth = 1,
    int maxDepth = 0,
  ]) async {
    if (depth < 1) {
      throw ArgumentError.value(depth, 'depth', 'must be >= 1');
    }
    if (maxDepth != 0 && maxDepth < depth) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'must be 0 or >= depth');
    }
    final filterSegments = splitCategoryPath(filter);
    final snapshot = await loadCatalogSnapshot();
    if (snapshot != null) {
      return catalogNodesFromSnapshot(
        snapshot,
        filter: filterSegments,
        depth: depth,
        maxDepth: maxDepth,
      );
    }
    // device_projection can only answer windows that stay above level 4 and
    // filters that don't reach into the repair levels.
    final deviceLevelsSuffice = maxDepth != 0 &&
        maxDepth <= CatalogLevel.model &&
        filterSegments.length <= CatalogLevel.model;
    final pushdown = <String>[
      for (final (i, column) in const [
        'device_type_name',
        'manufacturer_name',
        'model_name',
      ].indexed)
        if (filterSegments.length > i)
          Query.equal(column, filterSegments[i]),
    ];
    final Iterable<List<String>> paths;
    if (deviceLevelsSuffice) {
      final rows = await _scanRows('device_projection', [
        ...pushdown,
        Query.select(
            const ['device_type_name', 'manufacturer_name', 'model_name']),
      ]);
      paths = rows.map((r) => [
            for (final c in const [
              'device_type_name',
              'manufacturer_name',
              'model_name',
            ])
              if ('${r[c] ?? ''}'.isNotEmpty) '${r[c]}',
          ]);
    } else {
      final rows = await _scanRows('catalog_projection', [
        ...pushdown,
        Query.select(const ['category_path']),
      ]);
      paths = rows.map((r) => splitCategoryPath('${r['category_path'] ?? ''}'));
    }
    return aggregateCatalogPaths(
      paths,
      depth: depth,
      maxDepth: maxDepth,
      filter: filterSegments,
    );
  }

  Future<CatalogSlotView?> getCatalogSlot(String code) async {
    final page = await _db.listRows(
      databaseId: databaseId,
      tableId: 'catalog_projection',
      queries: [Query.equal('code', code), Query.limit(1)],
    );
    if (page.rows.isEmpty) return null;
    return CatalogSlotView.fromRow(page.rows.first.data);
  }

  /// Every supplier offer for a slot — winners and losers alike. With a
  /// [config], the subscriber's supplier exclusions are pushed down.
  Future<List<OfferView>> listOffersForSlot(
    String code, {
    int limit = 100,
    ClientConfigBundle? config,
  }) async {
    final page = await _db.listRows(
      databaseId: databaseId,
      tableId: 'offer_projection',
      queries: [
        Query.equal('code', code),
        Query.limit(limit),
        if (config != null)
          for (final value in config.excludedValues(FilterKind.supplier))
            Query.notEqual('supplier_name', value),
      ],
    );
    return [for (final row in page.rows) OfferView.fromRow(row.data)];
  }

  /// Pick the slot winner by [strategy] from the full offer set.
  ///
  /// Compares [OfferView.costPriceMinor] (converted cost), preferring
  /// in-stock offers — same rules as the platform [selectWinner] helper.
  /// [strategy] defaults to the [config]'s strategy (or `cheapest` when
  /// neither is given); the [config]'s supplier exclusions shrink the
  /// candidate pool before selection.
  Future<OfferView?> winnerForSlot(
    String code, [
    WinnerStrategy? strategy,
    ClientConfigBundle? config,
  ]) async {
    final offers = await listOffersForSlot(code, config: config);
    if (offers.isEmpty) return null;
    final byId = {for (final o in offers) o.offerId: o};
    final winner = selectWinner(
      [
        for (final o in offers)
          WinnerCandidate(offerId: o.offerId, stockPriceMinor: o.costPriceMinor, inStock: o.inStock),
      ],
      strategy ?? config?.strategy ?? WinnerStrategy.cheapest,
    );
    return winner == null ? null : byId[winner.offerId];
  }

  /// The price this subscriber should DISPLAY for a slot, per their config:
  /// in `platform` mode the precomputed [CatalogSlotView.winningPriceMinor];
  /// in `custom` mode their own margin pipeline over the config-strategy
  /// winner's cost. Null when the slot is unknown or has no offers.
  Future<int?> displayPriceForSlot(String code, ClientConfigBundle config) async {
    if (config.config.pricingMode == PricingMode.platform) {
      return (await getCatalogSlot(code))?.winningPriceMinor;
    }
    final winner = await winnerForSlot(code, null, config);
    if (winner == null) return null;
    return computeOfferPricing(
      rawPriceMinor: winner.costPriceMinor,
      config: config.config.toPricingConfig(),
      rateToShop: 1.0,
    ).finalPriceMinor;
  }

  /// Lists devices the owner carries from `device_projection` — the "which
  /// models" surface, independent of pricing. Optionally narrowed by
  /// [manufacturerName] / [deviceTypeName]; reads every matching row
  /// (cursor-paged). Powers filter pickers and the tier-name editor.
  Future<List<RepairPricerDevice>> listDevices({
    String? manufacturerName,
    String? deviceTypeName,
  }) async {
    final rows = await _listAllRows('device_projection', [
      if (manufacturerName != null && manufacturerName.isNotEmpty)
        Query.equal('manufacturer_name', manufacturerName),
      if (deviceTypeName != null && deviceTypeName.isNotEmpty)
        Query.equal('device_type_name', deviceTypeName),
    ]);
    return [for (final row in rows) RepairPricerDevice.fromRow(row)];
  }

  // ── Translations ──────────────────────────────────────────────────────

  /// Fetches the whole vocabulary dictionary once (it's small — dozens of
  /// terms × a curated set of locales). Cache the returned object and call
  /// [TranslationDictionary.label] per render.
  Future<TranslationDictionary> loadTranslations() async {
    return TranslationDictionary.fromRows(await _listAllRows('translations', const []));
  }

  // ── Writes (via the subscriber_config_admin Function) ─────────────────

  /// Applies the whitelisted pricing fields to the team's config row.
  Future<void> saveConfig(Map<String, dynamic> fields) =>
      _callConfigFunction({'action': 'save_config', 'fields': fields});

  /// Applies the whitelisted widget display fields to the team's config row.
  Future<void> saveWidgetSettings(Map<String, dynamic> fields) =>
      _callConfigFunction({'action': 'save_widget_settings', 'fields': fields});

  /// Rotates the public widget key (revokes the old one). Returns the new key.
  Future<String?> regenerateWidgetKey() async {
    final result = await _callConfigFunction({'action': 'regenerate_widget_key'});
    return result['widgetKey'] as String?;
  }

  /// Adds one catalog exclusion. The Function validates [value] against the
  /// live catalog, so an unknown value throws rather than silently no-op'ing.
  Future<void> addFilterRule(FilterKind kind, String value) =>
      _callConfigFunction({'action': 'add_filter_rule', 'kind': kind.key, 'value': value});

  Future<void> removeFilterRule(FilterKind kind, String value) =>
      _callConfigFunction({'action': 'remove_filter_rule', 'kind': kind.key, 'value': value});

  /// Upserts one tier's per-team display names. Passing null/empty for both
  /// locales clears the override (falls back to the global tier name).
  Future<void> setTierNames({required String tierKey, String? en, String? sv}) =>
      _callConfigFunction({'action': 'set_tier_names', 'tierKey': tierKey, 'en': en, 'sv': sv});

  Future<Map<String, dynamic>> _callConfigFunction(Map<String, dynamic> body) async {
    final execution = await _functions.createExecution(
      functionId: configFunctionId,
      body: jsonEncode(body),
      method: ExecutionMethod.pOST,
    );
    final raw = execution.responseBody;
    final decoded = raw.isEmpty ? const <String, dynamic>{} : jsonDecode(raw);
    final result = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (result['ok'] != true) {
      throw StateError(result['error'] as String? ?? 'config action failed (${execution.status})');
    }
    return result;
  }

  // ── Paging ────────────────────────────────────────────────────────────

  /// Reads every row matching [queries] in as few round-trips as possible:
  /// one 5000-row page covers today's entire catalog (measured 2026-07-30:
  /// the full 4.5k-slot catalog_projection returns in ~0.7-1.1s in ONE
  /// request, while the same rows at 50/page cost 91 sequential round-trips
  /// — ~15s over a real network). Should a table outgrow a page, the
  /// remaining pages are fetched IN PARALLEL by offset (the first page
  /// reports `total`), with a cursor tail in case `total` was capped.
  /// The self-host allows limit(5000) — the portal's loadFacets already
  /// relies on it.
  Future<List<Map<String, dynamic>>> _scanRows(
    String tableId,
    List<String> queries, {
    int pageSize = 5000,
  }) async {
    final first = await _db.listRows(
      databaseId: databaseId,
      tableId: tableId,
      queries: [...queries, Query.limit(pageSize)],
    );
    final rows = [...first.rows];
    final remaining = ((first.total - rows.length) / pageSize).ceil();
    if (rows.length >= pageSize && remaining > 0) {
      final pages = await Future.wait([
        for (var i = 1; i <= remaining; i++)
          _db.listRows(
            databaseId: databaseId,
            tableId: tableId,
            queries: [
              ...queries,
              Query.limit(pageSize),
              Query.offset(i * pageSize),
            ],
          ),
      ]);
      for (final page in pages) {
        rows.addAll(page.rows);
      }
      // `total` can be capped server-side; if the last page came back full,
      // keep cursor-paging until the true end.
      if (pages.isNotEmpty && pages.last.rows.length == pageSize) {
        while (true) {
          final page = await _db.listRows(
            databaseId: databaseId,
            tableId: tableId,
            queries: [
              ...queries,
              Query.limit(pageSize),
              Query.cursorAfter(rows.last.$id),
            ],
          );
          rows.addAll(page.rows);
          if (page.rows.length < pageSize) break;
        }
      }
    }
    return [for (final r in rows) r.data];
  }

  /// Cursor-pages through every readable row of [tableId] (session reads
  /// are already scoped by row security).
  Future<List<Map<String, dynamic>>> _listAllRows(String tableId, List<String> baseQueries) async {
    const pageSize = 500;
    final rows = <Map<String, dynamic>>[];
    var lastId = '';
    while (true) {
      final queries = <String>[...baseQueries, Query.limit(pageSize)];
      if (lastId.isNotEmpty) queries.add(Query.cursorAfter(lastId));
      final page = await _db.listRows(databaseId: databaseId, tableId: tableId, queries: queries);
      if (page.rows.isEmpty) break;
      rows.addAll(page.rows.map((r) => r.data));
      lastId = page.rows.last.$id;
      if (page.rows.length < pageSize) break;
    }
    return rows;
  }
}
