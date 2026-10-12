import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/domain/entities/sync_summary.dart';
import 'package:stockflow/core/sync/domain/usecases/sync_data_usecase.dart';

import '../helpers/mocks.dart';

void main() {
  late MockPushPendingChangesUseCase pushPendingChangesUseCase;
  late MockPullRemoteChangesUseCase pullRemoteChangesUseCase;
  late SyncDataUseCase syncDataUseCase;

  setUp(() {
    pushPendingChangesUseCase = MockPushPendingChangesUseCase();
    pullRemoteChangesUseCase = MockPullRemoteChangesUseCase();
    syncDataUseCase = SyncDataUseCase(
      pushPendingChangesUseCase: pushPendingChangesUseCase,
      pullRemoteChangesUseCase: pullRemoteChangesUseCase,
    );
  });

  test('both succeed -> counts reach the summary', () async {
    when(
      () => pushPendingChangesUseCase(),
    ).thenAnswer((_) async => const Success(2));
    when(
      () => pullRemoteChangesUseCase(),
    ).thenAnswer((_) async => const Success(3));

    final result = await syncDataUseCase();

    expect(result, isA<Success<SyncSummary>>());
    final summary = (result as Success<SyncSummary>).data;
    expect(summary.pushedCount, 2);
    expect(summary.pulledCount, 3);
  });

  test('push fails -> returns that failure, pull is skipped', () async {
    when(
      () => pushPendingChangesUseCase(),
    ).thenAnswer((_) async => const Failure('push error'));

    final result = await syncDataUseCase();

    expect(result, isA<Failure<SyncSummary>>());
    expect((result as Failure<SyncSummary>).message, 'push error');
    verifyNever(() => pullRemoteChangesUseCase());
  });

  test('pull fails -> returns that failure', () async {
    when(
      () => pushPendingChangesUseCase(),
    ).thenAnswer((_) async => const Success(1));
    when(
      () => pullRemoteChangesUseCase(),
    ).thenAnswer((_) async => const Failure('pull error'));

    final result = await syncDataUseCase();

    expect(result, isA<Failure<SyncSummary>>());
    expect((result as Failure<SyncSummary>).message, 'pull error');
    verify(() => pushPendingChangesUseCase()).called(1);
  });

  test('nothing pushed -> pull still runs', () async {
    when(
      () => pushPendingChangesUseCase(),
    ).thenAnswer((_) async => const Success(0));
    when(
      () => pullRemoteChangesUseCase(),
    ).thenAnswer((_) async => const Success(4));

    final result = await syncDataUseCase();

    expect(result, isA<Success<SyncSummary>>());
    final summary = (result as Success<SyncSummary>).data;
    expect(summary.pushedCount, 0);
    expect(summary.pulledCount, 4);
    verify(() => pullRemoteChangesUseCase()).called(1);
  });

  test('push runs before pull', () async {
    when(
      () => pushPendingChangesUseCase(),
    ).thenAnswer((_) async => const Success(1));
    when(
      () => pullRemoteChangesUseCase(),
    ).thenAnswer((_) async => const Success(1));

    await syncDataUseCase();

    verifyInOrder([
      () => pushPendingChangesUseCase(),
      () => pullRemoteChangesUseCase(),
    ]);
  });
}
