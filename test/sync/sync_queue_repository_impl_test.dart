import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';

void main() {
  late AppDatabase db;
  late SyncQueueRepositoryImpl repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = SyncQueueRepositoryImpl(syncDao: db.syncDao);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Result<int>> enqueueOne({
    String entityType = 'transaction',
    String entityId = 'txn-1',
    OperationType operation = OperationType.create,
    String payload = '{}',
  }) {
    return repository.enqueue(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
  }

  Future<List<SyncQueueEntry>> queueRows() => db.syncDao.getAllQueued();

  group('enqueue', () {
    test(
      'valid entry -> Success<int>, and exactly one row exists after',
      () async {
        final result = await enqueueOne();

        expect(result, isA<Success<int>>());
        expect((await queueRows()).length, 1);
      },
    );

    test(
      'entityType / entityId / payload are stored verbatim, untransformed',
      () async {
        await enqueueOne(
          entityType: 'category',
          entityId: 'cat-42',
          payload: '{"id":"cat-42","name":"Food"}',
        );

        final row = (await queueRows()).single;
        expect(row.entityType, 'category');
        expect(row.entityId, 'cat-42');
        expect(row.payload, '{"id":"cat-42","name":"Food"}');
      },
    );

    for (final operation in OperationType.values) {
      test('operation ${operation.name} round-trips as the enum', () async {
        await enqueueOne(operation: operation);

        expect((await queueRows()).single.operation, operation);
      });
    }

    test('id is generated internally -- caller never supplies one', () async {
      await enqueueOne();

      final row = (await queueRows()).single;
      expect(row.id, isNotEmpty);
    });

    test('two enqueue calls -> two rows with distinct ids', () async {
      await enqueueOne();
      await enqueueOne();

      final rows = await queueRows();
      expect(rows.length, 2);
      expect(rows[0].id, isNot(rows[1].id));
    });

    test('createdAt is auto-populated to roughly now', () async {
      final before = DateTime.now();
      await enqueueOne();
      final after = DateTime.now();

      final createdAt = (await queueRows()).single.createdAt;
      expect(
        createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(createdAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('payload is stored as an opaque string, byte-identical', () async {
      const payload = '{"z":1,"a":[true,null,"x"],"nested":{"k":"v"}}';
      await enqueueOne(payload: payload);

      expect((await queueRows()).single.payload, payload);
    });

    // Not tested here: forcing dataSource to throw so enqueue returns
    // Failure. Same caveat as transactions_repository_test.dart -- closing
    // the connection on NativeDatabase.memory() hangs the next query rather
    // than throwing, so the catch/Failure branch can't be reliably driven.
  });

  group('watchPendingCount', () {
    test('empty queue -> emits 0', () async {
      expect(await repository.watchPendingCount().first, 0);
    });

    test('after N enqueues -> emits N', () async {
      await enqueueOne(entityId: 'a');
      await enqueueOne(entityId: 'b');
      await enqueueOne(entityId: 'c');

      expect(await repository.watchPendingCount().first, 3);
    });

    test(
      'is reactive -- re-emits when a row is added after subscribing',
      () async {
        expectLater(repository.watchPendingCount(), emitsInOrder([0, 1]));
        await Future<void>.delayed(Duration.zero);
        await enqueueOne();
      },
    );

    test(
      'counts rows regardless of operation type (no status filter)',
      () async {
        await enqueueOne(entityId: 'a', operation: OperationType.create);
        await enqueueOne(entityId: 'b', operation: OperationType.delete);

        expect(await repository.watchPendingCount().first, 2);
      },
    );
  });
}
