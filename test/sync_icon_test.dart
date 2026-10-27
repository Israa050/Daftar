import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/sync/presentation/widgets/sync_icon.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

Widget _icon(SyncCubit cubit, {bool disableAnimations = false}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: BlocProvider<SyncCubit>.value(
          value: cubit,
          child: const Scaffold(body: SyncIcon()),
        ),
      ),
    ),
  );
}

SyncState _syncing() => SyncInProgress(isManual: false);

SyncState _done() => SyncCompleted(
  pushedCount: 1,
  pulledCount: 0,
  allFailed: false,
  isManual: false,
);

void main() {
  late _MockSyncCubit cubit;
  late StreamController<SyncState> states;

  /// Starts the cubit in [initial]; later states are pushed with [states].
  void startIn(SyncState initial) {
    whenListen(cubit, states.stream, initialState: initial);
  }

  setUp(() {
    cubit = _MockSyncCubit();
    states = StreamController<SyncState>.broadcast();
  });

  tearDown(() => states.close());

  group('SyncIcon', () {
    testWidgets('rests as a cloud and does not animate when idle', (
      tester,
    ) async {
      startIn(SyncIdle());
      await tester.pumpWidget(_icon(cubit));

      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('spins while syncing', (tester) async {
      startIn(SyncIdle());
      await tester.pumpWidget(_icon(cubit));

      states.add(_syncing());
      await tester.pump();

      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);

      // It really turns: the rotation moves away from its start.
      await tester.pump(const Duration(milliseconds: 250));
      final rotation = tester.widget<RotationTransition>(
        find.descendant(
          of: find.byType(SyncIcon),
          matching: find.byType(RotationTransition),
        ),
      );
      expect(rotation.turns.value, greaterThan(0));
    });

    testWidgets('stops and returns to the cloud when the sync finishes', (
      tester,
    ) async {
      startIn(SyncIdle());
      await tester.pumpWidget(_icon(cubit));

      states.add(_syncing());
      await tester.pump();
      states.add(_done());
      await tester.pump();

      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('spins at once when a sync is already running on mount', (
      tester,
    ) async {
      startIn(_syncing());
      await tester.pumpWidget(_icon(cubit));

      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('shows the sync arrow but does not spin under reduced motion', (
      tester,
    ) async {
      startIn(_syncing());
      await tester.pumpWidget(_icon(cubit, disableAnimations: true));

      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('leaves no ticker running once removed mid-sync', (
      tester,
    ) async {
      startIn(_syncing());
      await tester.pumpWidget(_icon(cubit));
      expect(tester.hasRunningAnimations, isTrue);

      // Replace the whole tree, as leaving the screen would. A controller that
      // was not disposed would keep its ticker alive and fail this test.
      await tester.pumpWidget(const SizedBox());

      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
