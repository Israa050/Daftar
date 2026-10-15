import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/features/categories/data/repos/category_repository_impl.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';

import '../helpers/mocks.dart';

// End-to-end conflict through the REAL local stack: a category is edited
// locally through CategoryRepositoryImpl (so the edit is also queued for push)
// while the same category was edited on another device (the mocked remote).
// The pull then decides which version the local database keeps.
//
// Scope: this proves the PULL resolves a conflict by last-write-wins in the
// local DB. It does NOT prove the whole sync does. pushEntry() upserts with no
// timestamp check and SyncDataUseCase pushes before it pulls, so a stale
// queued edit can still overwrite a newer remote edit on the server.
//
// Remote times are always built from the local edit's own updatedAt, never
// from the clock: timestamps are whole seconds, and the local add and edit
// happen within the same second.
void main() {
  late TransactionsDataSource dataSource;
  late SyncQueueRepositoryImpl syncQueueRepository;
  late CategoryRepositoryImpl categoryRepository;
  late MockSupabaseDataSource remote;
  late SyncRepositoryImpl syncRepository;

  // Set up by the offline local edit in setUp.
  late String categoryId;
  late DateTime localEditTime;

  setUpAll(() {
    registerFallbackValue(DateTime.utc(1970));
  });

  setUp(() async {
    dataSource = TransactionsDataSource(NativeDatabase.memory());
    syncQueueRepository = SyncQueueRepositoryImpl(dataSource: dataSource);
    categoryRepository = CategoryRepositoryImpl(
      dataSource: dataSource,
      syncQueueRepository: syncQueueRepository,
    );
    remote = MockSupabaseDataSource();
    syncRepository = SyncRepositoryImpl(
      syncQueueRepository: syncQueueRepository,
      supabaseSyncDataSource: remote,
      dataSource: dataSource,
    );

    // The offline local edit: add, then rename. Both writes are queued.
    await categoryRepository.addCategory(name: 'Groceries');
    categoryId = (await categoryRepository.getCategoryByName('Groceries'))!.id;
    await categoryRepository.updateCategory(id: categoryId, name: 'Local Edit');

    final row = (await dataSource.getAllCategoriesOnce()).singleWhere(
      (c) => c.id == categoryId,
    );
    localEditTime = row.updatedAt.toUtc();
  });

  tearDown(() async {
    await dataSource.close();
  });

  /// The other device edited the same category at [remoteUpdatedAt].
  Future<Result<int>> pullRemoteEditAt(DateTime remoteUpdatedAt) {
    when(
      () => remote.pullChanges(
        entityType: 'category',
        since: any(named: 'since'),
      ),
    ).thenAnswer(
      (_) async => [
        {
          'id': categoryId,
          'name': 'Remote Edit',
          'color_hex': '#00FF00',
          'updated_at': remoteUpdatedAt.toIso8601String(),
        },
      ],
    );
    when(
      () => remote.pullChanges(
        entityType: 'transaction',
        since: any(named: 'since'),
      ),
    ).thenAnswer((_) async => []);

    return syncRepository.pullRemoteChanges();
  }

  /// The queued update for the local edit, if it is still pending.
  Future<bool> localEditStillQueued() async {
    final entries = await dataSource.getAllSyncQueueEntries();
    return entries.any(
      (e) => e.entityId == categoryId && e.operation == OperationType.update,
    );
  }

  /// The category as stored locally. Read by id (not by name) so a wrong
  /// winner fails with the actual name instead of a null crash.
  Future<Category> storedCategory() async {
    final row = await dataSource.findCategoryById(categoryId);
    return row!;
  }

  // Functions, not values: localEditTime is only known once setUp has run.
  DateTime later() => localEditTime.add(const Duration(seconds: 5));
  DateTime earlier() => localEditTime.subtract(const Duration(seconds: 5));

  test('pull: a later remote edit overwrites the earlier local edit', () async {
    final result = await pullRemoteEditAt(later());

    expect((result as Success<int>).data, 1);
    final stored = await storedCategory();
    expect(stored.name, 'Remote Edit');
    expect(stored.colorHex, '#00FF00', reason: 'the whole row is replaced');
    expect(stored.updatedAt.toUtc(), later());
  });

  test(
    'pull: an earlier remote edit does not overwrite the later local edit',
    () async {
      final result = await pullRemoteEditAt(earlier());

      expect((result as Success<int>).data, 0);
      final stored = await storedCategory();
      expect(stored.name, 'Local Edit');
      expect(stored.updatedAt.toUtc(), localEditTime);
    },
  );

  test(
    'pull: a remote edit at the same instant as the local edit keeps local',
    () async {
      final result = await pullRemoteEditAt(localEditTime);

      expect((result as Success<int>).data, 0);
      expect((await storedCategory()).name, 'Local Edit');
    },
  );

  test(
    'pull: the pending local edit stays queued when the remote wins',
    () async {
      expect(await localEditStillQueued(), isTrue);

      await pullRemoteEditAt(later());

      expect(
        await localEditStillQueued(),
        isTrue,
        reason: 'pull neither creates nor consumes queue entries',
      );
    },
  );

  test('pull: the pending local edit stays queued when local wins', () async {
    expect(await localEditStillQueued(), isTrue);

    await pullRemoteEditAt(earlier());

    expect(await localEditStillQueued(), isTrue);
  });

  test('pull: a second pull of the same remote edit applies nothing', () async {
    final first = await pullRemoteEditAt(later());
    expect((first as Success<int>).data, 1);

    final second = await syncRepository.pullRemoteChanges();

    expect((second as Success<int>).data, 0);
    final stored = await storedCategory();
    expect(stored.name, 'Remote Edit');
    expect(stored.updatedAt.toUtc(), later());
  });

  test(
    'KNOWN GAP: a stale queued edit overwrites a newer remote edit on push',
    () async {
      // Not testable at the pull level. pushEntry() upserts unconditionally
      // and SyncDataUseCase pushes first, so the later remote edit is lost on
      // the server. Left here as a pointer for a follow-up branch.
    },
    skip: 'known gap, see fix/push-respects-last-write-wins',
  );
}
