import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/domain/entities/sync_summary.dart';
import 'package:stockflow/core/sync/domain/usecases/pull_remote_changes_usecase.dart';
import 'package:stockflow/core/sync/domain/usecases/push_pending_changes_usecase.dart';

/// Runs one full sync: push queued local changes, then pull remote ones.
class SyncDataUseCase {
  SyncDataUseCase({
    required PushPendingChangesUseCase pushPendingChangesUseCase,
    required PullRemoteChangesUseCase pullRemoteChangesUseCase,
  }) : _pushPendingChangesUseCase = pushPendingChangesUseCase,
       _pullRemoteChangesUseCase = pullRemoteChangesUseCase;

  final PushPendingChangesUseCase _pushPendingChangesUseCase;
  final PullRemoteChangesUseCase _pullRemoteChangesUseCase;

  /// A push failure returns immediately without pulling. Pull runs even when
  /// nothing was pushed: it is the only way this device learns about changes
  /// made on other devices.
  Future<Result<SyncSummary>> call() async {
    final int pushedCount;
    switch (await _pushPendingChangesUseCase()) {
      case Success(:final data):
        pushedCount = data;
      case Failure(:final message):
        return Failure(message);
    }

    final int pulledCount;
    switch (await _pullRemoteChangesUseCase()) {
      case Success(:final data):
        pulledCount = data;
      case Failure(:final message):
        return Failure(message);
    }

    return Success(
      SyncSummary(pushedCount: pushedCount, pulledCount: pulledCount),
    );
  }
}
