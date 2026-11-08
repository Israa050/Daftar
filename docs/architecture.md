# Architecture: Project Structure

The full `lib/` directory tree and the dependency-layering rules —
extracted from the README to keep that file short for a first-time visitor.
See also [`reactive-architecture.md`](reactive-architecture.md) for how data
actually flows through these layers, [`database.md`](database.md) for the
schema (ERD), and [`technical-decisions.md`](technical-decisions.md) for the
trade-offs behind specific choices made here.

## Project structure

The app is organized feature-first under `lib/features/`, with genuinely
cross-cutting concerns (connectivity, the offline sync queue, theming) kept
in `lib/core/` instead of inside any one feature:

```
lib/
├── core/
│   ├── app_bloc_observer.dart     # Logs every Bloc event/state change/error
│   ├── result.dart                # Result<T> (Success/Failure) — shared success/error wrapper
│   ├── service_locator.dart       # get_it setup — binds every repository, use case, Bloc/Cubit
│   ├── connectivity/              # Cross-cutting network-status layer (not a feature — see below)
│   │   ├── domain/
│   │   │   ├── network_status.dart          # online/offline enum, owned by domain
│   │   │   ├── connectivity_repository.dart # Abstract interface — zero data-layer/plugin imports
│   │   │   └── usecases/
│   │   │       └── watch_connectivity_usecase.dart
│   │   ├── data/
│   │   │   └── connectivity_repository_impl.dart # Wraps connectivity_plus; maps ConnectivityResult -> NetworkStatus
│   │   ├── cubit/
│   │   │   └── connectivity_cubit.dart      # Broadcasts NetworkStatus app-wide; registered as a singleton
│   │   └── presentation/
│   │       └── widgets/
│   │           └── offline_banner.dart      # Strip shown above screen content while offline; driven by ConnectivityCubit
│   ├── sync/                      # Offline outbox + push-sync layer (not a feature — see below)
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── operation_type.dart          # create/update/delete enum, owned by domain
│   │   │   │   └── sync_queue_entry_entity.dart # Plain domain model for one queued entry
│   │   │   ├── repositories/
│   │   │   │   ├── sync_queue_repository.dart   # Abstract interface — enqueue(...), getPending(), dequeue(id), watchPendingCount()
│   │   │   │   └── sync_repository.dart         # Abstract interface — pushPending(): reads the queue, pushes each entry independently
│   │   │   └── usecases/
│   │   │       ├── watch_pending_sync_count_usecase.dart
│   │   │       └── push_pending_changes_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── sync_queue_entries.dart      # Drift table definition — id, entityType, entityId, operation, payload, createdAt
│   │   │   ├── datasources/
│   │   │   │   └── supabase_sync_data_source.dart # pushEntry(): upsert on create/update, delete().eq() on delete; maps local camelCase -> remote snake_case + stamps user_id
│   │   │   └── repos/
│   │   │       ├── sync_queue_repository_impl.dart # Implements SyncQueueRepository against TransactionsDataSource
│   │   │       └── sync_repository_impl.dart      # Implements SyncRepository; per-entry try/catch so one failure doesn't block the rest of the pass
│   │   ├── cubit/
│   │   │   ├── pending_sync_cubit.dart          # Broadcasts the queue-count stream (Cubit<int>); registered as a singleton
│   │   │   └── sync_cubit.dart                  # Cubit<void>; triggers pushPending() on reconnect and when the queue count increases while online
│   │   └── presentation/
│   │       └── widgets/
│   │           └── pending_sync_badge.dart      # App-bar badge over PendingSyncCubit; hidden at zero
│   └── theme/
│       ├── app_colors.dart        # Semantic color tokens (light/dark) as a ThemeExtension
│       └── app_theme.dart         # Builds ThemeData (app bar, cards, inputs, FAB...) from the tokens
└── features/
    ├── transactions/
    │   ├── bloc/                  # TransactionsBloc, BalanceCubit — depend on use cases only
    │   ├── domain/
    │   │   ├── entities/
    │   │   │   ├── transaction_entity.dart     # Plain domain model — no Drift types; carries categoryId
    │   │   │   └── transaction_type.dart       # income/expense enum, owned by domain
    │   │   ├── repositories/
    │   │   │   └── transactions_repository.dart  # Abstract interface — zero data-layer imports
    │   │   └── usecases/
    │   │       ├── get_transactions_usecase.dart
    │   │       ├── watch_balance_usecase.dart
    │   │       ├── add_transaction_usecase.dart
    │   │       └── delete_transaction_usecase.dart
    │   ├── data/
    │   │   ├── models/
    │   │   │   └── transactions.dart  # Drift table definition (imports TransactionType from domain); categoryId FK -> Categories, ON DELETE SET NULL
    │   │   ├── repos/
    │   │   │   └── transactions_repository_impl.dart  # Implements TransactionsRepository; maps Drift rows <-> entities; every write is wrapped in one atomic Drift transaction() alongside a SyncQueueRepository.enqueue() call
    │   │   ├── connection.dart                   # Platform-specific Drift connection
    │   │   ├── transactions_data_source.dart     # The single Drift database class (real persistence, schema v6) for Transactions, Categories, SyncQueueEntries, AND SyncMeta — see note below
    │   │   └── transactions_data_source.g.dart   # Generated by drift_dev — do not edit
    │   └── presentation/
    │       ├── format.dart                         # Amount/date formatting + parseHexColor helper (shared across features)
    │       ├── screens/
    │       │   └── transactions_screen.dart        # Main screen: composes the widgets below; app bar action opens CategoriesScreen
    │       └── widgets/
    │           ├── add_transaction_sheet.dart       # Bottom sheet for creating a transaction
    │           ├── balance_summary_card.dart        # Balance figure + income/expense stat pills
    │           ├── stat_pill.dart                   # Single income/expense mini stat
    │           ├── transaction_tile.dart            # Swipe-to-delete row; shows a category pill when categoryId resolves
    │           ├── transactions_list.dart           # List/empty-state switch; resolves each row's category by id before rendering
    │           ├── transactions_empty_state.dart    # "No transactions yet" placeholder
    │           └── undo_snackbar_content.dart        # Snackbar body with a shrinking countdown bar
    └── categories/
        ├── bloc/
        │   ├── categories_bloc.dart        # Owns category CRUD; separate from TransactionsBloc, which only reads categories
        │   ├── categories_event.dart
        │   ├── categories_state.dart
        │   └── category_totals_cubit.dart  # Aggregate-stream cubit shaped like BalanceCubit
        ├── domain/
        │   ├── entities/
        │   │   ├── category_entity.dart        # Plain domain model — id, name, optional colorHex
        │   │   └── category_total_entity.dart  # One category's total expense — nullable id/name for the "Uncategorized" bucket
        │   ├── repositories/
        │   │   └── category_repository.dart      # Abstract interface — reactive watchCategories()/watchCategoryTotals(), Result-returning CRUD writes
        │   └── usecases/
        │       ├── watch_categories_usecase.dart
        │       ├── add_category_usecase.dart
        │       ├── update_category_usecase.dart
        │       ├── delete_category_usecase.dart
        │       └── watch_category_totals_usecase.dart
        ├── data/
        │   ├── models/
        │   │   └── categories.dart    # Drift table definition — id, name, nullable colorHex
        │   └── repos/
        │       └── category_repository_impl.dart  # Implements CategoryRepository against TransactionsDataSource; maps Drift rows <-> entities, incl. CategoryTotalRow -> CategoryTotalEntity; validates name trim/empty/case-insensitive-duplicate; every write wrapped in an atomic transaction() + enqueue()
        └── presentation/
            ├── category_palette.dart               # Fixed 12-swatch hex palette used by the category editor
            ├── screens/
            │   └── categories_screen.dart          # Manage-categories screen: list + add/edit/delete
            └── widgets/
                ├── category_totals_card.dart        # Collapsible spending-by-category card, reactive via CategoryTotalsCubit
                ├── category_list_tile.dart          # One row on CategoriesScreen: color dot, name, edit/delete icon buttons
                ├── category_editor_sheet.dart       # Bottom sheet for creating or editing a category (name + palette picker)
                └── delete_category_dialog.dart      # Confirmation dialog warning that orphaned transactions become "Uncategorized"
    └── backup/
        ├── cubit/
        │   ├── export_cubit.dart            # ExportCubit -- single export() method, one ExportDataUseCase dependency
        │   └── export_state.dart            # ExportState: Idle / InProgress / Success(file) / Failure(message)
        ├── domain/
        │   ├── entities/
        │   │   ├── exportable_source.dart   # Abstract source contract -- key + exportRows(); the OCP seam (see below)
        │   │   └── exported_file.dart       # Plain result value -- path, byteSize, countsByKey
        │   ├── backup_repository.dart       # Abstract interface -- exportToJson() is its only method
        │   └── usecases/
        │       └── export_data_usecase.dart # Thin call() wrapper around BackupRepository.exportToJson()
        ├── data/
        │   ├── export_serializer.dart       # Pure functions (no Flutter/Drift imports) -- buildEnvelope + encodeExport, the Isolate.run payload
        │   └── backup_repository_impl.dart  # Implements BackupRepository; loops ExportableSources, spawns the isolate, writes the temp file
        └── presentation/
            └── widgets/
                └── export_action.dart       # App bar IconButton; BlocConsumer drives spinner/snackbars and the share_plus call
```

