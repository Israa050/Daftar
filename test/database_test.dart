import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/core/database/default_categories.dart';
import 'package:stockflow/features/categories/data/daos/categories_dao.dart';
import 'package:stockflow/features/transactions/data/daos/transactions_dao.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:uuid/uuid.dart';

void main() {
  late AppDatabase db;
  late TransactionsDao dataSource;
  late CategoriesDao categoriesDao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dataSource = db.transactionsDao;
    categoriesDao = db.categoriesDao;
  });

  tearDown(() async {
    await db.close();
  });

  TransactionsCompanion buildEntry({
    required String id,
    int amountMinor = 100,
    TransactionType type = TransactionType.expense,
    Value<String?> note = const Value.absent(),
    Value<DateTime> occurredTime = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
  }) {
    return TransactionsCompanion.insert(
      id: id,
      amountMinor: amountMinor,
      type: type,
      note: note,
      occurredTime: occurredTime,
      categoryId: categoryId,
    );
  }

  CategoriesCompanion buildCategory({
    required String id,
    String name = 'Category',
    Value<String?> colorHex = const Value.absent(),
  }) {
    return CategoriesCompanion.insert(id: id, name: name, colorHex: colorHex);
  }

  group('Test Drift', () {
    group('addTransaction', () {
      test('basic insert + read-back via allTransactions', () async {
        String id = Uuid().v4();
        await dataSource.insertOne(
          buildEntry(
            id: id,
            amountMinor: 50,
            note: Value('Some note'),
            type: TransactionType.expense,
            occurredTime: Value(DateTime.now()),
          ),
        );
        final result = await dataSource.watchAll().first;
        expect(result[0].id, id);
        expect(result[0].amountMinor, 50);
        expect(result[0].note, 'Some note');
        expect(result[0].type, TransactionType.expense);
      });
      test('note omitted -> stored as null', () async {
        String id = Uuid().v4();
        await dataSource.insertOne(
          buildEntry(
            id: id,
            amountMinor: 50,
            type: TransactionType.expense,
            occurredTime: Value(DateTime.now()),
          ),
        );
        final result = await dataSource.watchAll().first;
        expect(result[0].note, null);
      });

      test(
        'occurredTime and creationTime auto-populate when omitted',
        () async {
          final before = DateTime.now();
          final id = const Uuid().v4();
          await dataSource.insertOne(buildEntry(id: id));
          final after = DateTime.now();

          final result = (await dataSource.watchAll().first).single;
          expect(
            result.occurredTime.isAfter(
              before.subtract(const Duration(seconds: 1)),
            ),
            isTrue,
          );
          expect(
            result.occurredTime.isBefore(after.add(const Duration(seconds: 1))),
            isTrue,
          );
          expect(
            result.creationTime.isAfter(
              before.subtract(const Duration(seconds: 1)),
            ),
            isTrue,
          );
          expect(
            result.creationTime.isBefore(after.add(const Duration(seconds: 1))),
            isTrue,
          );
        },
      );

      test(
        'explicit occurredTime overrides the default (backdating)',
        () async {
          final id = const Uuid().v4();
          final backdated = DateTime(2020, 1, 1);
          await dataSource.insertOne(
            buildEntry(id: id, occurredTime: Value(backdated)),
          );

          final result = (await dataSource.watchAll().first).single;
          expect(result.occurredTime, backdated);
        },
      );

      test(
        'type round-trips as TransactionType enum, not a raw string',
        () async {
          final incomeId = const Uuid().v4();
          final expenseId = const Uuid().v4();
          await dataSource.insertOne(
            buildEntry(id: incomeId, type: TransactionType.income),
          );
          await dataSource.insertOne(
            buildEntry(id: expenseId, type: TransactionType.expense),
          );

          final result = await dataSource.watchAll().first;
          final income = result.firstWhere((t) => t.id == incomeId);
          final expense = result.firstWhere((t) => t.id == expenseId);
          expect(income.type, TransactionType.income);
          expect(expense.type, TransactionType.expense);
        },
      );

      test('duplicate id throws; distinct ids both succeed', () async {
        final id = const Uuid().v4();
        await dataSource.insertOne(buildEntry(id: id));

        expect(
          () => dataSource.insertOne(buildEntry(id: id)),
          throwsA(anything),
        );

        await dataSource.insertOne(buildEntry(id: const Uuid().v4()));
        final result = await dataSource.watchAll().first;
        expect(result.length, 2);
      });

      test('amountMinor stores exact integer values', () async {
        final id = const Uuid().v4();
        await dataSource.insertOne(buildEntry(id: id, amountMinor: 350));

        final result = (await dataSource.watchAll().first).single;
        expect(result.amountMinor, 350);
      });
    });

    group('deleteTransaction', () {
      test('deleting an existing id removes exactly that row', () async {
        final keepId = const Uuid().v4();
        final removeId = const Uuid().v4();
        await dataSource.insertOne(buildEntry(id: keepId));
        await dataSource.insertOne(buildEntry(id: removeId));

        await dataSource.deleteById(removeId);

        final result = await dataSource.watchAll().first;
        expect(result.length, 1);
        expect(result.single.id, keepId);
      });

      test('return value equals number of rows deleted (1)', () async {
        final id = const Uuid().v4();
        await dataSource.insertOne(buildEntry(id: id));

        final deletedCount = await dataSource.deleteById(id);
        expect(deletedCount, 1);
      });

      test('deleting a non-existent id returns 0, does not throw', () async {
        final deletedCount = await dataSource.deleteById(const Uuid().v4());
        expect(deletedCount, 0);
      });
    });

    group('allTransactions', () {
      test('empty table returns []', () async {
        final result = await dataSource.watchAll().first;
        expect(result, isEmpty);
      });

      test(
        'multiple inserted rows are all present (order-independent)',
        () async {
          final ids = [const Uuid().v4(), const Uuid().v4(), const Uuid().v4()];
          for (final id in ids) {
            await dataSource.insertOne(buildEntry(id: id));
          }

          final result = await dataSource.watchAll().first;
          expect(result.map((t) => t.id).toSet(), ids.toSet());
        },
      );

      test('reflects state after a mix of inserts and deletes', () async {
        final keepId = const Uuid().v4();
        final removeId = const Uuid().v4();
        await dataSource.insertOne(buildEntry(id: keepId));
        await dataSource.insertOne(buildEntry(id: removeId));

        await dataSource.deleteById(removeId);

        final result = await dataSource.watchAll().first;
        expect(result.length, 1);
        expect(result.single.id, keepId);
      });

      test(
        'emits() an updated list when a row is inserted after subscribing',
        () async {
          final id = const Uuid().v4();
          expectLater(
            dataSource.watchAll(),
            emitsInOrder([
              isEmpty,
              predicate<List<Transaction>>(
                (list) => list.length == 1 && list.single.id == id,
              ),
            ]),
          );
          await Future<void>.delayed(Duration.zero);
          await dataSource.insertOne(buildEntry(id: id));
        },
      );
    });

    group('balance', () {
      test('empty table -> 0', () async {
        final result = await dataSource.watchBalance().first;
        expect(result, 0);
      });

      test('income only -> sum of amountMinor', () async {
        await dataSource.insertOne(
          buildEntry(
            id: const Uuid().v4(),
            amountMinor: 500,
            type: TransactionType.income,
          ),
        );
        await dataSource.insertOne(
          buildEntry(
            id: const Uuid().v4(),
            amountMinor: 250,
            type: TransactionType.income,
          ),
        );

        final result = await dataSource.watchBalance().first;
        expect(result, 750);
      });

      test('income minus expense -> net balance', () async {
        await dataSource.insertOne(
          buildEntry(
            id: const Uuid().v4(),
            amountMinor: 1000,
            type: TransactionType.income,
          ),
        );
        await dataSource.insertOne(
          buildEntry(
            id: const Uuid().v4(),
            amountMinor: 350,
            type: TransactionType.expense,
          ),
        );

        final result = await dataSource.watchBalance().first;
        expect(result, 650);
      });

      test('expense exceeding income -> negative balance', () async {
        await dataSource.insertOne(
          buildEntry(
            id: const Uuid().v4(),
            amountMinor: 100,
            type: TransactionType.income,
          ),
        );
        await dataSource.insertOne(
          buildEntry(
            id: const Uuid().v4(),
            amountMinor: 400,
            type: TransactionType.expense,
          ),
        );

        final result = await dataSource.watchBalance().first;
        expect(result, -300);
      });

      test('matches the sum computed from allTransactions', () async {
        final entries = [
          (amountMinor: 500, type: TransactionType.income),
          (amountMinor: 120, type: TransactionType.expense),
          (amountMinor: 75, type: TransactionType.expense),
          (amountMinor: 900, type: TransactionType.income),
        ];
        for (final entry in entries) {
          await dataSource.insertOne(
            buildEntry(
              id: const Uuid().v4(),
              amountMinor: entry.amountMinor,
              type: entry.type,
            ),
          );
        }

        final rows = await dataSource.watchAll().first;
        final expected = rows.fold<int>(
          0,
          (sum, t) =>
              sum +
              (t.type == TransactionType.income
                  ? t.amountMinor
                  : -t.amountMinor),
        );

        final result = await dataSource.watchBalance().first;
        expect(result, expected);
      });

      test(
        'emits() an updated total when a row is inserted after subscribing',
        () async {
          expectLater(dataSource.watchBalance(), emitsInOrder([0, 500]));
          await Future<void>.delayed(Duration.zero);
          await dataSource.insertOne(
            buildEntry(
              id: const Uuid().v4(),
              amountMinor: 500,
              type: TransactionType.income,
            ),
          );
        },
      );
    });

    // Every test in this group runs against a database that already has
    // the 4 seeded default categories from onCreate (unlike Transactions,
    // which starts genuinely empty) -- so assertions filter down to the
    // ids created within the test rather than assuming an empty table.
    group('Categories', () {
      group('addCategory', () {
        test('basic insert + read-back via watchAllCategories', () async {
          final id = const Uuid().v4();
          await categoriesDao.insertOne(
            buildCategory(
              id: id,
              name: 'Food',
              colorHex: const Value('#FF0000'),
            ),
          );

          final result = await categoriesDao.watchAll().first;
          final inserted = result.singleWhere((c) => c.id == id);
          expect(inserted.name, 'Food');
          expect(inserted.colorHex, '#FF0000');
        });

        test('colorHex omitted -> stored as null', () async {
          final id = const Uuid().v4();
          await categoriesDao.insertOne(buildCategory(id: id, name: 'Food'));

          final result = await categoriesDao.watchAll().first;
          expect(result.singleWhere((c) => c.id == id).colorHex, null);
        });

        test('duplicate id throws; distinct ids both succeed', () async {
          final id = const Uuid().v4();
          await categoriesDao.insertOne(buildCategory(id: id));

          expect(
            () => categoriesDao.insertOne(buildCategory(id: id)),
            throwsA(anything),
          );

          final secondId = const Uuid().v4();
          await categoriesDao.insertOne(buildCategory(id: secondId));
          final result = await categoriesDao.watchAll().first;
          expect(result.map((c) => c.id), containsAll([id, secondId]));
        });
      });

      group('updateCategory', () {
        test('replaces name and colorHex for a matching id', () async {
          final id = const Uuid().v4();
          await categoriesDao.insertOne(
            buildCategory(
              id: id,
              name: 'Food',
              colorHex: const Value('#FF0000'),
            ),
          );

          await categoriesDao.updateOne(
            CategoriesCompanion(
              id: Value(id),
              name: const Value('Groceries'),
              colorHex: const Value('#00FF00'),
            ),
          );

          final result = await categoriesDao.watchAll().first;
          final updated = result.singleWhere((c) => c.id == id);
          expect(updated.name, 'Groceries');
          expect(updated.colorHex, '#00FF00');
        });

        test('non-existent id -> returns false, no row created', () async {
          final ghostId = const Uuid().v4();
          final updated = await categoriesDao.updateOne(
            CategoriesCompanion(
              id: Value(ghostId),
              name: const Value('Ghost'),
              colorHex: const Value.absent(),
            ),
          );

          expect(updated, isFalse);
          final result = await categoriesDao.watchAll().first;
          expect(result.where((c) => c.id == ghostId), isEmpty);
        });
      });

      group('deleteCategory', () {
        test('deleting an existing id removes exactly that row', () async {
          final keepId = const Uuid().v4();
          final removeId = const Uuid().v4();
          await categoriesDao.insertOne(buildCategory(id: keepId));
          await categoriesDao.insertOne(buildCategory(id: removeId));

          await categoriesDao.deleteById(removeId);

          final result = await categoriesDao.watchAll().first;
          expect(result.where((c) => c.id == removeId), isEmpty);
          expect(result.where((c) => c.id == keepId).length, 1);
        });

        test('deleting a non-existent id returns 0, does not throw', () async {
          final deletedCount = await categoriesDao.deleteById(
            const Uuid().v4(),
          );
          expect(deletedCount, 0);
        });

        test(
          'deleting a category referenced by a transaction sets '
          'categoryId to null instead of failing (ON DELETE SET NULL)',
          () async {
            final categoryId = const Uuid().v4();
            final transactionId = const Uuid().v4();
            await categoriesDao.insertOne(buildCategory(id: categoryId));
            await dataSource.insertOne(
              buildEntry(id: transactionId, categoryId: Value(categoryId)),
            );

            await categoriesDao.deleteById(categoryId);

            final categories = await categoriesDao.watchAll().first;
            expect(categories.where((c) => c.id == categoryId), isEmpty);

            final transactions = await dataSource.watchAll().first;
            final orphaned = transactions.singleWhere(
              (t) => t.id == transactionId,
            );
            expect(orphaned.categoryId, null);
          },
        );

        test('deleting a category with no transactions attached succeeds '
            'immediately (baseline for the orphaning test above)', () async {
          final categoryId = const Uuid().v4();
          await categoriesDao.insertOne(buildCategory(id: categoryId));

          final deletedCount = await categoriesDao.deleteById(categoryId);

          expect(deletedCount, 1);
        });
      });

      group('findCategoryByName', () {
        test('existing name -> returns the matching row', () async {
          final id = const Uuid().v4();
          await categoriesDao.insertOne(
            buildCategory(id: id, name: 'A Unique Category Name'),
          );

          final result = await categoriesDao.findByName(
            'A Unique Category Name',
          );

          expect(result?.id, id);
        });

        test('no matching name -> returns null', () async {
          final result = await categoriesDao.findByName('Nonexistent');
          expect(result, null);
        });
      });

      group('watchAllCategories', () {
        test(
          'a fresh database already contains the 4 seeded default categories',
          () async {
            final result = await categoriesDao.watchAll().first;
            expect(result.map((c) => c.id), [
              defaultCategoryFoodId,
              defaultCategoryTransportId,
              defaultCategoryShoppingId,
              defaultCategoryBillsId,
            ]);
          },
        );

        test(
          'emits() an updated list when a row is inserted after subscribing',
          () async {
            final id = const Uuid().v4();
            expectLater(
              categoriesDao.watchAll(),
              emitsInOrder([
                predicate<List<Category>>((list) => list.length == 4),
                predicate<List<Category>>(
                  (list) => list.length == 5 && list.any((c) => c.id == id),
                ),
              ]),
            );
            await Future<void>.delayed(Duration.zero);
            await categoriesDao.insertOne(buildCategory(id: id));
          },
        );
      });
    });
  });
}
