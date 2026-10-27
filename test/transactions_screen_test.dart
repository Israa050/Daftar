import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/connectivity/cubit/connectivity_cubit.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/service_locator.dart';
import 'package:stockflow/core/sync/cubit/pending_sync_cubit.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/theme/app_theme.dart';
import 'package:stockflow/features/backup/cubit/export_cubit.dart';
import 'package:stockflow/features/categories/bloc/category_totals_cubit.dart';
import 'package:stockflow/features/categories/domain/entities/category_total_entity.dart';
import 'package:stockflow/features/transactions/bloc/transactions_bloc.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:stockflow/features/transactions/presentation/screens/transactions_screen.dart';

class _MockTransactionsBloc
    extends MockBloc<TransactionsEvent, TransactionsState>
    implements TransactionsBloc {}

class _MockConnectivityCubit extends MockCubit<NetworkStatus>
    implements ConnectivityCubit {}

class _MockPendingSyncCubit extends MockCubit<int>
    implements PendingSyncCubit {}

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class _MockCategoryTotalsCubit extends MockCubit<List<CategoryTotalEntity>>
    implements CategoryTotalsCubit {}

class _MockExportCubit extends MockCubit<ExportState> implements ExportCubit {}

final _lunch = TransactionEntity(
  id: 't1',
  amountMinor: 500,
  type: TransactionType.expense,
  note: 'Lunch',
  timestamp: DateTime(2026, 1, 1, 12),
  categoryId: null,
);

void main() {
  late _MockTransactionsBloc bloc;
  late StreamController<TransactionsState> states;

  setUpAll(() => registerFallbackValue(AppLaunchEvent()));

  setUp(() {
    bloc = _MockTransactionsBloc();
    states = StreamController<TransactionsState>.broadcast();
    when(() => bloc.isClosed).thenReturn(false);

    final exportCubit = _MockExportCubit();
    whenListen(
      exportCubit,
      const Stream<ExportState>.empty(),
      initialState: ExportIdle(),
    );
    // ExportAction in the app bar creates its cubit through GetIt.
    getIt.registerFactory<ExportCubit>(() => exportCubit);
  });

  tearDown(() async {
    await states.close();
    await getIt.reset();
  });

  Widget screen() {
    final connectivity = _MockConnectivityCubit();
    whenListen(
      connectivity,
      const Stream<NetworkStatus>.empty(),
      initialState: NetworkStatus.online,
    );
    final pending = _MockPendingSyncCubit();
    whenListen(pending, const Stream<int>.empty(), initialState: 0);
    final sync = _MockSyncCubit();
    whenListen(sync, const Stream<SyncState>.empty(), initialState: SyncIdle());
    final totals = _MockCategoryTotalsCubit();
    whenListen(
      totals,
      const Stream<List<CategoryTotalEntity>>.empty(),
      initialState: const <CategoryTotalEntity>[],
    );

    return MaterialApp(
      theme: AppTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ConnectivityCubit>.value(value: connectivity),
          BlocProvider<PendingSyncCubit>.value(value: pending),
          BlocProvider<SyncCubit>.value(value: sync),
          BlocProvider<CategoryTotalsCubit>.value(value: totals),
          BlocProvider<TransactionsBloc>.value(value: bloc),
        ],
        child: const TransactionsScreen(),
      ),
    );
  }

  void startLoaded(List<TransactionEntity> data) {
    whenListen(
      bloc,
      states.stream,
      initialState: Loaded(data: data, categories: const []),
    );
  }

  /// Swipes the first row away and waits out the 5-second undo window.
  Future<void> swipeAndWaitForUndoWindow(WidgetTester tester) async {
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  // A function, because mocktail's any() may only run inside verify()/when().
  TransactionsEvent deleteEvent() =>
      any<TransactionsEvent>(that: isA<DeleteTransactionEvent>());

  group('TransactionsScreen swipe-to-delete', () {
    testWidgets('deletes the row once the undo window passes', (tester) async {
      startLoaded([_lunch]);
      await tester.pumpWidget(screen());

      await swipeAndWaitForUndoWindow(tester);

      verify(() => bloc.add(deleteEvent())).called(1);
    });

    testWidgets('does not add an event to a bloc that is already closed', (
      tester,
    ) async {
      startLoaded([_lunch]);
      await tester.pumpWidget(screen());
      when(() => bloc.isClosed).thenReturn(true);

      await swipeAndWaitForUndoWindow(tester);

      verifyNever(() => bloc.add(deleteEvent()));
    });
  });

  group('TransactionsScreen errors', () {
    testWidgets('shows an error snackbar once, not again on a rebuild', (
      tester,
    ) async {
      startLoaded(const []);
      await tester.pumpWidget(screen());

      states.add(TransactionsError(message: 'Boom', previousData: const []));
      await tester.pump();
      await tester.pump();
      expect(find.text('Boom'), findsOneWidget);

      // Let that snackbar go away: first its entry animation finishes (which
      // is when its dismiss timer starts), then the timer runs out.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Boom'), findsNothing);

      // Rebuild the screen while the state is still the error. It must not
      // queue the same snackbar again.
      await tester.pumpWidget(screen());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Boom'), findsNothing);
    });
  });
}
