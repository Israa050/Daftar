# Changelog

Notes for each build pushed to `production`. The top entry is what
Firebase App Distribution shows testers for the current release.

## v0.7.0 — Two-way sync: changes flow back, and the later edit wins

- Sync is now **two-way**. After every push (automatic or "Sync now"), the
  app also **pulls** changes made on other devices signed into the same
  account and applies them here, creating rows that don't exist yet and
  updating ones that changed.
- **The later edit wins, in both directions.** An incoming change replaces
  what is on this device only if it is newer, and a change you made offline
  can no longer overwrite a newer edit made elsewhere: the server now
  ignores a stale write, and the newer version comes down on the next pull.
  Two edits in the same second tie, and this device keeps its own copy.
- "Sync now" reports both directions, e.g. "Synced 2 changes out, 1 change
  in." It no longer counts your own change coming back as an incoming one.
- A new device now brings in categories before the transactions that use
  them, so transactions no longer fail to appear on the first sync.
- Each table (transactions, categories) remembers where its last pull got
  to, so a pull only fetches what changed, and a failure in one table's
  pull doesn't hold up the other.
- Behind the scenes: the backend database schema is now versioned in the
  repository (`supabase/migrations`), with indexes that speed up the pull.
- **Known gaps:**
  - Deleting a row on one device does not yet remove it on another.
  - Transactions can be added and deleted but not edited yet.
  - Sign-in is anonymous, so your data doesn't follow you to a reinstall
    or a second phone yet.
  - An older version of the app on another device doesn't have the
    "ignore stale writes" check until it is updated.

## v0.6.0 — Push sync to Supabase & manual "Sync now"

- Local changes now actually **sync to a server**: queued transactions and
  categories are pushed to Supabase whenever connectivity comes back online
  or a new change is made while already online. Sign-in is anonymous for
  now — no account setup needed, but data doesn't yet follow you across a
  reinstall or a second device.
