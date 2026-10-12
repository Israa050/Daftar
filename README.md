# Money Log

<p align="center">
  <img src="assets/screenshots/money-log-hero-wide.png" alt="Money Log app overview" width="700" />
</p>

<details>
<summary>More screenshots</summary>

<p align="center">
  <img src="assets/screenshots/transactions.jpg" alt="Transactions list with balance summary" width="230" />
  &nbsp;&nbsp;
  <img src="assets/screenshots/add_transaction.jpg" alt="Add transaction bottom sheet" width="230" />
  &nbsp;&nbsp;
  <img src="assets/screenshots/add_transactions_categories_chips.jpg" alt="Add transaction sheet with category chips" width="230" />
  &nbsp;&nbsp;
  <img src="assets/screenshots/empty.jpg" alt="Empty state" width="230" />
</p>

<p align="center">
  <em>Balance summary &amp; transaction list &nbsp;·&nbsp; Add-transaction sheet &nbsp;·&nbsp; Category picker &nbsp;·&nbsp; Empty state</em>
</p>

</details>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.11-0175C2?logo=dart&logoColor=white" />
  <img alt="State management" src="https://img.shields.io/badge/state-flutter__bloc-6C4EE3" />
  <img alt="Database" src="https://img.shields.io/badge/db-Drift%20(SQLite)-4A6FD4" />
  <img alt="CI" src="https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" />
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green" /></a>
</p>

<p align="center">
  <a href="https://github.com/Israa050/money-log/releases/latest">
    <img alt="Download APK" src="https://img.shields.io/github/v/release/Israa050/money-log?label=Download%20APK&logo=android&logoColor=white&color=3DDC84" />
  </a>
</p>

<p align="center">
  <a href="https://claude.ai/code/artifact/7ef70167-84d3-4ec5-b1da-6acea789d354">📊 The Reactive Loop — interactive diagram</a>
  &nbsp;·&nbsp;
  <a href="https://claude.ai/code/artifact/97b41c14-86fe-47d7-bbc0-a13aed14b7d2">🖱️ Live transactions demo</a>
</p>

---

## 📖 About

Money Log is a small, focused personal-finance tracker: log income and
expenses, see your balance update instantly, and undo a delete before it's
final. It exists as a reference implementation of a **fully reactive**
Flutter architecture — every screen is driven by a live database stream, not
a fetch-then-render cycle, so the UI is never more than one SQLite write away
from the truth.

