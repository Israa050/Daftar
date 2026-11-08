import 'package:drift/drift.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/core/sync/data/models/sync_meta.dart';
import 'package:stockflow/core/sync/data/models/sync_queue_entries.dart';

part 'sync_dao.g.dart';

/// The offline sync queue plus the sync-meta watermarks.
@DriftAccessor(tables: [SyncQueueEntries, SyncMeta])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  Future<int> enqueue(SyncQueueEntriesCompanion entry) {
    return into(syncQueueEntries).insert(entry);
  }

  Future<List<SyncQueueEntry>> getAllQueued() => select(syncQueueEntries).get();

  Future<int> deleteQueued(String id) {
    return (delete(syncQueueEntries)..where((e) => e.id.equals(id))).go();
  }

  Stream<int> watchPendingCount() {
    final count = countAll();
    final query = selectOnly(syncQueueEntries)..addColumns([count]);
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  Future<DateTime?> getMeta(String key) async {
    final row = await (select(
      syncMeta,
    )..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, DateTime value) {
    return into(
      syncMeta,
    ).insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: value));
  }
}
