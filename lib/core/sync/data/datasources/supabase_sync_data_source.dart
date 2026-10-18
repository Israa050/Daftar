import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/sync/domain/entities/sync_queue_entry_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncDataSource {
  final SupabaseClient client;

  SupabaseSyncDataSource({required this.client});

  static const _tableNames = {
    'transaction': 'transactions',
    'category': 'categories',
  };

  /// Pushes one queued change to Supabase. Throws on a real failure
  /// (network, RLS, bad table name) -- callers (SyncRepository.pushPending)
  /// catch per-entry so one failure doesn't block the rest of the queue.
  Future<void> pushEntry(SyncQueueEntryEntity entry) async {
    final tableName = _tableNames[entry.entityType] ?? entry.entityType;

    switch (entry.operation) {
      case OperationType.create:
      case OperationType.update:
        final local = jsonDecode(entry.payload) as Map<String, dynamic>;
        final userId = client.auth.currentUser!.id;
        final mapped = mapForSupabase(entry.entityType, local, userId);
        // A Postgres function, not an upsert: it writes only if the server
        // row is not newer, so a stale offline edit cannot overwrite a newer
        // edit from another device. A rejected stale write returns normally,
        // so the caller still dequeues it and the next pull brings the newer
        // row down.
        final call = rpcCallFor(entry.entityType, mapped);
        await client.rpc(call.function, params: call.params);

      case OperationType.delete:
        // No rows-affected check needed: Postgrest's delete doesn't throw
        // when zero rows match, so deleting an already-gone row is already
        // a no-op success, not a Failure.
        await client.from(tableName).delete().eq('id', entry.entityId);
    }
  }

  /// Fetches every row in [entityType]'s remote table belonging to the
  /// current user that changed after [since], oldest first. [since] should
  /// be the start of the previous pull (see SyncRepositoryImpl), not its
  /// completion, so a row that changes while this pull is in flight is
  /// simply picked up again next time rather than missed.
  ///
  /// Remote deletes are not represented here: pushEntry hard-deletes rows on
  /// delete, leaving no tombstone to pull, so a delete made on one device
  /// is not currently propagated to others via pull. Out of scope for now
  /// -- see brief.
  Future<List<Map<String, dynamic>>> pullChanges({
    required String entityType,
    required DateTime since,
  }) async {
    final tableName = _tableNames[entityType] ?? entityType;
    final userId = client.auth.currentUser!.id;

    final rows = await client
        .from(tableName)
        .select()
        .eq('user_id', userId)
        .gt('updated_at', since.toUtc().toIso8601String())
        .order('updated_at');

    return List<Map<String, dynamic>>.from(rows);
  }

  /// Translates a locally-stored payload (camelCase, Drift-native field
  /// names) into the shape Supabase's tables actually expect (snake_case,
  /// plus the owning user_id required by their "own rows only" RLS
  /// policies). Kept separate from the local payload format so queued rows
  /// from before a remote schema change still push correctly after an app
  /// update changes this mapping.
  ///
  /// `@visibleForTesting`: mocktail can't reliably intercept Supabase's
  /// `client.from(...).upsert(...)` chain (its awaitability comes from an
  /// overridden generic `then`), so this mapping is tested directly instead.
  @visibleForTesting
  Map<String, dynamic> mapForSupabase(
    String entityType,
    Map<String, dynamic> local,
    String userId,
  ) {
    switch (entityType) {
      case 'transaction':
        return {
          'id': local['id'],
          'user_id': userId,
          'amount_minor': local['amountMinor'],
          'type': local['type'],
          'note': local['note'],
          'category_id': local['categoryId'],
          'occurred_at': local['occurredTime'],
          'created_at': local['creationTime'],
          'updated_at': local['updatedAt'],
        };
      case 'category':
        return {
          'id': local['id'],
          'user_id': userId,
          'name': local['name'],
          'color_hex': local['colorHex'],
          'updated_at': local['updatedAt'],
        };
      default:
        return local;
    }
  }

  /// Which Postgres function to call, and its arguments, for one create or
  /// update. [mapped] is the output of [mapForSupabase].
  ///
  /// Argument names carry the `p_` prefix the functions declare (see
  /// supabase/migrations/*_push_if_newer_functions.sql), and `user_id` is
  /// deliberately absent: the functions take the owner from `auth.uid()`.
  ///
  /// Throws for an unknown [entityType]; pushPending catches per entry, so
  /// one bad row stays queued without blocking the rest.
  ///
  /// `@visibleForTesting`: the `client.rpc(...)` call itself can't be mocked,
  /// so this pure mapping is what the tests check.
  @visibleForTesting
  ({String function, Map<String, dynamic> params}) rpcCallFor(
    String entityType,
    Map<String, dynamic> mapped,
  ) {
    switch (entityType) {
      case 'transaction':
        return (
          function: 'push_transaction',
          params: {
            'p_id': mapped['id'],
            'p_amount_minor': mapped['amount_minor'],
            'p_type': mapped['type'],
            'p_note': mapped['note'],
            'p_category_id': mapped['category_id'],
            'p_occurred_at': mapped['occurred_at'],
            'p_created_at': mapped['created_at'],
            'p_updated_at': mapped['updated_at'],
          },
        );
      case 'category':
        return (
          function: 'push_category',
          params: {
            'p_id': mapped['id'],
            'p_name': mapped['name'],
            'p_color_hex': mapped['color_hex'],
            'p_updated_at': mapped['updated_at'],
          },
        );
      default:
        throw ArgumentError('No push function for entity type "$entityType"');
    }
  }
}
