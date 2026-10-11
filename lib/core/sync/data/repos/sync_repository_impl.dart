import 'package:drift/drift.dart';
import 'package:logger/logger.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/datasources/supabase_sync_data_source.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_repository.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';

final _logger = Logger(printer: PrettyPrinter(methodCount: 0));

class SyncRepositoryImpl implements SyncRepository {
  SyncRepositoryImpl({
    required this.syncQueueRepository,
    required this.supabaseSyncDataSource,
    required this.dataSource,
  });

  final SyncQueueRepository syncQueueRepository;
  final SupabaseSyncDataSource supabaseSyncDataSource;
  final TransactionsDataSource dataSource;

  // Categories first: transactions.category_id has an FK to categories.
  static const _entityTypes = ['category', 'transaction'];

  String _watermarkKey(String entityType) => 'lastPulledAt:$entityType';

  @override
  Future<Result<int>> pushPending() async {
    final pending = await syncQueueRepository.getPending();
    if (pending case Failure(:final message)) {
      return Failure(message);
    }

    final entries = (pending as Success).data;
    var succeeded = 0;

    for (final entry in entries) {
      try {
        await supabaseSyncDataSource.pushEntry(entry);
      } catch (e, st) {
        // Push failed -- leave this entry queued and move on. No
        // error/retry bookkeeping; it's simply retried next pushPending().
        // Logged (not swallowed) so a persistent failure stays visible.
        //
        // .toString() not .name: a reproduced Dart/mocktail edge case makes
        // .name throw NoSuchMethodError in this exact catch-after-loop
        // shape. .toString() gives "OperationType.create" instead of
        // "create" -- same info, just qualified.
        _logger.w(
          'Sync push failed for ${entry.entityType}/${entry.id} '
          '(${entry.operation.toString()}): $e',
          error: e,
          stackTrace: st,
        );
        continue;
      }

      final dequeued = await syncQueueRepository.dequeue(entry.id);
      if (dequeued is Success) {
        succeeded++;
      }
      // If dequeue itself fails, the entry stays in the queue and the push
      // will just happen again next time -- harmless since pushEntry is
      // idempotent. Not counted as succeeded since it hasn't actually left
      // the queue yet.
    }

    return Success(succeeded);
  }

  @override
  Future<Result<int>> pullRemoteChanges() async {
    var applied = 0;

    for (final entityType in _entityTypes) {
      try {
        applied += await _pullEntityType(entityType);
      } catch (e, st) {
        // Same independence as pushPending: one entity type's pull failing
        // (network, RLS, bad data) must not block the other's, and is
        // simply retried next time since the watermark for this type was
        // not advanced.
        _logger.w(
          'Sync pull failed for $entityType: $e',
          error: e,
          stackTrace: st,
        );
      }
    }

    return Success(applied);
  }

  Future<int> _pullEntityType(String entityType) async {
    final key = _watermarkKey(entityType);
    final lastPulledAt =
        await dataSource.getSyncMeta(key) ?? DateTime.utc(1970);
    // Captured before querying, not after applying, so a row that changes
    // remotely while this pull is in flight is picked up again next time
    // instead of being skipped.
    final pullStartedAt = DateTime.now().toUtc();

    final rows = await supabaseSyncDataSource.pullChanges(
      entityType: entityType,
      since: lastPulledAt,
    );

    var applied = 0;
    for (final row in rows) {
      final wasApplied = switch (entityType) {
        'transaction' => await _applyTransaction(row),
        'category' => await _applyCategory(row),
        _ => false,
      };
      if (wasApplied) applied++;
    }

    await dataSource.setSyncMeta(key, pullStartedAt);
    return applied;
  }

  /// Applies one remote transaction row if it's newer than the local copy
  /// (or there is no local copy yet). Returns whether it was applied.
  Future<bool> _applyTransaction(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdatedAt = DateTime.parse(row['updated_at'] as String);

    final local = await dataSource.findTransactionById(id);
    if (local != null && !remoteUpdatedAt.isAfter(local.updatedAt)) {
      return false;
    }

    await dataSource.upsertTransaction(
      TransactionsCompanion.insert(
        id: id,
        amountMinor: row['amount_minor'] as int,
        type: TransactionType.values.byName(row['type'] as String),
        note: Value(row['note'] as String?),
        categoryId: Value(row['category_id'] as String?),
        occurredTime: Value(DateTime.parse(row['occurred_at'] as String)),
        creationTime: Value(DateTime.parse(row['created_at'] as String)),
        updatedAt: Value(remoteUpdatedAt),
      ),
    );
    return true;
  }

  /// Applies one remote category row if it's newer than the local copy (or
  /// there is no local copy yet). Returns whether it was applied.
  Future<bool> _applyCategory(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdatedAt = DateTime.parse(row['updated_at'] as String);

    final local = await dataSource.findCategoryById(id);
    if (local != null && !remoteUpdatedAt.isAfter(local.updatedAt)) {
      return false;
    }

    await dataSource.upsertCategory(
      CategoriesCompanion.insert(
        id: id,
        name: row['name'] as String,
        colorHex: Value(row['color_hex'] as String?),
        updatedAt: Value(remoteUpdatedAt),
      ),
    );
    return true;
  }
}