> **Why `Categories` and `SyncQueueEntries` live inside
> `transactions_data_source.dart` instead of their own feature's `data/`
> folder:** Drift transactions and foreign keys cannot span two separate
> `@DriftDatabase` classes — there is exactly one SQLite connection/file for
> the whole app, `transactions.sqlite`, and every table shares it. The table
> *definitions* (`categories.dart`, `sync_queue_entries.dart`) live under
> their own feature/module folder and are just imported into
> `transactions_data_source.dart`'s `@DriftDatabase(tables: [...])` list —
> only the physical database class itself has to be shared. This is what
> makes the atomic-write guarantee possible: a transaction row and its
> sync-queue row can be written in one Drift `transaction()` block only
> because they're on the same connection.

## Layering

Dependencies point inward, toward `domain/`, within each feature — and
`core/sync` sits underneath every feature that writes data:

```
presentation → bloc → domain/usecases → domain/repositories (abstract)
                                              ^
                                              |
                                data/repos (implements the interface)
                                              |
                                              v
                                  core/sync: SyncQueueRepository (abstract)
                                              ^
                                              |
                                core/sync/data/repos (implements the interface)
```

- **`domain/`** has zero imports from `data/` in any feature — `TransactionEntity`,
  `TransactionType`, `TransactionsRepository` (the abstract interface), and
  the equivalents in `categories/` and `core/sync/` are plain Dart with no
  Drift types anywhere in their signatures.
