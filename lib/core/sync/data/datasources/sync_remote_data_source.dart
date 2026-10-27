import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';

/// The server side of sync: what [SyncRepositoryImpl] needs from a remote.
///
/// [SupabaseSyncDataSource] is the real implementation. Keeping the
/// repository on this interface lets tests (including the integration test)
/// swap in an in-memory remote instead of the real Supabase project.
abstract class SyncRemoteDataSource {
  /// Pushes one queued change to the remote. Throws on a real failure
  /// (network, RLS, bad table name) -- callers catch per entry so one
  /// failure doesn't block the rest of the queue.
  Future<void> pushEntry(SyncQueueEntryEntity entry);

  /// Fetches every row of [entityType] belonging to the current user that
  /// changed after [since], oldest first.
  Future<List<Map<String, dynamic>>> pullChanges({
    required String entityType,
    required DateTime since,
  });
}
