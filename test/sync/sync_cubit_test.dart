import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/sync/domain/entities/sync_summary.dart';

import '../helpers/mocks.dart';

void main() {
  late MockConnectivityCubit connectivityCubit;
  late MockPendingSyncCubit pendingSyncCubit;
  late MockSyncDataUseCase syncDataUseCase;

  setUp(() {
    connectivityCubit = MockConnectivityCubit();
    pendingSyncCubit = MockPendingSyncCubit();
    syncDataUseCase = MockSyncDataUseCase();

    whenListen(
      connectivityCubit,
      const Stream<NetworkStatus>.empty(),
      initialState: NetworkStatus.offline,
    );

    whenListen(pendingSyncCubit, const Stream<int>.empty(), initialState: 0);
  });

  SyncCubit buildCubit() => SyncCubit(
    connectivityCubit: connectivityCubit,
    pendingSyncCubit: pendingSyncCubit,
    syncDataUseCase: syncDataUseCase,
  );

  const noChanges = SyncSummary(pushedCount: 0, pulledCount: 0);

  group('SyncCubit', () {
    test('offline at construction: starts idle, nothing is synced', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);

      expect(cubit.state, isA<SyncIdle>());
      verifyNever(() => syncDataUseCase());
    });

    blocTest<SyncCubit, SyncState>(
      'success: emits in-progress then completed with both counts',
      setUp: () {
        when(() => syncDataUseCase()).thenAnswer(
          (_) async =>
              const Success(SyncSummary(pushedCount: 2, pulledCount: 3)),
        );
      },
      build: buildCubit,
      act: (bloc) => bloc.syncNow(),
      expect: () => [
        isA<SyncInProgress>().having((s) => s.isManual, 'isManual', true),
        isA<SyncCompleted>()
            .having((s) => s.pushedCount, 'pushedCount', 2)
            .having((s) => s.pulledCount, 'pulledCount', 3),
      ],
      verify: (_) {
        verify(() => syncDataUseCase()).called(1);
      },
    );

    blocTest<SyncCubit, SyncState>(
      'failure: use case returns a Failure -> emits SyncFailure',
      setUp: () {
        when(
          () => syncDataUseCase(),
        ).thenAnswer((_) async => const Failure('Sync Failed'));
      },
      build: buildCubit,
      act: (bloc) => bloc.syncNow(),
      expect: () => [
        isA<SyncInProgress>().having((s) => s.isManual, 'isManual', true),
        isA<SyncFailure>().having(
          (s) => s.message,
          'message',
          contains('Sync Failed'),
        ),
      ],
      verify: (_) {
        verify(() => syncDataUseCase()).called(1);
      },
    );

    blocTest<SyncCubit, SyncState>(
      'failure: use case throws -> emits SyncFailure',
      setUp: () {
        when(() => syncDataUseCase()).thenThrow(Exception('boom'));
      },
      build: buildCubit,
      act: (bloc) => bloc.syncNow(),
      expect: () => [
        isA<SyncInProgress>(),
        isA<SyncFailure>().having(
          (s) => s.message,
          'message',
          contains('boom'),
        ),
      ],
    );

    final gate = Completer<Result<SyncSummary>>();

    blocTest<SyncCubit, SyncState>(
      'second syncNow() while one is running is ignored',
      setUp: () {
        when(() => syncDataUseCase()).thenAnswer((_) => gate.future);
      },
      build: buildCubit,
      act: (cubit) async {
        final first = cubit
            .syncNow(); // don't await: it's now stuck at the use case
        await cubit.syncNow(); // returns immediately: guard hits
        gate.complete(const Success(noChanges)); // let the first one finish
        await first;
      },
      expect: () => [
        isA<SyncInProgress>().having((s) => s.isManual, 'isManual', true),
        isA<SyncCompleted>(),
      ],
      verify: (_) => verify(() => syncDataUseCase()).called(1),
    );

    blocTest<SyncCubit, SyncState>(
      'allFailed: queue had pending changes but none were pushed',
      setUp: () {
        whenListen(
          pendingSyncCubit,
          const Stream<int>.empty(),
          initialState: 3,
        );
        when(
          () => syncDataUseCase(),
        ).thenAnswer((_) async => const Success(noChanges));
      },
      build: buildCubit,
      act: (cubit) => cubit.syncNow(),
      expect: () => [
        isA<SyncInProgress>(),
        isA<SyncCompleted>().having((s) => s.allFailed, 'allFailed', true),
      ],
    );

    blocTest<SyncCubit, SyncState>(
      'allFailed is false when nothing was pending and nothing was pushed',
      setUp: () {
        // The outer setUp already reports a pending count of 0.
        when(
          () => syncDataUseCase(),
        ).thenAnswer((_) async => const Success(noChanges));
      },
      build: buildCubit,
      act: (cubit) => cubit.syncNow(),
      expect: () => [
        isA<SyncInProgress>(),
        isA<SyncCompleted>().having((s) => s.allFailed, 'allFailed', false),
      ],
    );
  });
}
