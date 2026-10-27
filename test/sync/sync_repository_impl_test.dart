import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/datasources/supabase_sync_data_source.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';

import '../helpers/mocks.dart';

class _FakeSyncQueueEntryEntity extends Fake implements SyncQueueEntryEntity {}

void main() {
  late SyncQueueRepository syncQueueRepository;
  late SyncRepositoryImpl repository;
  late SupabaseSyncDataSource dataSource;
  late MockTransactionsDataSource transactionsDataSource;

  final myEntry = SyncQueueEntryEntity(
    id: 'q1',
    entityType: 'transaction',
    entityId: 'txn-1',
    operation: OperationType.create,
    payload: '{}',
    createdAt: DateTime(2026),
  );

  setUpAll(() {
    registerFallbackValue(_FakeSyncQueueEntryEntity());
    registerFallbackValue(OperationType.create);
  });

  setUp(() {
    syncQueueRepository = MockSyncQueueRepository();
    dataSource = MockSupabaseDataSource();
    transactionsDataSource = MockTransactionsDataSource();
    repository = SyncRepositoryImpl(
      syncQueueRepository: syncQueueRepository,
      remoteDataSource: dataSource,
      dataSource: transactionsDataSource,
    );
  });

  test('getPending() returns Failure -> pushPending() returns that Failure '
      'immediately, no entries are pushed', () async {
    when(
      () => syncQueueRepository.getPending(),
    ).thenAnswer((_) async => const Failure('db read error'));

    final result = await repository.pushPending();

    expect(result, isA<Failure>());
    expect((result as Failure).message, 'db read error');
    verifyNever(() => dataSource.pushEntry(any()));
  });

  test(
    'empty queue -> Success(0), pushEntry and dequeue never called',
    () async {
      when(
        () => syncQueueRepository.getPending(),
      ).thenAnswer((_) async => Success([]));

      final result = await repository.pushPending();

      expect(result, isA<Success>());
      expect((result as Success).data, 0);
      verifyNever(() => dataSource.pushEntry(any()));
      verifyNever(() => syncQueueRepository.dequeue(any()));
    },
  );

  test(
    'one entry, push and dequeue both succeed -> Success(1), '
    'pushEntry and dequeue each called once with the right arguments',
    () async {
      when(
        () => syncQueueRepository.getPending(),
      ).thenAnswer((_) async => Success([myEntry]));

      when(() => dataSource.pushEntry(myEntry)).thenAnswer((_) async {});

      when(
        () => syncQueueRepository.dequeue(myEntry.id),
      ).thenAnswer((_) async => const Success(null));

      final result = await repository.pushPending();

      expect(result, isA<Success<int>>());
      expect((result as Success).data, 1);

      verify(() => dataSource.pushEntry(myEntry)).called(1);
      verify(() => syncQueueRepository.dequeue(myEntry.id)).called(1);
    },
  );

  test(
    'pushEntry() throws -> entry is left queued, not dequeued, not counted',
    () async {
      when(
        () => syncQueueRepository.getPending(),
      ).thenAnswer((_) async => Success([myEntry]));

      when(
        () => dataSource.pushEntry(myEntry),
      ).thenThrow(Exception('network error'));

      final result = await repository.pushPending();

      expect(result, isA<Success<int>>());
      expect((result as Success).data, 0);

      verify(() => dataSource.pushEntry(myEntry)).called(1);
      verifyNever(() => syncQueueRepository.dequeue(myEntry.id));
    },
  );

  test('push succeeds but dequeue() fails -> not counted as succeeded '
      '(the row has not actually left the queue)', () async {
    when(
      () => syncQueueRepository.getPending(),
    ).thenAnswer((_) async => Success([myEntry]));

    when(() => dataSource.pushEntry(myEntry)).thenAnswer((_) async {});

    when(
      () => syncQueueRepository.dequeue(myEntry.id),
    ).thenAnswer((_) async => const Failure('Dequeue Failure'));

    final result = await repository.pushPending();

    expect(result, isA<Success<int>>());
    expect((result as Success).data, 0);

    verify(() => dataSource.pushEntry(myEntry)).called(1);
    verify(() => syncQueueRepository.dequeue(myEntry.id)).called(1);
  });

  test('one entry fails, the rest still get attempted independently '
      '(a single failure does not stop the pass)', () async {
    final okBefore = SyncQueueEntryEntity(
      id: 'q0',
      entityType: 'transaction',
      entityId: 'txn-0',
      operation: OperationType.create,
      payload: '{}',
      createdAt: DateTime(2026),
    );
    final failing = SyncQueueEntryEntity(
      id: 'q1',
      entityType: 'transaction',
      entityId: 'txn-1',
      operation: OperationType.create,
      payload: '{}',
      createdAt: DateTime(2026),
    );
    final okAfter = SyncQueueEntryEntity(
      id: 'q2',
      entityType: 'transaction',
      entityId: 'txn-2',
      operation: OperationType.create,
      payload: '{}',
      createdAt: DateTime(2026),
    );

    when(
      () => syncQueueRepository.getPending(),
    ).thenAnswer((_) async => Success([okBefore, failing, okAfter]));

    when(() => dataSource.pushEntry(okBefore)).thenAnswer((_) async {});
    when(
      () => dataSource.pushEntry(failing),
    ).thenThrow(Exception('server rejected this row'));
    when(() => dataSource.pushEntry(okAfter)).thenAnswer((_) async {});

    when(
      () => syncQueueRepository.dequeue(any()),
    ).thenAnswer((_) async => const Success(null));

    final result = await repository.pushPending();

    expect(result, isA<Success<int>>());
    expect((result as Success).data, 2);

    // All three were attempted -- the failing one didn't stop the loop.
    verify(() => dataSource.pushEntry(okBefore)).called(1);
    verify(() => dataSource.pushEntry(failing)).called(1);
    verify(() => dataSource.pushEntry(okAfter)).called(1);

    // Only the two that actually succeeded get dequeued.
    verify(() => syncQueueRepository.dequeue(okBefore.id)).called(1);
    verify(() => syncQueueRepository.dequeue(okAfter.id)).called(1);
    verifyNever(() => syncQueueRepository.dequeue(failing.id));
  });

  test(
    'multiple entries all succeed -> Success(N), each dequeued once',
    () async {
      final entries = [
        SyncQueueEntryEntity(
          id: 'q1',
          entityType: 'transaction',
          entityId: 'txn-1',
          operation: OperationType.create,
          payload: '{}',
          createdAt: DateTime(2026),
        ),
        SyncQueueEntryEntity(
          id: 'q2',
          entityType: 'transaction',
          entityId: 'txn-2',
          operation: OperationType.update,
          payload: '{}',
          createdAt: DateTime(2026),
        ),
        SyncQueueEntryEntity(
          id: 'q3',
          entityType: 'category',
          entityId: 'cat-1',
          operation: OperationType.delete,
          payload: '{}',
          createdAt: DateTime(2026),
        ),
      ];

      when(
        () => syncQueueRepository.getPending(),
      ).thenAnswer((_) async => Success(entries));
      when(() => dataSource.pushEntry(any())).thenAnswer((_) async {});
      when(
        () => syncQueueRepository.dequeue(any()),
      ).thenAnswer((_) async => const Success(null));

      final result = await repository.pushPending();

      expect(result, isA<Success<int>>());
      expect((result as Success).data, 3);

      for (final e in entries) {
        verify(() => dataSource.pushEntry(e)).called(1);
        verify(() => syncQueueRepository.dequeue(e.id)).called(1);
      }
    },
  );
}
