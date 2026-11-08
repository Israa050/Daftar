import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/core/sync/data/daos/sync_dao.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';
import 'package:uuid/uuid.dart';

class SyncQueueRepositoryImpl extends SyncQueueRepository {
  final SyncDao syncDao;

  SyncQueueRepositoryImpl({required this.syncDao});

  SyncQueueEntryEntity _toEntity(SyncQueueEntry entry) {
    return SyncQueueEntryEntity(
      id: entry.id,
      entityType: entry.entityType,
      entityId: entry.entityId,
      operation: entry.operation,
      payload: entry.payload,
      createdAt: entry.createdAt,
    );
  }

  @override
  Future<Result<int>> enqueue({
    required String entityType,
    required String entityId,
    required OperationType operation,
    required String payload,
  }) async {
    final entry = SyncQueueEntriesCompanion.insert(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
    try {
      final result = await syncDao.enqueue(entry);
      return Success(result);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  @override
  Stream<int> watchPendingCount() {
    return syncDao.watchPendingCount();
  }

  @override
  Future<Result<void>> dequeue(String id) async {
    try {
      await syncDao.deleteQueued(id);
      return const Success(null);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  @override
  Future<Result<List<SyncQueueEntryEntity>>> getPending() async {
    try {
      final result = await syncDao.getAllQueued();
      return Success(result.map(_toEntity).toList());
    } catch (e) {
      return Failure(e.toString());
    }
  }
}
