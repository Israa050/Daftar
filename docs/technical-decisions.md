# Technical Decisions

Architecture, schema, and design trade-offs made across Money Log, extracted
from the README to keep that file focused on getting started and feature
overview. For the sync/push-sync-specific decision log (with interview-prep
framing), see
[`week5-decisions-and-interview-prep.md`](week5-decisions-and-interview-prep.md).

## Database schema

- **`id` is a client-generated UUID (`TEXT`), not an autoincrement integer.**
  Autoincrement IDs only exist after a row commits, which blocks
  optimistic-UI inserts and can collide once multiple devices insert data
  offline and later sync. A UUID can be generated before the insert and stays
  unique across devices with no coordination. Trade-off: slightly larger
  storage per row than an integer key — acceptable for a local, low-volume
  ledger table.
- **`amountMinor` is an `INTEGER` (minor units, e.g. cents), not a `double`.**
  Floating-point can't represent most decimal fractions exactly
  (`0.1 + 0.2 != 0.3` in IEEE 754), so summing amounts as `double` drifts over
  time. Storing whole minor units keeps every arithmetic operation exact;
  conversion to a display string (`$3.50`) happens only at the UI boundary.
- **`type` is a Drift `textEnum<TransactionType>`, not a bare `TEXT` column.**
  The set of valid values is fixed and known (`income`, `expense`), so the
  column is typed to match — the compiler catches typos and invalid values at
  the call site instead of letting malformed strings reach the database.
- **`note` is nullable; `occurredTime`/`creationTime` are not.**
  A transaction doesn't always have a note, so the column allows `NULL`.
  Both timestamps default to "now" via `withDefault(currentDateAndTime)`, but
  `occurredTime` can be overridden on insert to log a backdated transaction,
  while `creationTime` is meant to always reflect actual insert time.
- **`categoryId`'s foreign key is `ON DELETE SET NULL`, not the SQLite default
  (`NO ACTION`) or `CASCADE`.** With categories now deletable, `NO ACTION`
  would make deleting any category with transactions attached throw a
  constraint violation (SQLite enforces this immediately —
  `beforeOpen` turns `PRAGMA foreign_keys = ON`). `CASCADE` was rejected too:
  deleting a category is removing an organizational label, not disputing
  that money was spent, so silently destroying the transactions themselves
  would be the wrong failure mode for a finance app. `SET NULL` orphans the
  transaction into the existing "Uncategorized" bucket instead — a state
  `watchCategoryTotals()`/`CategoryTotalsCard` already render correctly, so
  no new UI branch was needed for it. This changed the schema
  (`schemaVersion` 2 → 3) via a `TableMigration`, since SQLite can't `ALTER`
  a column's foreign-key action in place — drift's `alterTable` rebuilds the
  table (create-copy-drop-rename) with the new constraint.
- **`SyncQueueEntries` was added as schema v4** (`onUpgrade`'s
  `if (from < 4) { await m.createTable(syncQueueEntries); }`) rather than
  bundled into the v3 migration. It's an independent table with no foreign
  keys to `Transactions`/`Categories` (see
  [Database schema](database.md) for why the
  reference is deliberately soft), so a plain `createTable` was sufficient —
  no `TableMigration`/rebuild needed the way `categoryId`'s FK change
  required.
- **`SyncQueueEntries.createdAt` uses `withDefault(currentDateAndTime)`,
  not a Dart-side `DateTime.now()` passed in by the repository.** Matches
  `Transactions.occurredTime`/`creationTime`'s existing convention of
  letting the database stamp insert time rather than the caller — keeps
  `SyncQueueRepositoryImpl.enqueue`'s `Companion.insert(...)` call from
  needing to pass a timestamp at all.

## Categories

