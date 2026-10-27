import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/service_locator.dart';
import 'package:stockflow/core/sync/data/datasources/sync_remote_data_source.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';
import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_repository.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';

class _InMemoryRemote implements SyncRemoteDataSource {
  final pushed = <SyncQueueEntryEntity>[];

  @override
  Future<void> pushEntry(SyncQueueEntryEntity entry) async => pushed.add(entry);

  @override
  Future<List<Map<String, dynamic>>> pullChanges({
    required String entityType,
    required DateTime since,
  }) async => [];
}

void main() {
  tearDown(() async {
    await getIt<TransactionsDataSource>().close();
    await getIt.reset();
  });

  test('the database and the sync remote can be swapped for fakes', () {
    // Supabase.initialize() is never called here. If anything resolved the
    // real Supabase remote, this test would throw.
    setupServiceLocator(database: NativeDatabase.memory());
    final remote = _InMemoryRemote();
    getIt.unregister<SyncRemoteDataSource>();
    getIt.registerLazySingleton<SyncRemoteDataSource>(() => remote);

    final repository = getIt<SyncRepository>();

    expect(repository, isA<SyncRepositoryImpl>());
    expect((repository as SyncRepositoryImpl).remoteDataSource, same(remote));
  });
}
