import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/timestamps.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';
import 'package:stockflow/features/transactions/data/daos/transactions_dao.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:stockflow/features/transactions/domain/repositories/transactions_repository.dart';
import 'package:uuid/uuid.dart';

class TransactionsRepositoryImpl extends TransactionsRepository {
  // [db] is held for transaction() -- the local write and its sync-queue row
  // must commit atomically, which spans this DAO and the sync queue. DAO
  // calls made inside db.transaction(...) join that same transaction.
  final AppDatabase db;
  final TransactionsDao dao;
  final SyncQueueRepository syncQueueRepository;

  TransactionsRepositoryImpl({
    required this.db,
    required this.dao,
    required this.syncQueueRepository,
  });

  TransactionEntity _toEntity(Transaction row) {
    return TransactionEntity(
      id: row.id,
      amountMinor: row.amountMinor,
      type: row.type,
      note: row.note ?? '',
      timestamp: row.occurredTime,
      categoryId: row.categoryId,
    );
  }

  @override
  Stream<List<TransactionEntity>> getAllTransactions() {
    return dao.watchAll().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<TransactionEntity>> getAllTransactionsOnce() async {
    final rows = await dao.getAllOnce();
    return rows.map(_toEntity).toList();
  }

  @override
  Stream<int> watchBalance() {
    return dao.watchBalance();
  }

  @override
  Future<Result<void>> addTransaction({
    required int amountMinor,
    required TransactionType type,
    String? note,
    String? categoryId,
  }) async {
    final id = const Uuid().v4();
    // Set explicitly (rather than relying on Drift's currentDateAndTime
    // default) so the same instant appears in both the local row and the
    // sync payload below, with no follow-up read needed. nowForSync()
    // truncates to whole seconds, which is all Drift stores.
    final now = nowForSync();
    final entry = TransactionsCompanion.insert(
      id: id,
      amountMinor: amountMinor,
      type: type,
      note: Value(note),
      categoryId: Value(categoryId),
      occurredTime: Value(now),
      creationTime: Value(now),
      updatedAt: Value(now),
    );

    final payload = jsonEncode({
      'id': id,
      'amountMinor': amountMinor,
      'type': type.name,
      'note': note,
      'categoryId': categoryId,
      'occurredTime': now.toIso8601String(),
      'creationTime': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    try {
      // The local write and its sync-queue row share one transaction, and the
      // row is enqueued unconditionally -- online or offline. See
      // docs/sync-queue.md for why "always enqueue" is the right call and what
      // is deliberately not built yet.
      await db.transaction(() async {
        await dao.insertOne(entry);
        final queued = await syncQueueRepository.enqueue(
          entityType: 'transaction',
          entityId: id,
          operation: OperationType.create,
          payload: payload,
        );
        // Drift only rolls back a transaction() on a thrown exception, not
        // on a returned Failure -- so a Failure has to be re-thrown here to
        // actually abort the transaction and undo the transaction insert
        // above. Caught below and converted back to Result for the caller.
        if (queued case Failure(:final message)) {
          throw Exception(message);
        }
      });
      return const Success(null);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  @override
  Future<Result<int>> deleteTransaction(String id) async {
    try {
      final result = await db.transaction(() async {
        final count = await dao.deleteById(id);
        final queued = await syncQueueRepository.enqueue(
          entityType: 'transaction',
          entityId: id,
          operation: OperationType.delete,
          payload: jsonEncode({'id': id}),
        );

        // See addTransaction: a Failure must be re-thrown to trigger
        // Drift's rollback, then is converted back to Result below.
        if (queued case Failure(:final message)) {
          throw Exception(message);
        }
        return count;
      });
      return Success(result);
    } catch (e) {
      return Failure(e.toString());
    }
  }
}
