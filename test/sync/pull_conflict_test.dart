import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/datasources/sync_remote_data_source.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';
import 'package:stockflow/core/sync/domain/entities/sync_summary.dart';
import 'package:stockflow/core/sync/domain/usecases/pull_remote_changes_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/push_pending_changes_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/sync_data_usecase.dart';
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

/// In-memory stand-in for the Supabase `categories` table.
///
/// pushEntry follows the same rule as the push_category SQL function: write
/// only if the stored updated_at is not later than the pushed one, and treat a
/// rejected stale write as a normal return (no error), so the client still
/// dequeues it. This fake mirrors that SQL; the SQL itself is proven in the
/// Supabase SQL editor, not here.
class FakeServer extends Fake implements SyncRemoteDataSource {
  /// Rows in the shape the pull reads (snake_case), keyed by id.
  final Map<String, Map<String, dynamic>> categories = {};

  @override
  Future<void> pushEntry(SyncQueueEntryEntity entry) async {
    if (entry.entityType != 'category') return;

    if (entry.operation == OperationType.delete) {
      categories.remove(entry.entityId);
      return;
    }

    final local = jsonDecode(entry.payload) as Map<String, dynamic>;
    final pushedAt = DateTime.parse(local['updatedAt'] as String);
    final stored = categories[entry.entityId];
    if (stored != null &&
        DateTime.parse(stored['updated_at'] as String).isAfter(pushedAt)) {
      return;
    }

    categories[entry.entityId] = {
      'id': entry.entityId,
      'name': local['name'],
      'color_hex': local['colorHex'],
      'updated_at': local['updatedAt'],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> pullChanges({
    required String entityType,
    required DateTime since,
  }) async {
    if (entityType != 'category') return [];

    return categories.values
        .where((r) => DateTime.parse(r['updated_at'] as String).isAfter(since))
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }
}

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
      remoteDataSource: remote,
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

  test('whole sync: a stale queued edit does not overwrite a newer remote edit '
      'on the server, and both sides end on the newer one', () async {
    // The other device already edited the same category, later than the
    // offline edit that is still waiting in the queue.
    final server = FakeServer()
      ..categories[categoryId] = {
        'id': categoryId,
        'name': 'Remote Edit',
        'color_hex': '#00FF00',
        'updated_at': later().toIso8601String(),
      };
    final repo = SyncRepositoryImpl(
      syncQueueRepository: syncQueueRepository,
      remoteDataSource: server,
      dataSource: dataSource,
    );
    final sync = SyncDataUseCase(
      pushPendingChangesUseCase: PushPendingChangesUseCase(repo),
      pullRemoteChangesUseCase: PullRemoteChangesUseCase(repo),
    );

    final result = await sync();

    expect(result, isA<Success<SyncSummary>>());
    expect(
      server.categories[categoryId]!['name'],
      'Remote Edit',
      reason: 'push must not replace a newer server row with a stale edit',
    );
    final stored = await storedCategory();
    expect(stored.name, 'Remote Edit');
    expect(stored.updatedAt.toUtc(), later());
    expect(
      await dataSource.getAllSyncQueueEntries(),
      isEmpty,
      reason: 'a rejected stale write still counts as pushed and is dequeued',
    );
  });
}