- **`TransactionsRepositoryImpl`** and **`CategoryRepositoryImpl`** (in each
  feature's `data/repos/`) are the only places that know both worlds: they
  implement their domain interface, map Drift's generated rows to/from
  entities, *and* coordinate the atomic write + sync-queue-enqueue described
  in [Offline sync queue](sync-queue.md#the-outbox-every-write-enqueues)
  section.
- **Use cases** (`domain/usecases/`) are thin, single-method wrappers around
  one repository call each — blocs/cubits depend only on these, never on a
  repository interface or impl directly.
- **`SyncQueueRepository`** is depended on by `TransactionsRepositoryImpl`
  and `CategoryRepositoryImpl` the same way any repository depends on
  another narrow interface — those repositories know `enqueue(entityType:,
  entityId:, operation:, payload:)`, never `SyncQueueEntries`'s Drift schema
  or how a queue row's `id`/`createdAt` are generated. This keeps every
  future repository that needs to enqueue (there will be more than these
  two) from duplicating `SyncQueueEntriesCompanion`-building logic — that
  knowledge lives in exactly one place, `SyncQueueRepositoryImpl`.
- **DI** (`service_locator.dart`) binds every `*Impl` against its abstract
  interface type, so swapping the persistence layer later would mean
  writing a new impl class, not touching any bloc, use case, or domain
  entity at all.
