import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/sync/data/repos/sync_queue_repository_impl.dart';
import 'package:stockflow/features/transactions/data/repos/transactions_repository_impl.dart';
import 'package:stockflow/features/transactions/data/transactions_data_source.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:uuid/uuid.dart';

void main() {
  late TransactionsDataSource dataSource;
  late TransactionsRepositoryImpl repository;

  setUp(() {
    dataSource = TransactionsDataSource(NativeDatabase.memory());
    repository = TransactionsRepositoryImpl(
      dataSource: dataSource,
      syncQueueRepository: SyncQueueRepositoryImpl(dataSource: dataSource),
    );
  });

  tearDown(() async {
    await dataSource.close();
  });

  group('addTransaction', () {
    test(
      'note omitted -> stored as null, readable via getAllTransactions.',
      () async {
        await repository.addTransaction(
          amountMinor: 5,
          type: TransactionType.income,
        );

        final rows = await repository.getAllTransactions().first;
        expect(rows.single.note, '');
      },
    );

    test(
      'note provided -> round-trips through addTransaction + getAllTransactions.',
      () async {
        await repository.addTransaction(
          amountMinor: 5,
          type: TransactionType.income,
          note: 'groceries',
        );

        final rows = await repository.getAllTransactions().first;
        expect(rows.single.note, 'groceries');
      },
    );

    test(
      'type and amountMinor are passed straight through unchanged.',
      () async {
        await repository.addTransaction(
          amountMinor: 999,
          type: TransactionType.expense,
        );

        final rows = await repository.getAllTransactions().first;
        expect(rows.single.amountMinor, 999);
        expect(rows.single.type, TransactionType.expense);
      },
    );

    test(
      'each call generates a distinct id -> two inserts produce two rows.',
      () async {
        await repository.addTransaction(
          amountMinor: 5,
          type: TransactionType.income,
        );
        await repository.addTransaction(
          amountMinor: 5,
          type: TransactionType.income,
        );

        final rows = await repository.getAllTransactions().first;
        expect(rows.length, 2);
        expect(rows[0].id, isNot(rows[1].id));
      },
    );

    test(
      'valid entry -> Success(null), and the row is readable via getAllTransactions after.',
      () async {
        final addResult = await repository.addTransaction(
          amountMinor: 20,
          type: TransactionType.expense,
        );
        expect(addResult, isA<Success<void>>());

        final rows = await repository.getAllTransactions().first;
        expect(rows.single.amountMinor, 20);
      },
    );

    test('local updatedAt and the queued payload updatedAt are the same '
        'instant.', () async {
      await repository.addTransaction(
        amountMinor: 5,
        type: TransactionType.expense,
      );
      final row = (await dataSource.getAllTransactionsOnce()).single;
      final queued = (await dataSource.getAllSyncQueueEntries()).single;
      final payloadUpdatedAt =
          jsonDecode(queued.payload)['updatedAt'] as String;

      expect(
        DateTime.parse(payloadUpdatedAt),
        row.updatedAt.toUtc(),
        reason:
            'Drift stores whole seconds; the payload must carry the same '
            'value or a pull sees its own push as newer.',
      );
    });
  });

  group('getAllTransactions', () {
    test('empty table -> emits [].', () async {
      final rows = await repository.getAllTransactions().first;
      expect(rows, isEmpty);
    });

    test(
      'is reactive -- emits again when a row is added after subscribing.',
      () async {
        expectLater(
          repository.getAllTransactions(),
          emitsInOrder([
            isEmpty,
            predicate<List<TransactionEntity>>(
              (list) => list.length == 1 && list.single.amountMinor == 15,
            ),
          ]),
        );
        await Future<void>.delayed(Duration.zero);
        await repository.addTransaction(
          amountMinor: 15,
          type: TransactionType.income,
        );
      },
    );

    // Not tested here: forcing dataSource to throw. Closing the connection
    // doesn't throw on NativeDatabase.memory() -- it hangs the next query
    // instead, so it can't be used to reliably exercise the catch/Failure
    // path.
  });

  group('deleteTransaction', () {
    test(
      'existing id -> Success(1), row no longer present afterward.',
      () async {
        await repository.addTransaction(
          amountMinor: 30,
          type: TransactionType.expense,
        );
        final entryId = (await repository.getAllTransactions().first).single.id;

        final deleteResult = await repository.deleteTransaction(entryId);

        expect(deleteResult, isA<Success<int>>());
        expect((deleteResult as Success<int>).data, 1);

        final rows = await repository.getAllTransactions().first;
        expect(rows, isEmpty);
      },
    );

    test(
      'non-existent id -> Success(0), not a Failure (mirrors data source behavior).',
      () async {
        final deleteResult = await repository.deleteTransaction(
          const Uuid().v4(),
        );

        expect(deleteResult, isA<Success<int>>());
        expect((deleteResult as Success<int>).data, 0);
      },
    );

    // Not tested here: forcing dataSource to throw, for the same reason as
    // getAllTransactions above (close() hangs rather than throws on this
    // in-memory driver).
  });
}
