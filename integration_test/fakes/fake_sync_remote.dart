import 'package:stockflow/core/sync/data/datasources/sync_remote_data_source.dart';
import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';

/// An in-memory stand-in for the Supabase remote. It records every change the
/// app pushes so the test can check what reached "the server", and it never
/// has anything new to pull. It makes no network calls and needs no secrets.
class FakeSyncRemote implements SyncRemoteDataSource {
  /// Every entry pushed, in order.
  final List<SyncQueueEntryEntity> pushed = [];

  @override
  Future<void> pushEntry(SyncQueueEntryEntity entry) async {
    pushed.add(entry);
  }

  @override
  Future<List<Map<String, dynamic>>> pullChanges({
    required String entityType,
    required DateTime since,
  }) async => const [];
}
