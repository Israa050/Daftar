import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:stockflow/core/connectivity/cubit/connectivity_cubit.dart';
import 'package:stockflow/core/connectivity/data/connectivity_repository_impl.dart';
import 'package:stockflow/core/connectivity/domain/connectivity_repository.dart';
import 'package:stockflow/core/connectivity/domain/usecases/watch_connectivity_usecase.dart';
import 'package:stockflow/core/sync/cubit/pending_sync_cubit.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/sync/data/datasources/supabase_sync_data_source.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/core/sync/data/repos/sync_repository_impl.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_repository.dart';
import 'package:stockflow/core/sync/domain/usecases/pull_remote_changes_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/push_pending_changes_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/sync_data_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/watch_pending_sync_count_usecase.dart';
import 'package:stockflow/features/backup/cubit/export_cubit.dart';
import 'package:stockflow/features/backup/data/backup_repository_impl.dart';
import 'package:stockflow/features/backup/domain/backup_repository.dart';
import 'package:stockflow/features/backup/domain/entities/exportable_source.dart';
import 'package:stockflow/features/backup/domain/usecases/export_data_usecase.dart';
import 'package:stockflow/features/transactions/bloc/balance_cubit.dart';
import 'package:stockflow/features/categories/bloc/categories_bloc.dart';
import 'package:stockflow/features/categories/bloc/category_totals_cubit.dart';
import 'package:stockflow/features/transactions/bloc/transactions_bloc.dart';
import 'package:stockflow/features/transactions/data/connection.dart';
import 'package:stockflow/features/categories/data/repos/categories_export_source.dart';
import 'package:stockflow/features/categories/data/repos/category_repository_impl.dart';
import 'package:stockflow/features/transactions/data/repos/transactions_export_source.dart';
import 'package:stockflow/features/transactions/data/repos/transactions_repository_impl.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';
import 'package:stockflow/features/categories/domain/repositories/category_repository.dart';
import 'package:stockflow/features/transactions/domain/repositories/transactions_repository.dart';
import 'package:stockflow/features/categories/domain/usecases/add_category_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/add_transaction_usecase.dart';
import 'package:stockflow/features/categories/domain/usecases/delete_category_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/delete_transaction_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/get_transactions_usecase.dart';
import 'package:stockflow/features/categories/domain/usecases/update_category_usecase.dart';
import 'package:stockflow/features/transactions/domain/usecases/watch_balance_usecase.dart';
import 'package:stockflow/features/categories/domain/usecases/watch_categories_usecase.dart';
import 'package:stockflow/features/categories/domain/usecases/watch_category_totals_usecase.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // Requires Supabase.initialize() to have already completed in main().
  getIt.registerLazySingleton<SupabaseClient>(() => Supabase.instance.client);

  getIt.registerLazySingleton<ConnectivityRepository>(
    () => ConnectivityRepositoryImpl(),
  );

  getIt.registerLazySingleton<WatchConnectivityUseCase>(
    () => WatchConnectivityUseCase(getIt<ConnectivityRepository>()),
  );

  getIt.registerLazySingleton<ConnectivityCubit>(
    () => ConnectivityCubit(
      watchConnectivityUseCase: getIt<WatchConnectivityUseCase>(),
    ),
  );

  getIt.registerLazySingleton<TransactionsDataSource>(
    () => TransactionsDataSource(openTransactionsConnection()),
  );

  getIt.registerLazySingleton<SyncQueueRepository>(
    () => SyncQueueRepositoryImpl(dataSource: getIt<TransactionsDataSource>()),
  );

  getIt.registerLazySingleton<WatchPendingSyncCountUseCase>(
    () => WatchPendingSyncCountUseCase(getIt<SyncQueueRepository>()),
  );

  getIt.registerLazySingleton<SupabaseSyncDataSource>(
    () => SupabaseSyncDataSource(client: getIt<SupabaseClient>()),
  );

  getIt.registerLazySingleton<SyncRepository>(
    () => SyncRepositoryImpl(
      syncQueueRepository: getIt<SyncQueueRepository>(),
      supabaseSyncDataSource: getIt<SupabaseSyncDataSource>(),
      dataSource: getIt<TransactionsDataSource>(),
    ),
  );

  getIt.registerLazySingleton<PushPendingChangesUseCase>(
    () => PushPendingChangesUseCase(getIt<SyncRepository>()),
  );

  getIt.registerLazySingleton<PullRemoteChangesUseCase>(
    () => PullRemoteChangesUseCase(getIt<SyncRepository>()),
  );

  getIt.registerLazySingleton<SyncDataUseCase>(
    () => SyncDataUseCase(
      pushPendingChangesUseCase: getIt<PushPendingChangesUseCase>(),
      pullRemoteChangesUseCase: getIt<PullRemoteChangesUseCase>(),
    ),
  );

  // App-wide singleton: one queue-count subscription for the whole app.
  getIt.registerLazySingleton<PendingSyncCubit>(
    () => PendingSyncCubit(
      watchPendingSyncCount: getIt<WatchPendingSyncCountUseCase>(),
    ),
  );

  // App-wide singleton: one push listener for the whole app, triggered by
  // reconnecting (ConnectivityCubit) or by a new row being queued while
  // already online (PendingSyncCubit).
  getIt.registerLazySingleton<SyncCubit>(
    () => SyncCubit(
      connectivityCubit: getIt<ConnectivityCubit>(),
      pendingSyncCubit: getIt<PendingSyncCubit>(),
      syncDataUseCase: getIt<SyncDataUseCase>(),
    ),
  );

  getIt.registerLazySingleton<TransactionsRepository>(
    () => TransactionsRepositoryImpl(
      dataSource: getIt<TransactionsDataSource>(),
      syncQueueRepository: getIt<SyncQueueRepository>(),
    ),
  );

  getIt.registerLazySingleton<CategoryRepository>(
    () => CategoryRepositoryImpl(
      dataSource: getIt<TransactionsDataSource>(),
      syncQueueRepository: getIt<SyncQueueRepository>(),
    ),
  );

  getIt.registerLazySingleton<GetTransactionsUseCase>(
    () => GetTransactionsUseCase(getIt<TransactionsRepository>()),
  );

  getIt.registerLazySingleton<WatchCategoriesUseCase>(
    () => WatchCategoriesUseCase(getIt<CategoryRepository>()),
  );

  getIt.registerLazySingleton<AddCategoryUseCase>(
    () => AddCategoryUseCase(getIt<CategoryRepository>()),
  );

  getIt.registerLazySingleton<UpdateCategoryUseCase>(
    () => UpdateCategoryUseCase(getIt<CategoryRepository>()),
  );

  getIt.registerLazySingleton<DeleteCategoryUseCase>(
    () => DeleteCategoryUseCase(getIt<CategoryRepository>()),
  );

  getIt.registerLazySingleton<WatchBalanceUseCase>(
    () => WatchBalanceUseCase(getIt<TransactionsRepository>()),
  );

  getIt.registerLazySingleton<WatchCategoryTotalsUsecase>(
    () => WatchCategoryTotalsUsecase(
      categoryRepository: getIt<CategoryRepository>(),
    ),
  );

  getIt.registerLazySingleton<AddTransactionUseCase>(
    () => AddTransactionUseCase(getIt<TransactionsRepository>()),
  );

  getIt.registerLazySingleton<DeleteTransactionUseCase>(
    () => DeleteTransactionUseCase(getIt<TransactionsRepository>()),
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

  getIt.registerFactory<CategoriesBloc>(
    () => CategoriesBloc(
      watchCategoriesUseCase: getIt<WatchCategoriesUseCase>(),
      addCategoryUseCase: getIt<AddCategoryUseCase>(),
      updateCategoryUseCase: getIt<UpdateCategoryUseCase>(),
      deleteCategoryUseCase: getIt<DeleteCategoryUseCase>(),
    ),
  );

  getIt.registerLazySingleton<ExportableSource>(
    () => TransactionsExportSource(
      transactionsRepository: getIt<TransactionsRepository>(),
    ),
    instanceName: 'transactionsExportSource',
  );

  getIt.registerLazySingleton<ExportableSource>(
    () =>
        CategoriesExportSource(categoryRepository: getIt<CategoryRepository>()),
    instanceName: 'categoriesExportSource',
  );

  getIt.registerLazySingleton<BackupRepository>(
    () => BackupRepositoryImpl(
      sources: [
        getIt<ExportableSource>(instanceName: 'transactionsExportSource'),
        getIt<ExportableSource>(instanceName: 'categoriesExportSource'),
      ],
    ),
  );

  getIt.registerLazySingleton<ExportDataUseCase>(
    () => ExportDataUseCase(getIt<BackupRepository>()),
  );

  getIt.registerFactory<ExportCubit>(
    () => ExportCubit(exportDataUseCase: getIt<ExportDataUseCase>()),
  );
}
