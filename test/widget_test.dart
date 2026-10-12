import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/connectivity/cubit/connectivity_cubit.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/connectivity/domain/usecases/watch_connectivity_usecase.dart';
import 'package:stockflow/core/service_locator.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/cubit/pending_sync_cubit.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/sync/domain/entities/sync_summary.dart';
import 'package:stockflow/core/sync/domain/usecases/sync_data_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/watch_pending_sync_count_usecase.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';
import 'package:stockflow/features/backup/cubit/export_cubit.dart';
import 'package:stockflow/features/backup/data/backup_repository_impl.dart';
import 'package:stockflow/features/backup/domain/backup_repository.dart';
import 'package:stockflow/features/backup/domain/entities/exportable_source.dart';
import 'package:stockflow/features/backup/domain/usecases/export_data_usecase.dart';
import 'package:stockflow/main.dart';
import 'package:stockflow/features/transactions/bloc/balance_cubit.dart';
import 'package:stockflow/features/categories/bloc/category_totals_cubit.dart';
import 'package:stockflow/features/transactions/bloc/transactions_bloc.dart';
import 'package:stockflow/features/categories/data/repos/categories_export_source.dart';
import 'package:stockflow/features/categories/data/repos/category_repository_impl.dart';
import 'package:stockflow/features/transactions/data/repos/transactions_export_source.dart';
import 'package:stockflow/features/transactions/data/repos/transactions_repository_impl.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';
import 'package:stockflow/features/categories/domain/repositories/category_repository.dart';
import 'package:stockflow/features/transactions/domain/repositories/transactions_repository.dart';
import 'package:stockflow/features/transactions/domain/usecases/add_transaction_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/delete_transaction_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/get_transactions_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/watch_balance_usecase.dart';
import 'package:stockflow/features/categories/domain/usecases/watch_categories_usecase.dart';
import 'package:stockflow/features/categories/domain/usecases/watch_category_totals_usecase.dart';
import 'package:stockflow/features/transactions/presentation/screens/transactions_screen.dart';

/// Stub use case that never emits -- keeps [ConnectivityCubit] on its
/// default online state without touching the connectivity_plus plugin.
class _StubWatchConnectivityUseCase implements WatchConnectivityUseCase {
  @override
  Stream<NetworkStatus> call() => const Stream.empty();
}

/// Stub use case that never emits -- keeps [PendingSyncCubit] at 0 without
/// wiring a real queue-count stream.
class _StubWatchPendingSyncCountUseCase
    implements WatchPendingSyncCountUseCase {
  @override
  Stream<int> call() => const Stream.empty();
}

