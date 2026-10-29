# What's Implemented / Not Yet Done

The detailed, per-feature implementation checklist and known-gaps list —
extracted from the README to keep that file short for a first-time visitor.
See the [main README](../README.md) for feature highlights and
[`architecture.md`](architecture.md) / [`technical-decisions.md`](technical-decisions.md)
for how and why.

## ✅ What's implemented

- Drift schema for `Transactions` (see the README's
  [Database schema](../README.md#-database-schema)), with a
  `.watch()`-backed `allTransactions` stream alongside
  `addTransaction`/`deleteTransaction`, backed by real SQLite via
  `sqlite3_flutter_libs`.
- `Result<T>` (`lib/core/result.dart`) — a sealed `Success<T>` / `Failure<T>`
  wrapper with a `when(success:, failure:)` method, used for write results
  (`addTransaction`, `deleteTransaction`) instead of letting exceptions
  propagate.
- A domain layer (`lib/features/transactions/domain/`) that decouples the
  bloc from Drift entirely:
  - `TransactionEntity` / `TransactionType` — plain Dart models with no
    Drift dependency.
  - `TransactionsRepository` — the abstract interface the domain and bloc
    layers depend on; has zero imports from `data/`.
  - Four use cases (`GetTransactionsUseCase`, `WatchBalanceUseCase`,
    `AddTransactionUseCase`, `DeleteTransactionUseCase`) — single-method
    (`call(...)`) wrappers around one repository call each.
  - `TransactionsRepositoryImpl` (in `data/repos/`) implements the
    interface and is the only place that maps Drift `Transaction` rows
    to/from `TransactionEntity`.
- `TransactionsBloc`, fully reactive and wired end-to-end to its use cases
  via `get_it` (never to the repository directly). Two long-lived stream
  subscriptions — transactions and, as of this release, categories — are
  started on `AppLaunchEvent` and cancelled together in `close()`; writes
  only emit on failure (`TransactionsError`).
- **Category management:** categories are now a fully editable
  resource, not a fixed set of four seeded rows.
  - `Categories` Drift table (`id`, `name`, nullable `colorHex`), schema
    v3, with `transactions.categoryId`'s FK changed to `ON DELETE SET
    NULL` via a `TableMigration` — deleting a category with transactions
    attached orphans them instead of throwing a constraint error.
  - `CategoryRepository`/`CategoryRepositoryImpl` grew a reactive
    `watchCategories()` (replacing the old one-shot `getCategories()`) plus
    `Result`-returning `addCategory`/`updateCategory`/`deleteCategory`,
    with trim/empty/case-insensitive-duplicate name validation done in the
    repository rather than a SQL constraint.
  - Four new use cases (`WatchCategoriesUseCase`, `AddCategoryUseCase`,
    `UpdateCategoryUseCase`, `DeleteCategoryUseCase`) and a new
    `CategoriesBloc` (mirroring `TransactionsBloc`'s shape: a `CategoriesLoaded`/
    `CategoriesError` state pair with `previousData` preserved across
    failures) that owns category mutation, kept separate from
    `TransactionsBloc`, which only reads categories.
  - A new `CategoriesScreen` (reached via an app-bar icon on the
    transactions screen), `CategoryEditorSheet` (add/edit, name field +
    a fixed 12-swatch color palette) and `DeleteCategoryDialog`
    (warns that orphaned transactions become "Uncategorized").
    `AddTransactionSheet`'s `ChoiceChip` picker is now sourced from
    `TransactionsBloc`'s live category stream, so a category created,
    renamed, or deleted on the new screen is reflected everywhere
    instantly — no restart required (see
    [Design decisions](technical-decisions.md) for the full set of
    trade-offs: `ON DELETE SET NULL` vs. blocking/cascading,
    `Future`-vs-`Stream`, in-repository validation vs. a SQL constraint,
    and the fixed palette vs. a color-picker package).
- Reactive total spending per category: `TransactionsDataSource.categoryTotals`
  joins `transactions` to `categories` via a `leftOuterJoin`, filters to
  expense transactions, and groups by `categoryId`, so uncategorized spend
  surfaces as its own bucket instead of being dropped. Wired end-to-end
  through `CategoryTotalEntity`, `CategoryRepository.watchCategoryTotals()`,
  `WatchCategoryTotalsUsecase`, and `CategoryTotalsCubit` (an aggregate-stream
  cubit shaped like `BalanceCubit`, not `TransactionsBloc` — see the
  README's [Reactive data flow](../README.md#-reactive-data-flow)),
  rendered by `CategoryTotalsCard`. The card is collapsible: tapping its
  header toggles an animated expand/collapse (local widget state, not
  persisted) to free vertical space for the transaction list below; the
  grand total stays visible in both states.
- Category visibility on transactions: `TransactionEntity` now carries
  `categoryId` through from the Drift row, and `TransactionTile` renders a
  small colored pill (dot + category name) next to the transaction title
  when one resolves — `TransactionsList` builds a `categoryId -> CategoryEntity`
  lookup map once per build so each row resolves its category in O(1) rather
  than scanning the category list per row. No pill renders for an
  uncategorized transaction.
- **Connectivity layer:** a core, cross-cutting network-status layer
  under `lib/core/connectivity/` — not part of the `transactions` feature,
  since online/offline state is infrastructure any future feature may need,
  not business logic.
  - `ConnectivityRepository`/`ConnectivityRepositoryImpl` wrap
    `connectivity_plus`, mapping its `List<ConnectivityResult>` down to a
    domain-owned `NetworkStatus` enum (`online`/`offline`) so no plugin type
    crosses into `domain/` — `checkConnectivity()` returns
    `Result<NetworkStatus>`, with `Failure` reserved for real plugin errors
    (not "you're offline", which is a normal `Success(NetworkStatus.offline)`).
  - `WatchConnectivityUseCase` is a thin `call()` wrapper around the
    repository's status stream, matching every other use case's shape.
  - `ConnectivityCubit` subscribes to that stream once and broadcasts
    `NetworkStatus` — registered as a `getIt.registerLazySingleton`, not
    `registerFactory` like the feature blocs/cubits, since it's meant to be
    one shared app-wide instance rather than a fresh one per screen.
  - Consumed by `OfflineBanner`
    (`lib/core/connectivity/presentation/widgets/offline_banner.dart`): a
    `BlocBuilder<ConnectivityCubit, NetworkStatus>` rendering a thin strip
    above the transaction list while offline, collapsed (`AnimatedSize`) when
    online. `ConnectivityCubit` is provided app-wide via `BlocProvider.value`
    in `main.dart` (`.value`, not `create`, since it's a singleton the
    provider must not close).
- **Offline sync queue / transactional outbox:** a core, cross-cutting
  layer under `lib/core/sync/` recording every write to `Transactions` and
  `Categories` so it can be pushed to Supabase later — see the README's
  [Offline sync queue](../README.md#offline-sync-queue-transactional-outbox)
  for the full design rationale (always-enqueue, atomic transaction + enqueue,
  snapshot payload).
  - `SyncQueueEntries` Drift table (`id`, `entityType`, `entityId`,
    `operation`, `payload`, `createdAt`), schema v4, added via a plain
    `createTable` migration step (no FK to migrate around).
  - `OperationType` enum (`create`/`update`/`delete`), `SyncQueueRepository`/
    `SyncQueueRepositoryImpl` with an `enqueue(entityType:, entityId:,
    operation:, payload:)` method — `id`/`createdAt` generated internally,
    never by the caller — and a `watchPendingCount()` stream backed by a
    `COUNT(*)` query.
  - `TransactionsRepositoryImpl.addTransaction`/`deleteTransaction` and
    `CategoryRepositoryImpl.addCategory`/`updateCategory`/`deleteCategory`
    all wrap their write and a `syncQueueRepository.enqueue(...)` call in
    one Drift `transaction()`, with a `Failure` result re-thrown inside the
    block to force a rollback (Drift only rolls back on a thrown exception,
    not a returned value) and re-caught just outside to restore the
    `Result<T>` contract callers expect.
  - `WatchPendingSyncCountUseCase` wraps `watchPendingCount()` the same way
    `WatchBalanceUseCase` wraps `watchBalance()`. It is registered in
    `service_locator.dart` and consumed by `PendingSyncCubit` (a
    `Cubit<int>` shaped like `BalanceCubit`), which `PendingSyncBadge`
    (`lib/core/sync/presentation/widgets/pending_sync_badge.dart`) renders as
    an always-visible app-bar action (the numeric badge itself only shows
    once something is queued). A row leaves the count once its push
    actually succeeds, so the tooltip says "N changes waiting to sync",
    never "failed" — a row still in the queue means "not yet confirmed,"
    not "broken." `PendingSyncCubit` is provided app-wide via
    `BlocProvider.value` in `main.dart`, same as `ConnectivityCubit`.
- **Push sync + manual "Sync now":** the drain side of the outbox —
  see the README's [Push sync to Supabase](../README.md#push-sync-to-supabase)
  for the full design writeup (idempotent per-row pushes, the local→remote
  field mapping, the auto-trigger rules, `SyncCubit`'s state, and the
  `allFailed`-inference trade-off).
  - `SupabaseSyncDataSource` (`pushEntry`, `mapForSupabase`),
    `SyncRepository`/`SyncRepositoryImpl` (`pushPending()`), and
    `PushPendingChangesUseCase`, all registered in `service_locator.dart`.
  - `SyncCubit` — now `Cubit<SyncState>` (`SyncIdle` / `SyncInProgress` /
    `SyncCompleted` / `SyncFailure`, each carrying an `isManual` flag) —
    auto-triggers a push-then-pull on reconnect and on a pending-count
    increase while online, and exposes `syncNow()` for a user-triggered
    sync with an in-flight guard against double-firing.
  - `SyncNowButton` (disabled with a tooltip reason while syncing, offline,
    or when the queue is empty) and `SyncSheet` (pending count, the
    button, and a manual-only result snackbar reporting both push and
    pull counts), opened by tapping `PendingSyncBadge`.
  - Anonymous Supabase auth (`signInAnonymously()` in `main()`) is what
    gives every write a non-null `auth.uid()` for RLS to check against —
    see the README's [Push sync to Supabase](../README.md#push-sync-to-supabase)
    for the durable-identity trade-off this implies.
  - **Not yet built:** remote-delete propagation (see
    [Pull sync](../README.md#pull-sync-downloading-changes-from-other-devices)),
    per-row error messages surfaced in the UI (only the fact that a push
    failed, not why), and syncing the four seeded default categories for a
    real (non-anonymous) account. See [Not yet done](#-not-yet-done) below.
- `AppBlocObserver` — logs every Bloc event, state change, and error via the
  `logger` package.
- Full presentation layer: transactions screen with balance summary,
  swipe-to-delete with animated undo, and an add-transaction bottom sheet
  with local submit-in-flight UI state.
- GitHub Actions CI (`.github/workflows/flutter-test.yml`) running format
  checks, static analysis, and the full test suite on every PR into `main`.
- Unit tests, all run against a real in-memory Drift database
  (`NativeDatabase.memory()`) rather than mocks:
  - `test/database_test.dart` — inserts, defaults, backdating, enum
    round-tripping, duplicate-id rejection, deletes, empty/multi-row reads,
    and that the `allTransactions` stream re-emits after a change; a
    `Categories` group covers the same shape for category CRUD plus the
    key regression test for this release — deleting a category referenced
    by a transaction sets `categoryId` to `null` instead of throwing
    (verifying `ON DELETE SET NULL` against a real SQLite constraint, not
    just application code).
  - `test/transactions_repository_test.dart` — `TransactionsRepositoryImpl`
    against a real Drift database: `addTransaction` note/type/amount
    handling and distinct-id generation, `getAllTransactions` stream
    behavior (including reactivity), and `addTransaction`/`deleteTransaction`
    `Success`/`Failure` results.
  - `test/category_repository_test.dart` — `CategoryRepositoryImpl`
    against a real Drift database: name trim/empty/case-insensitive-duplicate
    validation on add and update, that renaming a category to its own
    current name is not treated as a duplicate, `watchCategories()`
    reactivity, and that deleting a category with transactions attached
    orphans their spend into the `"Uncategorized"` bucket of
    `watchCategoryTotals()`.
  - `test/transactions_bloc_test.dart` — `TransactionsBloc` built from real
    use cases over a real Drift database: `AppLaunchEvent`,
    `AddTransactionEvent`, `DeleteTransactionEvent` state emissions under the
    stream-driven model, the double-subscription guard, and that writes emit
    nothing on success (only the subscription does). Because
    `AppLaunchEvent` now starts two independent stream subscriptions
    (transactions and categories) with no guaranteed ordering, its "empty
    table" test asserts on the settled state rather than a single expected
    emission.
  - `test/sync/sync_queue_repository_impl_test.dart` —
    `SyncQueueRepositoryImpl` against a real Drift database: `enqueue`
    generates `id`/`createdAt` internally, stores `entityType`/`entityId`/
    `payload` verbatim, round-trips `operation` as the `OperationType` enum,
    and `watchPendingCount()` emits `0` when empty, `N` after N enqueues, is
    reactive, and counts rows regardless of operation type.
  - `test/widget_test.dart` — boots the full widget tree against an
    in-memory database with proper teardown; registers stub use cases for
    `ConnectivityCubit` and `PendingSyncCubit`.
- Mocktail-backed bloc/cubit unit tests, mocking the use cases each bloc
  actually depends on (`test/helpers/mocks.dart`) rather than the
  repository, so each test isolates exactly at the bloc's real dependency
  boundary:
  - `test/transactions_bloc_mocktail_test.dart` — `TransactionsBloc` against
    mocked `GetTransactionsUseCase`/`AddTransactionUseCase`/
    `DeleteTransactionUseCase`/`WatchCategoriesUseCase`:
    - `AppLaunchEvent`: stream success → `Loaded`; stream error →
      `TransactionsError` (covers the `onError` handling added to the
      launch subscription).
    - `AddTransactionEvent` / `DeleteTransactionEvent`: success → no direct
      emission (call verified via `verify(...).called(1)`); failure →
      `TransactionsError`, asserted both with no prior state (empty
      `previousData`) and seeded from a prior `Loaded` state (`previousData`
      preserved) — failure branches a real repository can't be forced into,
      since ids are generated internally and duplicate-id collisions aren't
      reachable through the public event API.
  - `test/categories_bloc_mocktail_test.dart` — `CategoriesBloc`
    against mocked `WatchCategoriesUseCase`/`AddCategoryUseCase`/
    `UpdateCategoryUseCase`/`DeleteCategoryUseCase`, covering the same
    success/failure/`previousData`-preservation shape as
    `transactions_bloc_mocktail_test.dart` for `AddCategoryEvent`,
    `UpdateCategoryEvent`, and `DeleteCategoryEvent`.
  - `test/balance_cubit_mocktail_test.dart` — `BalanceCubit` against a mocked
    `WatchBalanceUseCase`: initial state is `0` before the stream emits, a
    single stream value is re-emitted as-is, and multiple stream values are
    emitted in order.
  - `test/connectivity/` — `ConnectivityRepositoryImpl` against a
    mocked `Connectivity`: the online/offline mapping rule (`[none]` →
    offline, `[]` → offline, `[wifi]` → online, `[none, mobile]` →
    **online**, all-`none` → offline), stream mapping, and the plugin-throws
    → `Failure` path; `ConnectivityCubit` (seed state `online`, ordered
    emissions, `close()` cancels the subscription); `WatchConnectivityUseCase`
    passthrough.
  - `test/sync/watch_pending_sync_count_usecase_test.dart` — passthrough
    to `SyncQueueRepository.watchPendingCount()`.
- **Connectivity & offline sync UI:** `OfflineBanner` and
  `PendingSyncBadge`/`PendingSyncCubit` wired into `main.dart` +
  `transactions_screen.dart` — see
  [Connectivity layer](#-whats-implemented) above, and
  [`CHANGELOG.md`](../CHANGELOG.md) / [`release-notes.md`](release-notes.md)
  for the release that landed them. Widget/cubit tests for these three
  still pending.
- **Export data:** a new `lib/features/backup/` feature — see the
  README's [Export data](../README.md#export-data-manual-backup) for the
  full design writeup (the `ExportableSource`/OCP seam, the isolate
  boundary, the envelope format).
  - `ExportableSource` (abstract) plus `TransactionsExportSource` and
    `CategoriesExportSource` (living beside each feature's own repository
    impl), each mapping its entities to plain `Map<String, Object?>` rows.
  - `TransactionsRepository`/`CategoryRepository` grew one-shot
    `getAllTransactionsOnce()`/`getAllCategoriesOnce()` methods (`Future`,
    not `Stream`) purely for this snapshot read — every other read on
    these repositories stays reactive.
  - `export_serializer.dart` (`buildEnvelope`/`encodeExport`), pure
    functions with no Flutter/Drift imports, run inside `Isolate.run` by
    `BackupRepositoryImpl.exportToJson()`, which also writes the resulting
    JSON to a temp file and returns `Result<ExportedFile>`.
  - `ExportDataUseCase` and `ExportCubit` (`Idle`/`InProgress`/
    `Success(file)`/`Failure(message)`) follow the same shapes as every
    other use case/cubit in this codebase; both are registered in
    `service_locator.dart` alongside the two named `ExportableSource`
    instances (`get_it` requires `instanceName` here since two concrete
    types are registered under one abstract type).
  - `ExportAction`, an app-bar `IconButton` next to "Manage categories" on
    `TransactionsScreen`, wraps its own `BlocProvider<ExportCubit>` so it's
    a self-contained drop-in. It shows a spinner while `ExportInProgress`
    and a result snackbar on `Success`/`Failure`.
  - **Not wired to actually trigger yet:** `ExportAction`'s button
    `onPressed` is currently a no-op — the call to
    `context.read<ExportCubit>().export()` is written but commented out —
    so every layer beneath it (cubit → use case → repository → sources →
    isolate → file write) is implemented and passes `flutter analyze`, but
    tapping the button in the running app does nothing yet. Re-enabling it
    is a one-line change once the remaining checklist items below are
    ready.
  - `test/backup/export_serializer_test.dart` covers `buildEnvelope` /
    `encodeExport` (metadata, UTC `exportedAt`, `counts`, JSON round-trip).
    `BackupRepositoryImpl` and `ExportCubit` still have no dedicated tests —
    `test/widget_test.dart` was updated only far enough to register the DI
    graph so the app still boots in tests.

## 🚧 Not yet done

- No editing of existing transactions — only add and delete.
- No filtering/search/date-range views over the transaction list.
- No protection against deleting all categories at once, beyond the add
  sheet and category list both handling an empty category set gracefully.
- The offline banner reflects network *interface* state, not reachability
  (that's all `connectivity_plus` reports) — no captive-portal/dead-Wi-Fi
  detection, and no action is gated on network state.
- Sync is two-way (push and pull), but remote deletes are not propagated —
  deleting a row on one device does not remove it on another, since
  pushed deletes are hard deletes with no tombstone for a pull to find.
  Two devices editing the same row concurrently resolve as last-write-wins
  (by `updated_at`), with no merge or conflict UI.
- No `status`/error column on `SyncQueueEntries` (a deliberate choice, see
  the README's [Push sync to Supabase](../README.md#push-sync-to-supabase))
  means the UI can say a push failed but not *why* — `SyncCompleted.allFailed`
  is inferred from a before/after count comparison, not read from an
  actual error.
- The four seeded default categories are never enqueued (they bypass
  `CategoryRepositoryImpl.addCategory()`), so they never reach Supabase for
  any user — deferred until real, non-anonymous auth exists.
- An end-to-end offline→sync flow is covered only by the integration test
  (`integration_test/offline_sync_test.dart`), which needs a device and so
  does not run in CI — see the README's
  [Integration test](../README.md#integration-test-run-by-hand).
- Anonymous auth means no durable identity across reinstalls/devices —
  every fresh install gets a new `auth.uid()` with no data carried over.
- **Export data's button doesn't trigger an export yet** — `ExportAction`'s
  `onPressed` is a deliberate no-op for now (see above); the cubit/use
  case/repository/serializer chain beneath it is complete and analyzer-clean
  but has no unit tests, hasn't been exercised on a real device, and has no
  import/restore counterpart, CSV option, scheduled backups, or encryption.
