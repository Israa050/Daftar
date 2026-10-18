import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/sync/data/datasources/supabase_sync_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late SupabaseSyncDataSource dataSource;

  setUp(() {
    // pushEntry() itself is not under test here (see mapForSupabase's doc
    // comment for why) -- the client is only needed to construct
    // SupabaseSyncDataSource, so it's never stubbed or touched.
    dataSource = SupabaseSyncDataSource(client: MockSupabaseClient());
  });

  group('mapForSupabase - transaction', () {
    test(
      'maps every camelCase local field to its snake_case remote column',
      () {
        final result = dataSource.mapForSupabase('transaction', {
          'id': 'txn-1',
          'amountMinor': 500,
          'type': 'expense',
          'note': 'coffee',
          'categoryId': 'cat-1',
          'occurredTime': '2026-01-01T00:00:00.000Z',
          'creationTime': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        }, 'user-123');

        expect(result, {
          'id': 'txn-1',
          'user_id': 'user-123',
          'amount_minor': 500,
          'type': 'expense',
          'note': 'coffee',
          'category_id': 'cat-1',
          'occurred_at': '2026-01-01T00:00:00.000Z',
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
        });
      },
    );

    test('stamps the given userId as user_id, not anything from local', () {
      final result = dataSource.mapForSupabase('transaction', {
        'id': 'txn-1',
        'amountMinor': 500,
        'type': 'expense',
        'note': null,
        'categoryId': null,
        'occurredTime': '2026-01-01T00:00:00.000Z',
        'creationTime': '2026-01-01T00:00:00.000Z',
      }, 'the-signed-in-user');

      expect(result['user_id'], 'the-signed-in-user');
    });

    test(
      'null note/categoryId pass through as null, not dropped or defaulted',
      () {
        final result = dataSource.mapForSupabase('transaction', {
          'id': 'txn-1',
          'amountMinor': 500,
          'type': 'expense',
          'note': null,
          'categoryId': null,
          'occurredTime': '2026-01-01T00:00:00.000Z',
          'creationTime': '2026-01-01T00:00:00.000Z',
        }, 'user-123');

        expect(result.containsKey('note'), true);
        expect(result['note'], null);
        expect(result.containsKey('category_id'), true);
        expect(result['category_id'], null);
      },
    );

    test('the old camelCase keys never appear in the output', () {
      final result = dataSource.mapForSupabase('transaction', {
        'id': 'txn-1',
        'amountMinor': 500,
        'type': 'expense',
        'note': 'coffee',
        'categoryId': 'cat-1',
        'occurredTime': '2026-01-01T00:00:00.000Z',
        'creationTime': '2026-01-01T00:00:00.000Z',
      }, 'user-123');

      for (final camelKey in [
        'amountMinor',
        'categoryId',
        'occurredTime',
        'creationTime',
      ]) {
        expect(
          result.containsKey(camelKey),
          false,
          reason: '$camelKey should have been renamed, not carried over',
        );
      }
    });
  });

  group('mapForSupabase - category', () {
    test('maps id/name/colorHex to id/name/color_hex plus user_id', () {
      final result = dataSource.mapForSupabase('category', {
        'id': 'cat-1',
        'name': 'Food',
        'colorHex': '#FF9800',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      }, 'user-123');

      expect(result, {
        'id': 'cat-1',
        'user_id': 'user-123',
        'name': 'Food',
        'color_hex': '#FF9800',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
    });

    test('null colorHex passes through as null', () {
      final result = dataSource.mapForSupabase('category', {
        'id': 'cat-1',
        'name': 'Food',
        'colorHex': null,
      }, 'user-123');

      expect(result['color_hex'], null);
    });

    test('does not include transaction-only fields', () {
      final result = dataSource.mapForSupabase('category', {
        'id': 'cat-1',
        'name': 'Food',
        'colorHex': '#FF9800',
      }, 'user-123');

      expect(result.containsKey('amount_minor'), false);
      expect(result.containsKey('occurred_at'), false);
    });
  });

  group('mapForSupabase - unknown entity type', () {
    test('an unrecognized entityType returns the local payload unchanged', () {
      final local = {'id': 'x-1', 'someField': 'value'};

      final result = dataSource.mapForSupabase(
        'something-new',
        local,
        'user-123',
      );

      expect(result, local);
      // Deliberately not renamed and no user_id stamped -- this is the
      // fallback branch (`default: return local;`), included so a future
      // entity type isn't silently mis-synced without a test noticing.
      expect(result.containsKey('user_id'), false);
    });
  });

  // rpcCallFor picks the Postgres function and its p_-prefixed arguments for a
  // create/update. Its input is mapForSupabase's output, so build it the way
  // the app does (mapForSupabase first, then rpcCallFor). The record it returns
  // has `.function` and `.params`. Each case is a skipped placeholder until
  // its body is written.
  group('rpcCallFor', () {
    test('category -> push_category with exactly the four p_ arguments', () {
      final mapped = dataSource.mapForSupabase('category', {
        'id': 'cat-1',
        'name': 'Food',
        'colorHex': '#FF9800',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      }, 'user-123');

      final call = dataSource.rpcCallFor('category', mapped);

      expect(call.function, 'push_category');
      expect(
        call.params.keys,
        unorderedEquals(['p_id', 'p_name', 'p_color_hex', 'p_updated_at']),
      );
    });

    // Same path the app takes: local payload -> mapForSupabase -> rpcCallFor.
    Map<String, dynamic> mappedCategory({String? colorHex = '#FF9800'}) =>
        dataSource.mapForSupabase('category', {
          'id': 'cat-1',
          'name': 'Food',
          'colorHex': colorHex,
          'updatedAt': '2026-01-01T00:00:05.000Z',
        }, 'user-123');

    Map<String, dynamic> mappedTransaction({
      String? note = 'coffee',
      String? categoryId = 'cat-1',
    }) => dataSource.mapForSupabase('transaction', {
      'id': 'txn-1',
      'amountMinor': 500,
      'type': 'expense',
      'note': note,
      'categoryId': categoryId,
      'occurredTime': '2026-01-01T00:00:01.000Z',
      'creationTime': '2026-01-01T00:00:02.000Z',
      'updatedAt': '2026-01-01T00:00:05.000Z',
    }, 'user-123');

    test(
      'transaction -> push_transaction with exactly the eight p_ arguments',
      () {
        final call = dataSource.rpcCallFor('transaction', mappedTransaction());

        expect(call.function, 'push_transaction');
        expect(
          call.params.keys,
          unorderedEquals([
            'p_id',
            'p_amount_minor',
            'p_type',
            'p_note',
            'p_category_id',
            'p_occurred_at',
            'p_created_at',
            'p_updated_at',
          ]),
        );
      },
    );

    test(
      'user_id is never sent (the function takes the owner from auth.uid())',
      () {
        // mapForSupabase stamps user_id; rpcCallFor must drop it, because the
        // functions have no such parameter and PostgREST would answer
        // "function not found".
        final category = dataSource.rpcCallFor('category', mappedCategory());
        final transaction = dataSource.rpcCallFor(
          'transaction',
          mappedTransaction(),
        );

        expect(category.params.containsKey('user_id'), isFalse);
        expect(transaction.params.containsKey('user_id'), isFalse);
        expect(category.params.values, isNot(contains('user-123')));
        expect(transaction.params.values, isNot(contains('user-123')));
      },
    );

    test(
      'values come through from the mapped row, p_updated_at is not null',
      () {
        final category = dataSource.rpcCallFor('category', mappedCategory());
        expect(category.params, {
          'p_id': 'cat-1',
          'p_name': 'Food',
          'p_color_hex': '#FF9800',
          'p_updated_at': '2026-01-01T00:00:05.000Z',
        });

        final transaction = dataSource.rpcCallFor(
          'transaction',
          mappedTransaction(),
        );
        expect(transaction.params, {
          'p_id': 'txn-1',
          'p_amount_minor': 500,
          'p_type': 'expense',
          'p_note': 'coffee',
          'p_category_id': 'cat-1',
          'p_occurred_at': '2026-01-01T00:00:01.000Z',
          'p_created_at': '2026-01-01T00:00:02.000Z',
          'p_updated_at': '2026-01-01T00:00:05.000Z',
        });

        // The earlier bug read the wrong keys and sent a null timestamp, which
        // violates NOT NULL on the server.
        expect(category.params['p_updated_at'], isNotNull);
        expect(transaction.params['p_updated_at'], isNotNull);
      },
    );

    test('null optional fields stay null (note, colorHex, categoryId)', () {
      final category = dataSource.rpcCallFor(
        'category',
        mappedCategory(colorHex: null),
      );
      expect(category.params.containsKey('p_color_hex'), isTrue);
      expect(category.params['p_color_hex'], isNull);

      final transaction = dataSource.rpcCallFor(
        'transaction',
        mappedTransaction(note: null, categoryId: null),
      );
      expect(transaction.params.containsKey('p_note'), isTrue);
      expect(transaction.params['p_note'], isNull);
      expect(transaction.params.containsKey('p_category_id'), isTrue);
      expect(transaction.params['p_category_id'], isNull);
    });

    test('an unknown entity type throws ArgumentError', () {
      expect(
        () => dataSource.rpcCallFor('something-new', {'id': 'x-1'}),
        throwsArgumentError,
      );
    });
  });
}
