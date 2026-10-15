import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/datasources/supabase_sync_data_source.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';

import 'package:stockflow/features/transactions/data/transactions_data_source.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';

import '../helpers/mocks.dart';

void main() {
  late TransactionsDataSource transactionsDataSource;
  late SupabaseSyncDataSource supabaseSyncDataSource;
  late SyncRepositoryImpl syncRepositoryImpl;
  late SyncQueueRepositoryImpl syncQueueRepository;

  setUp(() {
    transactionsDataSource = TransactionsDataSource(NativeDatabase.memory());
    supabaseSyncDataSource = MockSupabaseDataSource();
    syncQueueRepository = SyncQueueRepositoryImpl(
      dataSource: transactionsDataSource,
    );
    syncRepositoryImpl = SyncRepositoryImpl(
      syncQueueRepository: syncQueueRepository,
      supabaseSyncDataSource: supabaseSyncDataSource,
      dataSource: transactionsDataSource,
    );
  });

  setUpAll(() {
    registerFallbackValue(DateTime.utc(1970));
  });

  tearDown(() async {
    await transactionsDataSource.close();
  });

  final updatedAt = DateTime.utc(2026, 1, 1, 12).toIso8601String();

  final categoryRow = <String, dynamic>{
    'id': 'cat-remote',
    'name': 'Remote category',
    'color_hex': '#FF0000',
    'updated_at': updatedAt,
  };

  // category_id points at the category above, which is not in the local DB
  // yet -- that missing parent is what triggers the FK failure.
  final transactionRow = <String, dynamic>{
    'id': 'txn-1',
    'amount_minor': 500,
    'type': 'expense',
    'note': 'from another device',
    'category_id': 'cat-remote',
    'occurred_at': updatedAt,
    'created_at': updatedAt,
    'updated_at': updatedAt,
  };

  test('fresh device: a transaction whose category is not local yet '
      'is applied in the same pull', () async {
    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'category',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => [categoryRow]);

    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'transaction',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => [transactionRow]);

    final result = await syncRepositoryImpl.pullRemoteChanges();

    expect((result as Success<int>).data, 2);
    expect(
      await transactionsDataSource.findCategoryById('cat-remote'),
      isNotNull,
    );

    final txn = await transactionsDataSource.findTransactionById('txn-1');
    expect(txn, isNotNull);
    expect(txn!.categoryId, 'cat-remote');
  });

  // A local transaction already exists at [sameInstant]; the remote has a
  // different version of the same row at [remoteUpdatedAt].
  final sameInstant = DateTime.utc(2026, 1, 1, 12);

  Future<Result<int>> pullRemoteVersionAt(DateTime remoteUpdatedAt) async {
    await transactionsDataSource.upsertTransaction(
      TransactionsCompanion.insert(
        id: 'txn-1',
        amountMinor: 500,
        type: TransactionType.expense,
        note: const Value('local edit'),
        updatedAt: Value(sameInstant),
      ),
    );

    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'category',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'transaction',
        since: any(named: 'since'),
      ),
    ).thenAnswer(
      (_) async => [
        {
          ...transactionRow,
          'note': 'remote version',
          'category_id': null,
          'updated_at': remoteUpdatedAt.toIso8601String(),
        },
      ],
    );

    return syncRepositoryImpl.pullRemoteChanges();
  }

  Future<Result<int>> pullRemoteCategoryAt(DateTime remoteUpdatedAt) async {
    await transactionsDataSource.upsertCategory(
      CategoriesCompanion.insert(
        id: 'cat-1',
        name: 'Local Name',
        updatedAt: Value(sameInstant),
      ),
    );

    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'category',
        since: any(named: 'since'),
      ),
    ).thenAnswer(
      (_) async => [
        {
          ...categoryRow,
          'id': 'cat-1',
          'name': 'Remote Name',
          'color_hex': '#FF0000',
          'updated_at': remoteUpdatedAt.toIso8601String(),
        },
      ],
    );

    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'transaction',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => []);

    return syncRepositoryImpl.pullRemoteChanges();
  }

  test('remote row with the same updated_at as the local row is not applied '
      '(tie keeps local)', () async {
    final result = await pullRemoteVersionAt(sameInstant);

    expect((result as Success<int>).data, 0);
    final txn = await transactionsDataSource.findTransactionById('txn-1');
    expect(txn!.note, 'local edit');
  });

  test('remote row that is newer than the local row is applied', () async {
    final remoteTime = sameInstant.add(const Duration(seconds: 5));
    final result = await pullRemoteVersionAt(remoteTime);

    expect((result as Success<int>).data, 1);
    final txn = await transactionsDataSource.findTransactionById('txn-1');
    expect(txn!.note, 'remote version');
    expect(txn.updatedAt.toUtc(), remoteTime);
  });

  test('remote row older than the local row is not applied '
      '(newer local edit wins)', () async {
    final result = await pullRemoteVersionAt(
      sameInstant.subtract(const Duration(seconds: 5)),
    );

    expect((result as Success<int>).data, 0);
    final txn = await transactionsDataSource.findTransactionById('txn-1');
    expect(txn!.note, 'local edit');
  });

  test('a pull applies remote rows without enqueueing anything '
      '(no push/pull loop)', () async {
    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'category',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => [categoryRow]);
    when(
      () => supabaseSyncDataSource.pullChanges(
        entityType: 'transaction',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => [transactionRow]);

    final result = await syncRepositoryImpl.pullRemoteChanges();

    expect((result as Success<int>).data, 2);
    final entries = await transactionsDataSource.getAllSyncQueueEntries();
    expect(
      entries,
      isEmpty,
      reason:
          'a pull-applied write must bypass the sync queue, or push and pull '
          'loop forever',
    );
  });

  test(
    'category: remote row older than the local row is not applied (newer local edit wins)',
    () async {
      final result = await pullRemoteCategoryAt(
        sameInstant.subtract(const Duration(seconds: 5)),
      );
      expect((result as Success<int>).data, 0);
      final cat = await transactionsDataSource.findCategoryById('cat-1');
      expect(cat!.name, 'Local Name');
    },
  );

  test('category: remote row newer than the local row is applied '
      '(newer remote edit wins)', () async {
    final remoteTime = sameInstant.add(const Duration(seconds: 5));
    final result = await pullRemoteCategoryAt(remoteTime);
    expect((result as Success<int>).data, 1);
    final cat = await transactionsDataSource.findCategoryById('cat-1');
    expect(cat!.name, 'Remote Name');
    expect(cat.updatedAt.toUtc(), remoteTime);
  });

  test('category: remote row with the same updated_at as the local row is not '
      'applied (tie keeps local)', () async {
    final result = await pullRemoteCategoryAt(sameInstant);
    expect((result as Success<int>).data, 0);
    final cat = await transactionsDataSource.findCategoryById('cat-1');
    expect(cat!.name, 'Local Name');
  });

  test(
    'a failed category pull does not advance its watermark; the transaction pull still applies',
    () async {
      when(
        () => supabaseSyncDataSource.pullChanges(
          entityType: 'category',
          since: any(named: 'since'),
        ),
      ).thenThrow(Exception('boom'));

      when(
        () => supabaseSyncDataSource.pullChanges(
          entityType: 'transaction',
          since: any(named: 'since'),
        ),
      ).thenAnswer(
        (_) async => [
          {...transactionRow, 'category_id': null},
        ],
      );

      final result = await syncRepositoryImpl.pullRemoteChanges();

      expect((result as Success<int>).data, 1);
      expect(
        await transactionsDataSource.getSyncMeta('lastPulledAt:category'),
        isNull,
      );
      expect(
        await transactionsDataSource.getSyncMeta('lastPulledAt:transaction'),
        isNotNull,
      );
    },
  );

  test(
    'the watermark is saved after a pull and passed as since on the next pull',
    () async {
      when(
        () => supabaseSyncDataSource.pullChanges(
          entityType: 'category',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => []);

      when(
        () => supabaseSyncDataSource.pullChanges(
          entityType: 'transaction',
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => []);

      await syncRepositoryImpl.pullRemoteChanges();

      expect(
        await transactionsDataSource.getSyncMeta('lastPulledAt:category'),
        isNotNull,
      );
      expect(
        await transactionsDataSource.getSyncMeta('lastPulledAt:transaction'),
        isNotNull,
      );

      // Read it now: the second pull below overwrites it with a newer one,
      // and what the second pull *asks for* is this first value.
      final savedByFirstPull = await transactionsDataSource.getSyncMeta(
        'lastPulledAt:category',
      );

      await syncRepositoryImpl.pullRemoteChanges();

      final captured = verify(
        () => supabaseSyncDataSource.pullChanges(
          entityType: 'category',
          since: captureAny(named: 'since'),
        ),
      ).captured;

      expect(captured[0], DateTime.utc(1970));
      // Same instant, compared as UTC: Drift hands back local time.
      expect((captured[1] as DateTime).toUtc(), savedByFirstPull!.toUtc());
    },
  );

  test('pulling the same remote row twice applies it only once', () async {
    final remoteTime = sameInstant.add(const Duration(seconds: 5));

    final first = await pullRemoteVersionAt(remoteTime);
    expect((first as Success<int>).data, 1);

    // The helper's stubs still return the same remote row. Its updated_at now
    // equals the local row's (the applied row carries the remote updatedAt),
    // so it is a tie and nothing is applied.
    final second = await syncRepositoryImpl.pullRemoteChanges();
    expect((second as Success<int>).data, 0);

    final txn = await transactionsDataSource.findTransactionById('txn-1');
    expect(txn!.note, 'remote version');
    expect(txn.updatedAt.toUtc(), remoteTime);
  });
}
