import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stockflow/core/connectivity/domain/connectivity_repository.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/service_locator.dart';
import 'package:stockflow/core/sync/data/datasources/sync_remote_data_source.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/sync/presentation/widgets/pending_sync_badge.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';
import 'package:stockflow/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:stockflow/main.dart';

import 'fakes/fake_connectivity_repository.dart';
import 'fakes/fake_sync_remote.dart';

/// Pumps frames until [condition] holds. The work behind the UI (the database,
/// the sync) finishes on its own time, between frames, so a fixed number of
/// pumps would be a guess.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for the condition.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeConnectivityRepository connectivity;
  late FakeSyncRemote remote;

  // The pending-sync badge in the app bar: its count label, and the badge
  // itself (which only exists while something is waiting to sync).
  final pendingBadge = find.descendant(
    of: find.byType(PendingSyncBadge),
    matching: find.byType(Badge),
  );
  final pendingCountOne = find.descendant(
    of: find.byType(PendingSyncBadge),
    matching: find.text('1'),
  );

  setUp(() {
    connectivity = FakeConnectivityRepository();
    remote = FakeSyncRemote();

    // Real everything (blocs, repositories, an in-memory Drift database),
    // except the two edges: the network and the server. Swap those before
    // anything resolves them (both registrations are lazy).
    setupServiceLocator(database: NativeDatabase.memory());
    getIt.unregister<ConnectivityRepository>();
    getIt.registerLazySingleton<ConnectivityRepository>(() => connectivity);
    getIt.unregister<SyncRemoteDataSource>();
    getIt.registerLazySingleton<SyncRemoteDataSource>(() => remote);
  });

  tearDown(() async {
    await getIt<TransactionsDataSource>().close();
    await connectivity.dispose();
    await getIt.reset();
  });

  testWidgets('the app starts on the transactions screen', (tester) async {
    // Pump MyApp directly, not main(): main() initializes Supabase and signs
    // in, which a test must never do.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(TransactionsScreen), findsOneWidget);

    // Unmount the app before tearDown closes the database under it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a transaction added offline is pending, then synced when back '
      'online', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // ConnectivityCubit starts as online, so go offline first. Otherwise the
    // new transaction would sync at once and never show as pending.
    connectivity.setStatus(NetworkStatus.offline);
    await tester.pumpAndSettle();

    // Add a transaction through the real UI.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '12.50',
    );
    await tester.tap(find.text('Save'));

    // Written to Drift and queued: the badge shows 1, and nothing has been
    // sent to the server.
    await pumpUntil(tester, () => pendingCountOne.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(pendingCountOne, findsOneWidget);
    expect(remote.pushed, isEmpty);

    // Back online: the queued change is pushed and the badge clears.
    connectivity.setStatus(NetworkStatus.online);
    await pumpUntil(tester, () => pendingBadge.evaluate().isEmpty);

    expect(pendingBadge, findsNothing);
    expect(remote.pushed, hasLength(1));
    expect(remote.pushed.single.entityType, 'transaction');
    expect(remote.pushed.single.operation, OperationType.create);

    // Unmount the app before tearDown closes the database under it.
    await tester.pumpWidget(const SizedBox());
  });
}
