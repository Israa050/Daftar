import 'package:drift/drift.dart';
import 'package:stockflow/core/database/default_categories.dart';
import 'package:stockflow/core/sync/data/daos/sync_dao.dart';
import 'package:stockflow/core/sync/data/models/sync_meta.dart';
import 'package:stockflow/core/sync/data/models/sync_queue_entries.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/features/categories/data/daos/categories_dao.dart';
import 'package:stockflow/features/categories/data/models/categories.dart';
import 'package:stockflow/features/transactions/data/daos/transactions_dao.dart';
import 'package:stockflow/features/transactions/data/models/transactions.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';

part 'app_database.g.dart';

/// The app's single Drift database. Queries live in the DAOs
/// ([TransactionsDao], [CategoriesDao], [SyncDao]); this class only declares
/// the schema, the migrations, and the default seed.
@DriftDatabase(
  tables: [Transactions, Categories, SyncQueueEntries, SyncMeta],
  daos: [TransactionsDao, CategoriesDao, SyncDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await batch((b) => b.insertAll(categories, defaultCategories));
    },
    onUpgrade: _upgrade,
    beforeOpen: (details) async {
      // SQLite defaults foreign keys OFF per connection; transactions.
      // category_id has an FK to categories, so it must be turned on here.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _upgrade(Migrator m, int from, int to) async {
    if (from < 2) await _v2AddCategories(m);
    if (from < 3) await _v3RebuildTransactions(m);
    if (from < 4) await _v4AddSyncQueue(m);
    if (from < 5) await _v5AddUpdatedAt(m);
    if (from < 6) await _v6AddSyncMeta(m);
  }

  /// v2: categories arrive; transactions gain a nullable categoryId.
  Future<void> _v2AddCategories(Migrator m) async {
    await m.createTable(categories);
    await m.addColumn(transactions, transactions.categoryId);
  }

  /// v3: rebuild transactions to pick up the FK on categoryId.
  Future<void> _v3RebuildTransactions(Migrator m) {
    return m.alterTable(TableMigration(transactions));
  }

  /// v4: the offline sync queue.
  Future<void> _v4AddSyncQueue(Migrator m) => m.createTable(syncQueueEntries);

  /// v5: updatedAt on both synced tables, for last-write-wins conflicts.
  Future<void> _v5AddUpdatedAt(Migrator m) async {
    await m.addColumn(transactions, transactions.updatedAt);
    await m.addColumn(categories, categories.updatedAt);
  }

  /// v6: sync_meta, for the last-pull-at watermark.
  Future<void> _v6AddSyncMeta(Migrator m) => m.createTable(syncMeta);
}