- Added a **manual "Sync now"** action: tap the pending-changes badge in
  the app bar to open a sheet showing how many changes are waiting and a
  button to push them immediately, instead of waiting for the automatic
  trigger. It's disabled with a reason (syncing / offline / nothing to
  sync) rather than just doing nothing, and shows a result once it's done
  ("Synced N changes" or "Couldn't send your changes — they're still
  saved on this device").
- The pending-changes badge is now always visible in the app bar (not just
  when something is queued), so sync is reachable at any time.
- Failed pushes stay queued and retry automatically — nothing is silently
  dropped.

## v0.5.0 — Offline banner & sync queue

- Added a **connectivity layer** (`lib/core/connectivity/`): wraps
  `connectivity_plus` behind a `ConnectivityRepository` that maps the
  plugin's results down to a domain `NetworkStatus` enum, with an
  `ConnectivityCubit` broadcasting it app-wide. "Offline" is a normal
  `Success(NetworkStatus.offline)`, not an error; `Failure` is reserved for
  real connectivity-check errors.
- Added a **transactional outbox** (`lib/core/sync/`): every write to
  `Transactions` or `Categories` now also records a row in a new
  `SyncQueueEntries` Drift table (schema v4), in the *same* Drift
  `transaction()` as the write itself — so the change and its sync record
  either both commit or neither does. Every write always enqueues,
  regardless of connectivity; see `docs/sync-queue.md` for why. The
  background process that drains the queue to a server is not built yet.
- Added an **offline banner**: a strip above the transaction list, shown
  while the device has no network interface. The copy is informational
  ("changes are saved on this device"), not an error.
- Added a **pending-changes badge**: an app-bar badge showing how many
  local writes are waiting to sync (hidden at zero), backed by the
  sync-queue count stream. The count only grows for now (no drain process),
  so it reads as "changes recorded on this device", not "sync failures".
- Reorganized the codebase from a single `lib/transactions/` folder into
  `lib/features/{transactions,categories}/` plus
  `lib/core/{connectivity,sync,theme}/`.
- Added test suites for the connectivity layer (repository mapping rule +
  error path, cubit lifecycle, use case), the sync queue
  (`SyncQueueRepositoryImpl` against a real in-memory Drift database, use
  case passthrough), and the export serializer (`buildEnvelope` /
  `encodeExport`).

## v0.4.0 — Manage categories

- Categories are now a fully editable resource: a new "Manage Categories"
  screen (opened from the transactions app bar) supports creating,
  renaming/recoloring, and deleting categories, closing the gap called out
  in v0.3.0.
- Changed `transactions.categoryId`'s foreign key to `ON DELETE SET NULL`
  (schema v2 → v3 migration) so deleting a category with transactions
  attached orphans them into the existing "Uncategorized" bucket instead of
  failing with a constraint error.
- `CategoryRepository` gained a reactive `watchCategories()` (replacing the
  old one-shot fetch) plus `addCategory`/`updateCategory`/`deleteCategory`,
  so a category change on the new screen now appears immediately in the
  add-transaction chips and transaction-tile pills — no restart required.
- Category names are validated on add/update: trimmed, rejected if empty,
  and rejected as a case-insensitive duplicate of an existing name.
- Color selection uses a fixed 12-swatch palette (a superset of the four
  seeded colors) instead of a free-form picker, so every color stays
  legible in both light and dark theme.
- Added a new `CategoriesBloc`, kept separate from `TransactionsBloc` (which
  only reads categories), following the same single-responsibility split
  already used for `BalanceCubit`/`CategoryTotalsCubit`.
- Added test coverage for all of the above: category CRUD and the
  `ON DELETE SET NULL` orphaning behavior against a real in-memory Drift
  database, repository-level name validation, and `CategoriesBloc`
  success/failure emissions via mocktail.

## v0.3.0 — Category totals & tags

- Added categories: a `Categories` Drift table with a nullable FK on
  `transactions.categoryId`, four default categories (Food, Transport,
  Shopping, Bills) seeded on database creation, a `CategoryRepository` +
  `GetCategoriesUseCase` mirroring the transactions domain/data split, and a
  color-coded category picker in the add-transaction sheet, sourced from
  `TransactionsBloc` state.
- Added reactive total spending per category: a Drift `leftOuterJoin` +
  `groupBy` query groups expense transactions by category (uncategorized
  spend included as its own bucket), wired through `CategoryRepository`,
  `WatchCategoryTotalsUsecase`, and a new `CategoryTotalsCubit` to a
  collapsible `CategoryTotalsCard` on the transactions screen.
- Transaction rows now show a color-coded category tag next to the title
  when a category is set, resolved from the same category list already
  loaded for the add-transaction picker.
- Fixed a bottom-sheet overflow in the add-transaction form by making its
  content scrollable, so it no longer clips when the keyboard is open.
- Not yet surfaced: editing/managing categories.

## v0.2.0+2

- Fixed a typo in the Drift schema: `occuredTime` → `occurredTime` (column
  and field), caught before any real user data existed so no migration was
  needed.
- Added mocktail-based unit tests for `TransactionsBloc` and
  `BalanceCubit`, covering failure paths a real repository couldn't be
  forced into.
- Fixed a silent bug where a repository stream error during app launch
  produced an uncaught async error instead of a `TransactionsError` state.
- Set up the `production` deploy pipeline: signed release builds now go
  out to Firebase App Distribution automatically, with real per-release
  notes pulled from this file.
- Added a "Download APK" badge to the README linking to the latest GitHub
  release, so visitors can actually install the app instead of just
  reading about it.

## v0.2.0 — Themed redesign

- Introduced a dedicated design system (`AppColors` + `AppTheme`) with
  light and dark color tokens — dark-first, following the system theme by
  default — replacing the single generic Material seed color.
- Split the 350+ line `transactions_screen.dart` into small, single-purpose
  widgets (`BalanceSummaryCard`, `StatPill`, `TransactionsList`,
  `TransactionsEmptyState`, `UndoSnackBarContent`), leaving the screen file
  as pure composition and state wiring.
- Restyled `TransactionTile` and `AddTransactionSheet` to match the new
  visual language: circular type icons on income/expense wash colors,
  card-style rows, and a segmented add/expense toggle.
- Refreshed the app screenshots to reflect the new look.

## v0.1.0 — Reactive core

- `TransactionsBloc` made fully reactive via a single long-lived Drift
  `.watch()` subscription — add/delete no longer trigger a manual refetch.
- Added a DB-computed `BalanceCubit` stream and hardened amount parsing
  (exact minor-unit arithmetic, no floating-point drift).
- Full presentation layer: balance summary, swipe-to-delete with animated
  undo, and an add-transaction bottom sheet.
- Drift-backed `Transactions` schema, `TransactionsRepository`, and
  `AppBlocObserver` for full event/state logging.
- GitHub Actions CI running format checks, static analysis, and the full
  test suite on every PR into `main`.