/// Stub use case that never actually syncs anything -- SyncCubit only calls
/// this if connectivity is online, which _StubWatchConnectivityUseCase never
/// reports, but it needs a real implementation to construct.
class _StubSyncDataUseCase implements SyncDataUseCase {
  @override
  Future<Result<SyncSummary>> call() async =>
      const Success(SyncSummary(pushedCount: 0, pulledCount: 0));
}

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    // Registers against an in-memory Drift database instead of
    // setupServiceLocator()'s real disk-backed connection, so this test
    // doesn't touch path_provider/disk I/O and every resource can be
    // closed deterministically in tearDown below.
    final dataSource = TransactionsDataSource(NativeDatabase.memory());
    getIt.registerSingleton<TransactionsDataSource>(dataSource);
    getIt.registerSingleton<ConnectivityCubit>(
      ConnectivityCubit(
        watchConnectivityUseCase: _StubWatchConnectivityUseCase(),
      ),
    );
    getIt.registerSingleton<PendingSyncCubit>(
      PendingSyncCubit(
        watchPendingSyncCount: _StubWatchPendingSyncCountUseCase(),
      ),
    );
    getIt.registerSingleton<SyncCubit>(
      SyncCubit(
        connectivityCubit: getIt<ConnectivityCubit>(),
        pendingSyncCubit: getIt<PendingSyncCubit>(),
        syncDataUseCase: _StubSyncDataUseCase(),
      ),
    );
    getIt.registerSingleton<SyncQueueRepository>(
      SyncQueueRepositoryImpl(dataSource: dataSource),
    );
    getIt.registerSingleton<TransactionsRepository>(
      TransactionsRepositoryImpl(
        dataSource: dataSource,
        syncQueueRepository: getIt<SyncQueueRepository>(),
      ),
    );
    getIt.registerSingleton<CategoryRepository>(
      CategoryRepositoryImpl(
        dataSource: dataSource,
        syncQueueRepository: getIt<SyncQueueRepository>(),
      ),
    );
    getIt.registerSingleton<GetTransactionsUseCase>(
      GetTransactionsUseCase(getIt<TransactionsRepository>()),
    );
    getIt.registerSingleton<WatchCategoriesUseCase>(
      WatchCategoriesUseCase(getIt<CategoryRepository>()),
    );
    getIt.registerSingleton<WatchBalanceUseCase>(
      WatchBalanceUseCase(getIt<TransactionsRepository>()),
    );
    getIt.registerSingleton<WatchCategoryTotalsUsecase>(
      WatchCategoryTotalsUsecase(
        categoryRepository: getIt<CategoryRepository>(),
      ),
    );
    getIt.registerSingleton<AddTransactionUseCase>(
      AddTransactionUseCase(getIt<TransactionsRepository>()),
    );
    getIt.registerSingleton<DeleteTransactionUseCase>(
      DeleteTransactionUseCase(getIt<TransactionsRepository>()),
    );
    getIt.registerFactory<TransactionsBloc>(
      () => TransactionsBloc(
        getTransactionsUseCase: getIt<GetTransactionsUseCase>(),
        addTransactionUseCase: getIt<AddTransactionUseCase>(),
        deleteTransactionUseCase: getIt<DeleteTransactionUseCase>(),
        watchCategoriesUseCase: getIt<WatchCategoriesUseCase>(),
      ),
    );
    getIt.registerFactory<BalanceCubit>(
      () => BalanceCubit(watchBalanceUseCase: getIt<WatchBalanceUseCase>()),
    );
    getIt.registerFactory<CategoryTotalsCubit>(
      () => CategoryTotalsCubit(
        watchCategoryTotals: getIt<WatchCategoryTotalsUsecase>(),
      ),
    );
    getIt.registerSingleton<ExportableSource>(
      TransactionsExportSource(
        transactionsRepository: getIt<TransactionsRepository>(),
      ),
      instanceName: 'transactionsExportSource',
    );
    getIt.registerSingleton<ExportableSource>(
      CategoriesExportSource(categoryRepository: getIt<CategoryRepository>()),
      instanceName: 'categoriesExportSource',
    );
    getIt.registerSingleton<BackupRepository>(
      BackupRepositoryImpl(
        sources: [
          getIt<ExportableSource>(instanceName: 'transactionsExportSource'),
          getIt<ExportableSource>(instanceName: 'categoriesExportSource'),
        ],
      ),
    );
    getIt.registerSingleton<ExportDataUseCase>(
      ExportDataUseCase(getIt<BackupRepository>()),
    );
    getIt.registerFactory<ExportCubit>(
      () => ExportCubit(exportDataUseCase: getIt<ExportDataUseCase>()),
    );

    addTearDown(() async {
      await getIt.reset();
      await dataSource.close();
    });

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(TransactionsScreen), findsOneWidget);

    // Let the bloc's watch() subscription deliver its first Loaded state.
    await tester.pump();

    // Replace the widget tree with an empty one so BlocProvider disposes
    // the TransactionsBloc, which calls _subscription.cancel(). Drift's
    // stream teardown (StreamQueryStore.markAsClosed) schedules its own
    // zero-duration Timer to finish closing the query -- flutter_test runs
    // the whole body inside a fake_async zone, so that timer is virtual and
    // only fires once the fake clock is advanced past it. pump() with an
    // explicit non-zero duration elapses the fake clock and lets it fire;
    // a bare pump() (zero elapsed time) does not.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
