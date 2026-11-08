# Export data (manual backup)

An app-bar action (`ExportAction`, next to "Manage categories" on
`TransactionsScreen`) serializes every transaction and category into one
JSON file and hands it to the OS share sheet via `share_plus`. Extracted from
the README to keep that file short for a first-time visitor.

This is **not** the sync queue — the outbox replays individual writes to the
server; export is a user-triggered, point-in-time snapshot of current state,
read fresh from the database and independent of whatever is sitting unsynced
in `SyncQueueEntries`. For a user without a durable account yet, this is the
only real backup path available today.

## Decisions

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
  can move earlier (e.g. Drift's `computeWithDatabase`) without changing
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
  [`technical-decisions.md`](technical-decisions.md)): JSON has no native
  date type, so `DateTime` must become a string at the export boundary, and
  UTC keeps it unambiguous across devices/timezones. Emitting a decimal
  amount instead of minor units would reintroduce exactly the floating-point
  drift the schema was designed to avoid.
- **The file is written to the OS temp directory, not app documents.**
  `getTemporaryDirectory()` (via `path_provider`, already a dependency),
  because the file is a transient hand-off to the share sheet — not app
  state Daftar owns or needs to keep around after the user has saved it
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

## Not yet built

- Import / restore. The envelope's `formatVersion` and category-first field
  ordering are designed to make this possible later, but no reader exists yet.
- CSV export.
- Scheduled / automatic backups.
- Encryption — the exported file is plaintext financial data, which is worth
  knowing before sharing it through the OS share sheet.
