import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/datasources/supabase_sync_data_source.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';

import 'package:stockflow/features/transactions/data/transactions_data_source.dart';

import '../helpers/mocks.dart';

void main() {
  late TransactionsDataSource transactionsDataSource;
  late SupabaseSyncDataSource supabaseSyncDataSource;
  late SyncRepositoryImpl syncRepositoryImpl;

  setUp(() {
    transactionsDataSource = TransactionsDataSource(NativeDatabase.memory());
    supabaseSyncDataSource = MockSupabaseDataSource();
    MockSyncQueueRepository mockSyncQueueRepository = MockSyncQueueRepository();
    syncRepositoryImpl = SyncRepositoryImpl(
      syncQueueRepository: mockSyncQueueRepository,
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
}