The app is built with the **BLoC** pattern on top of
**[Drift](https://drift.simonbinder.eu/)** (a type-safe SQLite layer): a
write lands in the database, Drift's `.watch()` query notices the table
changed, and the new data arrives back at the screen on its own — no manual
refresh, no re-fetch after a mutation, no stale state to reconcile. The UI
itself uses a warm, editorial dark-first design system with distinct
income/expense color language, card-based transaction rows, and swipe-to-
delete with a countdown undo.

## ✨ Features

- 📊 **Balance summary** — live total balance with income/expense breakdown
- 📈 **Spending by category** — a collapsible card showing total expenses grouped by category (plus an "Uncategorized" bucket), each row live-updated the instant a matching transaction is added or deleted
- 📋 **Transaction list** — card-styled rows with type icon, note, date, amount, and a color-coded category tag when one is set
- ➕ **Add transactions** — bottom sheet with an income/expense toggle, amount, optional note, and optional category
- 🏷️ **Categories** — pick from four seeded default categories (Food, Transport, Shopping, Bills) when adding a transaction, shown as color-coded chips; the same colors carry through to the transaction list and the category totals card
- 🗂️ **Manage categories** — a dedicated screen (opened from the transactions app bar) to create, rename/recolor, and delete categories from a fixed swatch palette; deleting a category that still has transactions orphans them into "Uncategorized" instead of failing, and every change propagates live to the add-transaction chips and transaction pills
- 👉 **Swipe to delete** — swipe a row away, then **Undo** within a 5-second countdown before it's permanently deleted
- 📡 **Offline banner** — a strip above the transaction list appears while the device has no network interface; the copy is informational ("changes are saved on this device"), since every write is persisted and queued locally regardless of connectivity
- 🔼 **Pending-changes badge** — an always-visible app-bar action showing how many local writes are waiting to sync (the count badge itself only appears once something is queued); tapping it opens the sync sheet
- ☁️ **Push sync to Supabase** — queued local writes are pushed to a Supabase backend (anonymous auth, RLS scoped to `auth.uid()`) whenever connectivity comes back online or a new change is queued while already online; each row pushes independently and failed rows simply stay queued for the next retry — no status/retry-count bookkeeping needed, since upsert/delete are idempotent
- 🔁 **Manual "Sync now"** — the sync sheet (opened from the pending-changes badge) shows the queued-change count and a button to trigger a push-then-pull on demand, disabled with a reason (syncing / offline / nothing queued) instead of just doing nothing; a result snackbar ("Synced N changes out, M in" / "Couldn't send your changes" / "Already up to date") appears only for this manual path, never for the silent auto-trigger
- 🔃 **Pull sync from other devices** — after every push, the app also pulls changes made elsewhere on the same account and applies them locally with last-write-wins (by `updated_at`), so edits on one device eventually show up on another; each table tracks its own sync watermark independently (remote deletes are a known, documented gap — not yet propagated)
- 🔄 **Fully reactive** — every screen is driven by a live Drift stream; add/delete never trigger a manual reload
- 💾 **Local persistence** — everything is stored in an on-device SQLite database via Drift
- 📤 **Export data** — an app-bar action serializes every transaction and category to a single JSON file (off the main isolate) and opens the OS share sheet, doubling as a manual backup for this offline-first app
- 🪵 **Bloc observability** — every event and state transition is logged through a custom `BlocObserver`
- 🎨 **Themed design system** — light/dark color tokens (`AppColors`), a distinct income/expense
  palette, and a small, composable widget set instead of one large screen file

## 🧱 Tech stack

| Layer          | Choice                                                        |
| -------------- | --------------------------------------------------------------|
| State mgmt     | [flutter_bloc](https://pub.dev/packages/flutter_bloc)         |
| Persistence    | [drift](https://pub.dev/packages/drift) (SQLite)               |
| DI             | [get_it](https://pub.dev/packages/get_it)                     |
| Connectivity   | [connectivity_plus](https://pub.dev/packages/connectivity_plus) |
| Backend        | [supabase_flutter](https://pub.dev/packages/supabase_flutter) (Postgres + auth + RLS) |
| Sharing        | [share_plus](https://pub.dev/packages/share_plus) (export file → OS share sheet) |
| IDs            | [uuid](https://pub.dev/packages/uuid) (client-generated v4)   |
| Logging        | [logger](https://pub.dev/packages/logger)                     |
| Testing        | [bloc_test](https://pub.dev/packages/bloc_test) + [mocktail](https://pub.dev/packages/mocktail) |
| CI             | [GitHub Actions](.github/workflows/flutter-test.yml)          |
| CD             | [GitHub Actions](.github/workflows/deploy-production.yml) + [Firebase App Distribution](https://firebase.google.com/docs/app-distribution) |

## 🚀 Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
cp env.example.json env.json   # fill in your own Supabase URL + anon key
flutter run --dart-define-from-file=env.json
```

> `env.json` is gitignored — it holds real Supabase credentials and is never
> committed. The app throws a clear `StateError` at startup if it's missing.
> A VS Code launch config that passes the flag automatically is provided in
> [`.vscode/launch.json`](.vscode/launch.json) (pick "stockflow (env)").

> The `build_runner` step regenerates Drift's `*.g.dart` files. Re-run it
> whenever a table definition under `lib/features/transactions/data/models/`,
> `lib/features/categories/data/models/`, or `lib/core/sync/data/models/`
> changes.

### Running tests

```bash
flutter test
```

Two complementary approaches are used:

- **Drift-backed tests** (`database_test.dart`, `transactions_repository_test.dart`,
  `category_repository_test.dart`, `transactions_bloc_test.dart`,
  `sync/sync_queue_repository_impl_test.dart`, `widget_test.dart`)
  drive a real in-memory Drift database (`NativeDatabase.memory()`) instead of
  mocks, so no state leaks between tests and nothing touches disk.
- **Mocktail-backed bloc/cubit/use-case tests** (`transactions_bloc_mocktail_test.dart`,
  `categories_bloc_mocktail_test.dart`, `balance_cubit_mocktail_test.dart`,
  `connectivity/`, `sync/watch_pending_sync_count_usecase_test.dart`,
  `sync/sync_repository_impl_test.dart`, `sync/sync_data_usecase_test.dart`,
  `sync/sync_cubit_test.dart`)
  use [`bloc_test`](https://pub.dev/packages/bloc_test) and
  [`mocktail`](https://pub.dev/packages/mocktail) with mocked use cases
  ([`test/helpers/mocks.dart`](test/helpers/mocks.dart)) to assert state
  emissions in isolation, including failure paths a real repository can't be
  forced into (see below). `sync/sync_repository_impl_test.dart` covers
  `pushPending()`'s independent-row processing: one failing entry doesn't
  block the rest of that pass. `sync/sync_data_usecase_test.dart` covers the
  push-then-pull sequencing (a push failure skips pull, a pull failure is
  returned, pull still runs when nothing was pushed), and
  `sync/sync_cubit_test.dart` covers `SyncCubit`'s states, the in-flight
  guard, and the `allFailed` inference against a mocked `SyncDataUseCase`.
  `sync/sync_repository_pull_test.dart` (real in-memory Drift) covers one
  `pullRemoteChanges()` regression, pull order against the foreign key;
  last-write-wins and conflict tests are still a known gap, not an
  oversight (see [Not yet done](docs/implemented.md#-not-yet-done)).
- **`sync/supabase_sync_data_source_test.dart`** tests the local→remote
  payload mapping (`camelCase` → `snake_case`, `user_id` stamping) directly,
  rather than mocking `pushEntry()`'s Supabase SDK calls end-to-end — the
  SDK's `client.from(...).upsert(...)` chain gets its awaitability from an
  overridden generic `then` method that `mocktail` can't reliably intercept.
- **Pure-function tests** (`format_test.dart`,
  `backup/export_serializer_test.dart`) need neither a database nor mocks.

### Continuous integration

Every pull request into `main` runs
[`.github/workflows/flutter-test.yml`](.github/workflows/flutter-test.yml):
dependency install → Drift code generation → `dart format` check →
`flutter analyze` → `flutter test`. A PR can't merge with a formatting
issue, an analyzer warning, or a failing test.

### Continuous deployment

Pushing to the `production` branch runs
[`.github/workflows/deploy-production.yml`](.github/workflows/deploy-production.yml):
it builds a signed, arm64-only release APK and uploads it to Firebase App
Distribution's `internal` tester group. `production` is a deploy-only
branch, separate from `main`. Full setup steps, the release-signing
approach, and troubleshooting notes are in
[`docs/firebase-app-distribution.md`](docs/firebase-app-distribution.md).

## 🗂️ Project structure

The app is organized feature-first under `lib/features/` (`transactions/`,
`categories/`, `backup/`), with genuinely cross-cutting concerns
(connectivity, the offline sync queue, theming) kept in `lib/core/` instead
of inside any one feature. Each feature follows the same
`bloc/domain/data/presentation` layering, with dependencies pointing inward
toward `domain/` — blocs depend only on use cases, use cases depend only on
an abstract repository interface, and only the `*Impl` classes in `data/`
know about Drift.

**→ [Full directory tree + layering rules](docs/architecture.md)**

## 🔄 Reactive data flow

There is no "refresh" step anywhere in this app. A write lands in SQLite,
Drift's `.watch()` query notices the table changed, and the new list arrives
back at the screen on its own.

**→ [Open the interactive loop diagram](https://claude.ai/code/artifact/7ef70167-84d3-4ec5-b1da-6acea789d354)**
for a visual walkthrough of the cycle described below.

```mermaid
flowchart LR
    UI["UI (BlocBuilder)"] -- "add(AppLaunchEvent)" --> Bloc[TransactionsBloc]
    Bloc -- "getTransactionsUseCase()\n(once, held in _subscription)" --> UC[GetTransactionsUseCase]
    UC --> Repo["TransactionsRepository\n(impl)"]
    Repo -- "select(transactions).watch()" --> DS[TransactionsDataSource]
    DS -- "SQL" --> DB[(SQLite via drift)]
    DB -- "table changed → re-run query" --> DS
    DS -- "Drift row" --> Repo
    Repo -- "TransactionEntity stream" --> UC
    UC -- "stream tick" --> Bloc
    Bloc -- "add(_TransactionsUpdated)\n→ emit(Loaded(data))" --> UI

    Sheet["AddTransactionSheet"] -- "add(AddTransactionEvent /\nDeleteTransactionEvent)" --> Bloc
    Bloc -- "addTransactionUseCase / deleteTransactionUseCase" --> Repo
    Bloc -. "emit(TransactionsError)\non failure only" .-> Sheet

    CatUI["CategoryTotalsCard\n(BlocBuilder)"] -- "subscribes once,\nin constructor" --> CatCubit[CategoryTotalsCubit]
    CatCubit --> CatUC[WatchCategoryTotalsUsecase]
    CatUC --> CatRepo["CategoryRepository\n(impl)"]
    CatRepo -- "leftOuterJoin + groupBy,\nwhere type == expense" --> DS
    DS -- "CategoryTotalRow list" --> CatRepo
    CatRepo -- "CategoryTotalEntity stream" --> CatUC
    CatUC -- "stream tick" --> CatCubit
    CatCubit -- "emit(totals)\ndirectly, no bridging event" --> CatUI
```

Each piece's job:

- **`TransactionsDataSource.allTransactions`** is a `Stream<List<Transaction>>`
  built from `select(transactions).watch()` — not a one-shot `Future`. Drift
  re-runs the query and re-emits automatically whenever a row in the
  `transactions` table changes.
- **`TransactionsRepositoryImpl.getAllTransactions()`** maps each Drift
  `Transaction` row to a `TransactionEntity` and passes the stream straight
  through — no `async`, no `Result<T>`. Writes (`addTransaction` /
  `deleteTransaction`) stay plain `Future<Result<T>>` and never return the
  updated list; the stream re-emitting is what updates the UI, not the
  write's return value.
- **`GetTransactionsUseCase` / `AddTransactionUseCase` / `DeleteTransactionUseCase`
  / `WatchBalanceUseCase`** are thin, single-method (`call(...)`) wrappers
  around one repository call each. `TransactionsBloc`/`BalanceCubit` depend
  only on these — never on `TransactionsRepository` directly — so the bloc
  layer never sees a Drift type.
- **`TransactionsBloc`** subscribes to `getTransactionsUseCase()` exactly
  once, in `_onLaunch` (guarded against double-subscribing), and stores the
  `StreamSubscription` in `_subscription`. Every tick is bridged through a
  private `_TransactionsUpdated` event (a Bloc handler can't `emit()` from
  inside a raw stream callback), which emits `Loaded(data)`.
  `AddTransactionEvent`/`DeleteTransactionEvent` handlers call the
  corresponding use case and **emit nothing on success** — the already-live
  subscription picks up the change on its own. They only emit
  `TransactionsError` if the write itself fails.
- **`_subscription.cancel()` in `close()`** is the one step with no automatic
  safety net (highlighted in the diagram). Skipping it leaks the Drift query
  listener past the Bloc's lifetime — since `TransactionsBloc` is a
  `getIt.registerFactory` instance created fresh per screen, forgetting this
  leaves one more orphaned subscription running after every navigation.
- **`AddTransactionSheet`** dispatches `AddTransactionEvent` and disables its
  submit button locally (`_isSubmitting`) while waiting — not via a Bloc
  `Loading` state, since none exists on the write path. A `BlocListener`
  (guarded by `listenWhen: (_, __) => _isSubmitting`) pops the sheet on the
  next `Loaded` and shows an inline error on `TransactionsError`, so failures
  surface before the sheet is dismissed instead of as a disconnected
  snackbar afterward.
- **`CategoryTotalsCubit`** follows the same aggregate-stream shape as
  `BalanceCubit`, not `TransactionsBloc`: it subscribes to
  `WatchCategoryTotalsUsecase()` once in its constructor and calls `emit`
  directly from the stream listener. A `Cubit` can do this safely — only a
  `Bloc` needs the private-event bridging trick `TransactionsBloc` uses,
  because a `Bloc`'s `emit` is only valid inside an event handler, while a
  `Cubit` has no such restriction.

### Swipe-to-delete + Undo

Deleting is optimistic on the UI side but not on the database side:

1. Swiping a row adds its id to a local `_pendingDeleteIds` set and hides it
   immediately — this keeps the rendered list in sync with what `Dismissible`
   already removed from the widget tree, avoiding a
   "dismissed Dismissible still in tree" crash.
2. A snackbar appears with an animated 5-second countdown bar and an **Undo**
   action.
3. If **Undo** is tapped, the id is removed from the pending set and the row
   reappears — no bloc event is ever dispatched, so nothing is deleted.
4. If the countdown finishes untouched, `DeleteTransactionEvent` fires and
   the row is permanently removed from the database; the live subscription
   reflects the deletion automatically.

### Observability

`main()` installs a custom `BlocObserver`
([`lib/core/app_bloc_observer.dart`](lib/core/app_bloc_observer.dart)) via
`Bloc.observer = AppBlocObserver()` before `runApp`. It logs, through the
[`logger`](https://pub.dev/packages/logger) package:

- **`onEvent`** — every dispatched event (`AppLaunchEvent`,
  `AddTransactionEvent`, the internal `_TransactionsUpdated`, ...)
- **`onChange`** — every state transition (`TransactionsInitial` → `Loaded`,
  → `TransactionsError`, ...)
- **`onError`** — anything thrown inside a Bloc handler that wasn't already
  caught

This gives a full console trace of the reactive cycle above — useful for
seeing exactly when a stream tick reaches the Bloc versus when a write
handler runs.

### Offline sync queue (transactional outbox)

Every write to `Transactions` or `Categories` also writes a row to
`SyncQueueEntries` — the local durable record of "this needs to reach the
server eventually." This is a **transactional outbox**: the pattern of
writing a business-data change and an "outbox" event in one atomic
transaction, so a separate process can drain the outbox and publish those
events (here, to Supabase) without ever risking the data change and the
sync record disagreeing about what happened. Both halves now exist: the
write side described in this section, and the push/drain side described in
[Push sync to Supabase](#push-sync-to-supabase) below. The design rationale
for the outbox itself is also captured, in shorter form, in
[`docs/sync-queue.md`](docs/sync-queue.md) — the canonical reference for
why "always enqueue" was chosen and what is deliberately deferred.

- **Every write always enqueues, online or offline.** There is exactly one
  code path for every write: local DB write, then enqueue — never a
  connectivity check that branches into "write directly to the server" vs.
  "queue it." A background sync process (not yet built) is the only thing
  that will ever talk to Supabase; from the repository's point of view,
  being online changes nothing about how a write happens, only how soon the
  eventual drain might run. This was a deliberate choice over branching on
  connectivity: a single path is easier to test and reason about, and it
  sidesteps a real failure mode the branching approach can't avoid — being
  "online" at write time doesn't guarantee a direct network write actually
  succeeds, so the offline/fallback path would need to exist and be correct
  regardless.
- **The data write and the enqueue are wrapped in one Drift `transaction()`.**
  `TransactionsRepositoryImpl.addTransaction`/`deleteTransaction` and
  `CategoryRepositoryImpl.addCategory`/`updateCategory`/`deleteCategory` each
  open `dataSource.transaction(() async { ... })`, perform the actual
  insert/update/delete, then call `syncQueueRepository.enqueue(...)` before
  the block closes. If either half fails, Drift rolls back both — there is
  no window where a transaction/category row exists with no matching queue
  entry (which would mean it silently never syncs), and no window where a
  queue entry exists for a write that never actually committed (a "phantom"
  sync). Because `enqueue()` returns a `Result<int>` rather than throwing,
  and Drift's `transaction()` only rolls back on a *thrown* exception, a
  returned `Failure` from `enqueue` is deliberately re-thrown inside the
  transaction block and re-caught just outside it, converting it back to
  `Result` for the caller — see the comment at the throw site in
  `transactions_repository_impl.dart` for why.
- **`payload` is a full snapshot, captured at write time — not a pointer to
  re-fetch later.** `SyncQueueEntries.payload` holds a JSON-encoded copy of
  the entity's data (id, amount, type, note, category, etc. for a
  transaction) at the moment of the write, not just the row's id. The
  alternative — storing only `entityId` and having the eventual drain
  process re-read the current row from local storage — was rejected because
  this app is offline-first by design: a write can sit unsynced for an
  unbounded time, and if the underlying row gets deleted locally before the
  drain ever runs, a pointer-based design would have nothing left to
  re-fetch and would silently lose that `create`/`update` event. A snapshot
  is self-sufficient — the queue row alone has everything needed to replay
  the write, independent of whatever local storage looks like by the time
  it's drained.
- **`SyncQueueRepository` is the only place that knows how to build a queue
  row.** Callers (`TransactionsRepositoryImpl`, `CategoryRepositoryImpl`)
  pass plain values — `entityType`, `entityId`, `operation`, `payload` —
  never a `SyncQueueEntriesCompanion`. `id` (a generated UUID) and
  `createdAt` (a Drift-side default, `withDefault(currentDateAndTime)`, the
  same pattern `Transactions.occurredTime` uses) are owned entirely by
  `SyncQueueRepositoryImpl`, so a third repository added later needs zero
  knowledge of the queue table's schema to participate — just the same
  four-value `enqueue(...)` call every existing writer already makes.
- **What's still open:** there is no `synced`/status column on the table —
  presence in the queue *is* the pending state, by deliberate design (see
  the next section). `SyncQueueRepository.watchPendingCount()` (backed by a
  `COUNT(*)` over the table) is therefore "rows not yet dequeued," not
  "rows that failed" — a row leaves the count only once its push actually
  succeeds.

### Push sync to Supabase

The drain side of the outbox: `SyncRepositoryImpl.pushPending()` reads
every queued row, pushes each one to Supabase independently, and dequeues
it on success. `SyncCubit` decides *when* this runs; `SyncNowButton`/
`SyncSheet` let the user run it *on demand* too. Full decision log in
[`docs/week5-decisions-and-interview-prep.md`](docs/week5-decisions-and-interview-prep.md).

- **Auth is anonymous for now.** `main()` calls `signInAnonymously()` before
  `runApp` so `auth.uid()` is always non-null, which is what Supabase's Row
  Level Security policies actually check. Trade-off, accepted deliberately:
  each fresh install mints a brand-new `auth.uid()`, so there is no durable
  identity across reinstalls/devices yet — real email/password auth is
  future work.
- **Per-row failures don't block the rest of the queue.** `pushPending()`
  loops with a `try`/`catch` around each entry: a row that fails to push
  (network, RLS, a bad id) is logged and left queued for the next attempt;
  the loop continues to the next row rather than aborting the whole pass.
  This is safe specifically because `pushEntry`'s Supabase calls are
  idempotent — `.upsert()` for create/update, and `.delete().eq('id', ...)`
  for delete, which is already a no-op success (not an error) when the row
  is already gone.
- **No `status`/retry-count/error column, by choice.** A row's mere
  presence in `SyncQueueEntries` *is* "not yet confirmed on the server" —
  adding bookkeeping columns for retry counts or backoff was rejected as
  solving a problem this app doesn't have yet at solo-user scale. The one
  concession is per-row error *logging* (not persisted state) so a
  persistently failing row is at least visible in the console instead of
  silently retried forever.
- **The local→remote field mapping lives at the push boundary, not in the
  domain model.** `SupabaseSyncDataSource.mapForSupabase()` renames
  camelCase to snake_case (`amountMinor` → `amount_minor`, etc.) and stamps
  `user_id` immediately before the network call — the local Drift models
  and the queued payload never learn that Supabase, or its column-naming
  convention, exists. This also means a queued row written before an app
  update still pushes correctly after the update changes the mapping,
  since the mapping is applied at push time, not at enqueue time.
- **`SyncCubit` auto-triggers a push on two signals:** connectivity
  regaining `online`, and the pending count *increasing* while already
  online (covers "add a transaction while connected," which doesn't change
  `NetworkStatus` and so wouldn't otherwise be noticed). A count
  *decreasing* never re-triggers a push — that's a push having just
  succeeded, not a new change arriving.
- **`SyncCubit` exposes its outcome as state** (`SyncIdle` /
  `SyncInProgress` / `SyncCompleted` / `SyncFailure`), each carrying an
  `isManual` flag distinguishing a user-triggered `syncNow()` call from an
  auto-trigger. This is what lets the UI show a spinner and a result
  snackbar only for a push the user actually asked for — the silent
  auto-trigger stays silent. An in-flight guard (`if (state is
  SyncInProgress) return;`) stops a manual tap from stacking a second push
  on top of one already running.
- **`SyncCompleted.allFailed` is inferred, not observed.**
  `pushPending()` returns only a count of rows that fully succeeded — if
  every row in the queue fails, the return value is indistinguishable from
  "there was nothing to push." `SyncCubit` compares the pending count
  immediately before and after the push: non-empty before, zero pushed
  after, means everything failed. This is a deliberate, documented
  trade-off — an error *message* still isn't available in the UI, only the
  fact that nothing went through; upgrading `pushPending()`'s return type
  to a small success/failure-count summary is the known next step if that
  becomes a real pain point.
- **Default categories are a known, deferred gap.** The four seeded
  categories are inserted directly by Drift's `onCreate`, bypassing
  `CategoryRepositoryImpl.addCategory()` entirely — so they are never
  enqueued and never reach Supabase for any user. A guarded
  `enqueueDefaultCategories()` was built and then deliberately reverted: no
  correct one-shot guard existed without a persisted flag, and re-enqueuing
  on every launch would grow the queue unboundedly. Deferred until real
  (non-anonymous) auth exists, at which point a per-account seed becomes
  possible.
- **Not yet built:** no mocked-Supabase test exists for `pushEntry()`
  itself (`SupabaseSyncDataSource.mapForSupabase()` is tested directly
  instead — see [Running tests](#running-tests) — since mocktail can't
  reliably intercept the Supabase SDK's `.upsert()` awaitable chain).

### Pull sync (downloading changes from other devices)

The other half of two-way sync: `SyncRepositoryImpl.pullRemoteChanges()`
fetches rows changed remotely since each entity type's own watermark and
applies them locally. It runs right after every push, on the same triggers
(connectivity regained, a new local change queued, or manual "Sync now").

- **One use case runs the whole sync: `SyncDataUseCase`.** Push and pull
  used to be two use cases that `SyncCubit` called one after the other and
  unwrapped itself. They are now sequenced in the domain layer
  (`lib/core/sync/domain/usecases/sync_data_usecase.dart`): it runs
  `PushPendingChangesUseCase`, and returns a `Failure` straight away if the
  queue can't be read (pull is skipped), then runs
  `PullRemoteChangesUseCase` and returns a `SyncSummary` (`pushedCount`,
  `pulledCount`). Pull runs even when nothing was pushed, because it is the
  only way this device learns about changes made elsewhere.
  `SyncCubit` now only decides *when* to sync and turns the `Result` into
  `SyncState`; `allFailed` stays in the cubit because it needs the pending
  count from before the sync, which is cubit state, not domain.
- **A `lastPulledAt` watermark per entity type**, not one shared value.
  `SyncMeta` (a small key-value Drift table, keys like
  `lastPulledAt:transaction`) tracks each table's own progress, mirroring
  how push already treats each queue row's success/failure independently
  (see above) — one table's pull failing doesn't block or roll back the
  other's watermark.
- **Categories are pulled before transactions.** `transactions.category_id`
  is a foreign key to `categories`, and SQLite enforces it. Pulling
  transactions first made a fresh device reject any transaction whose
  category hadn't been pulled yet, skipping that table's pull until the
  next sync. A regression test (`test/sync/sync_repository_pull_test.dart`)
  covers it against a real in-memory database.
- **The watermark is captured before querying, not after applying.** A
  row that changes remotely while a pull is in flight is simply picked up
  again on the next pull instead of being missed — the alternative
  (stamping the watermark at completion) can silently skip a row that
  changed in that window.
- **Last-write-wins, compared on `updated_at`.** Every write path now
  stamps `updatedAt`/`updated_at` explicitly (client-side, in Dart —
  matching the `occurredTime`/`creationTime` convention below, not a
  Postgres trigger, since the client is the one that knows *when the edit
  actually happened*, not just when it happened to reach the server).
  Applying a pulled row compares its `updated_at` against the local row's
  `updatedAt`: the incoming row only overwrites when it's strictly newer;
  a tie or an older incoming row leaves the local copy untouched.
- **Existing rows, migrated from schema v4/v5, default to "now," not to
  `occurredTime`.** Backfilling `updatedAt` from a domain field like
  `occurredTime` would falsely mark old, unrelated rows as "just edited,"
  making them incorrectly win future last-write-wins comparisons against
  genuinely newer data from other devices.
- **Known gap: remote deletes are not propagated.** `pushEntry`'s delete
  branch is a hard `.delete()` with no tombstone left behind, so a pull's
  `select ... where updated_at > :since` has nothing to find for a row
  that was deleted elsewhere — a delete made on one device does not yet
  remove that row on another. Fixing this needs a soft-delete
  (`deleted_at`) column on both tables plus a read-path filter everywhere;
  tracked as follow-up work, not yet implemented.

### Export data (manual backup)

An app-bar action (`ExportAction`, next to "Manage categories" on
`TransactionsScreen`) serializes every transaction and category into one
JSON file and hands it to the OS share sheet via `share_plus`. This is
**not** the sync queue above — the outbox replays individual writes to a
future server; export is a user-triggered, point-in-time snapshot of
current state, read fresh from the database and independent of whatever is
sitting unsynced in `SyncQueueEntries`. For an offline-first app with no
server yet, this is the only real backup path a user has today.

- **A new `backup/` feature, not folded into `transactions/` or
  `categories/`.** Export reads across both features' domains, and neither
  should have to import the other's entities just to support a
  cross-cutting capability — so `backup/` is its own feature, the one
  place allowed to depend on both, while nothing depends on it.
- **`ExportableSource` is the Open/Closed seam.** `BackupRepositoryImpl`
  takes a `List<ExportableSource>` in its constructor and never imports
  `TransactionsRepository` or `CategoryRepository` directly — it only
  knows `source.key` (a string used as the JSON key) and
  `source.exportRows()` (a `Future<List<Map<String, Object?>>>`).
  `TransactionsExportSource` and `CategoriesExportSource` (living beside
  each feature's own repository impl, in `data/repos/`) are the only two
  places that know how to turn a `TransactionEntity`/`CategoryEntity` into
  a plain map. Adding a third exportable table later — a future
  `BudgetsExportSource`, say — means writing one new class and adding one
  line to the `sources: [...]` list in `service_locator.dart`;
  `BackupRepositoryImpl` itself never needs to change.
- **Only the JSON encode runs on a background isolate — not the DB read.**
  `BackupRepositoryImpl.exportToJson()` calls each source's `exportRows()`
  on the main isolate first (cheap: a handful of repository/Drift calls),
  collects the results into one `Map<String, List<Map<String, Object?>>>`,
  then hands only that plain, isolate-safe data to
  `await Isolate.run(() => encodeExport(sourceData))`. `encodeExport` and
  `buildEnvelope` (`lib/features/backup/data/export_serializer.dart`) are
  deliberately pure top-level functions with no Flutter or Drift imports —
  nothing they close over is tied to the main isolate, and they're
  unit-testable with no database or widget tree at all. The honest caveat:
  `jsonEncode` is not always the expensive half of an export — row mapping
  and the Drift read can cost as much or more for a given dataset size: if
  a benchmark ever shows the query itself dominating, the isolate boundary
  can move earlier (e.g. `Drift`'s `computeWithDatabase`) without changing
  `BackupRepository`'s interface.
- **The envelope has its own `formatVersion`, separate from Drift's
  `schemaVersion`.** The two can change independently: a new export field
  bumps `formatVersion`; a new table/column bumps the database's
  `schemaVersion` (currently 6, recorded in the envelope only as
  diagnostic info). `'counts'` in the envelope is computed generically —
  `sourceData.map((key, rows) => MapEntry(key, rows.length))` — so it
  reflects however many sources actually ran, with no hardcoded field per
  table.
- **Timestamps are ISO-8601 UTC strings; `amountMinor` stays an integer.**
  Same reasoning as the database schema itself (see
  [Design decisions](docs/technical-decisions.md) below): JSON has no native date
  type, so `DateTime` must become a string at the export boundary, and UTC
  keeps it unambiguous across devices/timezones. Emitting a decimal amount
  instead of minor units would reintroduce exactly the floating-point
  drift the schema was designed to avoid.
- **The file is written to the OS temp directory, not app documents.**
  `getTemporaryDirectory()` (via `path_provider`, already a dependency),
  because the file is a transient hand-off to the share sheet — not app
  state Money Log owns or needs to keep around after the user has saved it
  somewhere else.
- **`ExportCubit` has exactly one public method, `export()`, and an
  in-flight guard (`if (state is ExportInProgress) return;`).** Matches
  `BalanceCubit`/`CategoryTotalsCubit`'s choice of `Cubit` over `Bloc` —
  one action, no event vocabulary needed. Unlike every other write in this
  app (`AddTransactionEvent`, `AddCategoryEvent`, ...), which emit nothing
  on success because a live Drift stream updates the UI instead, export
  has no such stream: `ExportSuccess(file)` is the only signal the UI will
  ever get, so the use case's return value has to be carried into state
  directly.
- **Not yet built:** import/restore (the envelope's `formatVersion` and
  category-first field ordering are designed to make this possible later,
  but no reader exists yet), CSV export, scheduled/automatic backups, and
  encryption — the exported file is plaintext financial data, which is
  worth knowing before sharing it through the OS share sheet.

## 🗄️ Database schema

```mermaid
erDiagram
    TRANSACTIONS {
        TEXT id PK "UUID, generated client-side"
        INTEGER amountMinor "amount in minor units (cents)"
        TEXT type "enum: income | expense"
        TEXT note "nullable"
        DATETIME occurredTime "defaults to now; can be backdated"
        DATETIME creationTime "defaults to now; row insert time"
        DATETIME updatedAt "set explicitly on every write; drives last-write-wins pull sync"
        TEXT categoryId FK "nullable, references CATEGORIES.id, ON DELETE SET NULL"
    }
    CATEGORIES {
        TEXT id PK "fixed string for seeded rows, e.g. 'default-food'"
        TEXT name
        TEXT colorHex "nullable, e.g. '#FF9800'"
        DATETIME updatedAt "set explicitly on every write; drives last-write-wins pull sync"
    }
    SYNC_QUEUE_ENTRIES {
        TEXT id PK "UUID, generated client-side by SyncQueueRepositoryImpl"
        TEXT entityType "e.g. 'transaction', 'category' -- not an FK, just a label"
        TEXT entityId "id of the row that changed, in whichever table entityType names"
        TEXT operation "enum: create | update | delete"
        TEXT payload "JSON snapshot of the entity at write time"
        DATETIME createdAt "defaults to now, via withDefault(currentDateAndTime)"
    }
    SYNC_META {
        TEXT key PK "e.g. 'lastPulledAt:transaction', 'lastPulledAt:category'"
        DATETIME value "watermark: rows pulled up to this point in time"
    }
    TRANSACTIONS }o--o| CATEGORIES : "categorized as"
```

`SyncQueueEntries` deliberately has **no foreign key** to `Transactions` or
`Categories` — `entityType`/`entityId` are a soft reference by design, since
the whole point of the outbox is to keep a durable, replay-safe record of a
write that must survive the original row being deleted before the queue is
ever drained (see [Offline sync queue](#offline-sync-queue-transactional-outbox)
above).

### Design decisions

The schema, category-coupling, and project-structure trade-offs behind this
app (why `id` is a client-generated UUID, why `amountMinor` is an integer,
the `ON DELETE SET NULL` choice, the fixed category palette, and more) are
documented in full in
**[`docs/technical-decisions.md`](docs/technical-decisions.md)** — kept
out of this file to keep the README focused on getting started and feature
overview.

## ✅ What's implemented / 🚧 Not yet done

Fully built: reactive transactions + categories (CRUD, swipe-to-delete with
undo, spending-by-category totals), an offline-first sync queue with
two-way push/pull to Supabase, connectivity/pending-sync UI, and manual
data export (serializer complete, UI trigger still a deliberate no-op).
Known gaps: no transaction editing, no remote-delete propagation on sync,
and anonymous-only auth (no durable identity across reinstalls).

**→ [Full implementation checklist + known gaps](docs/implemented.md)**

## 🏷️ Release notes

Per-version changelog (v0.1.0 through the current v0.6.0 — push sync to
Supabase, manual "Sync now", and everything before it) now lives in
**[`docs/release-notes.md`](docs/release-notes.md)**, kept separate from
this file so the README stays focused on the app as it is today rather than
how it got here.

## 📄 License

[MIT](LICENSE) — free to use, modify, and distribute, with no warranty.