- **`CategoryRepository.watchCategories()` returns a `Stream<List<CategoryEntity>>`,
  not a one-shot `Future`** (this replaced the original `Future`-returning
  `getCategories()` once a manage-categories screen existed). A `Future`
  fetched once in `TransactionsBloc._onLaunch` meant a category created,
  renamed, or deleted on the new screen would not appear anywhere else —
  the add-transaction chips, the transaction-tile pills — until the app
  restarted, which contradicts this app's whole "no manual refresh"
  premise. `TransactionsBloc` now holds a second `StreamSubscription`
  (alongside the transactions one) feeding a private `_CategoriesUpdated`
  event, so both streams merge into the same `Loaded.categories` field.
  Trade-off: because the two subscriptions start independently and Drift
  gives no guarantee about which one's first tick lands first, a fresh
  `AppLaunchEvent` can legitimately emit `Loaded` more than once before
  settling — callers should assert on the final state, not the emission
  count (see `transactions_bloc_test.dart`'s "settles on Loaded([])" test).
- **Category name uniqueness is enforced in `CategoryRepositoryImpl`, not as a
  SQL `UNIQUE` constraint.** Adding a unique index would need its own schema
  migration; validating in the repository (trim, reject empty, reject a
  case-insensitive duplicate via `findCategoryByName`) gives the same
  guarantee without one, and returns a `Result.failure` with a message the
  UI can show directly instead of parsing a raw SQLite constraint error.
  Case-insensitivity matters because SQLite's default text collation is
  case-sensitive (`BINARY`), so `name.equals(...)` alone would let
  `"groceries"` and `"Groceries"` coexist — `findCategoryByName` compares
  `.lower()` on both sides specifically to close that gap.
- **The four seeded default categories are not protected from edit or
  delete.** They're ordinary rows distinguished only by their fixed
  `'default-*'` ids, not a special "system category" flag — a user can
  rename, recolor, or remove any of them. Protecting them would mean a
  disabled delete button the user can't act on and a `startsWith('default-')`
  check leaking into the UI layer, for a restriction nothing in the product
  actually calls for; an empty category list is already a handled state
  (the add sheet hides its chips section, `CategoriesScreen` shows an empty
  state).
- **The category color picker is a fixed swatch palette
  (`kCategoryPalette`, 12 hex strings), not a free-form color picker
  package.** A full HSV/RGB picker (e.g. `flutter_colorpicker`) would add a
  dependency to an intentionally lean `pubspec.yaml` (no UI packages beyond
  Flutter/Cupertino today) and lets a user pick a color that's illegible
  against the app's `surface` color in one of the two themes. A curated
  palette — a superset of the four seeded colors — is guaranteed to render
  visibly in both light and dark mode, at the cost of not offering unlimited
  color choice.
- **4 default categories (Food, Transport, Shopping, Bills) are seeded via
  `onCreate` in `TransactionsDataSource`'s `MigrationStrategy`, with fixed
  string ids (`'default-food'`, etc.) instead of generated UUIDs.** `onCreate`
  only fires for brand-new databases, so existing dev installs that already
  migrated to schema v2 do **not** retroactively get seeded rows — acceptable
  pre-release, but would need a backfill migration once real user data exists.

## Transactions ↔ categories coupling

- **`AddTransactionEvent`/`addTransaction(...)` take a plain `String? categoryId`,
  not a `CategoryEntity?`.** Keeping the write path on primitive ids (the same
  pattern `deleteTransaction(String id)` already uses) avoids the
  `transactions` domain/repository layer importing `CategoryEntity` just to
  read `.id` off it — a repository whose job is "persist a transaction"
  doesn't need to know what a category *is*, only its foreign key.
- **`categoryId` is threaded through `TransactionsBloc`, not fetched directly
  by `AddTransactionSheet` via `get_it`.** `WatchCategoriesUseCase` is a
  constructor dependency of `TransactionsBloc` (alongside the other three use
  cases), subscribed to in `_onLaunch` and carried in `Loaded.categories`.
  The alternative — the sheet calling `getIt<WatchCategoriesUseCase>()()`
  directly in a `StreamBuilder` — would bypass the bloc layer and introduce a
  second, inconsistent way widgets access use cases in this codebase; every
  other read/write already goes through the bloc, so categories do too.
- **Category CRUD lives in a new `CategoriesBloc`, not folded into
  `TransactionsBloc`.** `TransactionsBloc` only ever *reads* categories (for
  the chips/pills); it has no reason to also own `AddCategoryEvent`/
  `UpdateCategoryEvent`/`DeleteCategoryEvent` and their error states —
  doing so would bloat one bloc with two unrelated responsibilities and
  couple `CategoriesScreen`'s lifecycle to `TransactionsScreen`'s
  `BlocProvider`. This mirrors how `BalanceCubit` and `CategoryTotalsCubit`
  are already separate from `TransactionsBloc` despite reading the same
  tables — single-responsibility blocs, not one mega-bloc, is the
  established pattern here.
- **`categoryTotals` uses a `leftOuterJoin`, not an inner join, and filters to
  `type == expense` at the query level rather than inside the sum.** An inner
  join would silently drop every transaction with `categoryId == null` from
  the result set, so "spending by category" would quietly under-report
  instead of showing an honest "Uncategorized" bucket — the left join is what
  makes that bucket reachable at all. Filtering with `..where(...)` before
  `groupBy` (rather than `sum(filter: ...)`, as `balance` does) was chosen
  because this query only ever needs one type, not two sums side by side, so
  restricting the row set up front is simpler than filtering per-aggregate.
- **`CategoryRepositoryImpl` maps `TypedResult` rows to a plain
  `CategoryTotalRow` class inside `TransactionsDataSource.categoryTotals`,
  not inside the repository.** Drift's joined-query expressions
  (`categories.id`, the `Sum` aggregate, etc.) only exist in scope where the
  query itself is built; re-declaring them in the repository to call
  `row.read(...)` there would create second, independent expression
  instances not guaranteed to match the ones the query actually used. Doing
  the `TypedResult` → plain-object mapping at the data source boundary keeps
  every Drift-specific type — including `TypedResult` itself — from ever
  crossing into `data/repos/`, `domain/`, or above.

## Project structure

- **The codebase is organized under `lib/features/` (`transactions/`,
  `categories/`) plus `lib/core/` (`connectivity/`, `sync/`, `theme/`),
  rather than one flat `lib/transactions/` containing everything** (an
  earlier structure this app briefly had). `categories/` was extracted from
  `transactions/` once it became clear category CRUD, its bloc, and its
  screens don't need to know anything about transactions — but the split is
  intentionally partial: `Categories`, `SyncQueueEntries`, and the joined
  `categoryTotals` query all still live inside
  `transactions_data_source.dart`, because Drift's transaction/FK
  guarantees require every table sharing those guarantees to be in one
  `@DriftDatabase` class. Moving the *files* into `features/categories/` and
  `core/sync/` doesn't remove that coupling — it just makes explicit which
  parts of the app are genuinely feature-local (CRUD, bloc, screens) versus
  genuinely shared (the database class itself, cross-table queries).
