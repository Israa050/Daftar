import 'package:drift/drift.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/features/transactions/data/models/transactions.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';

part 'transactions_dao.g.dart';

/// All transaction-table queries. A [DatabaseAccessor] shares [AppDatabase]'s
/// executor, so calls made inside `db.transaction(...)` join that transaction.
@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  // Newest first -- shared by the stream and the one-shot read so the ordering
  // is defined once.
  SimpleSelectStatement<$TransactionsTable, Transaction> _newestFirst() {
    return select(transactions)..orderBy([
      (t) => OrderingTerm(expression: t.occurredTime, mode: OrderingMode.desc),
    ]);
  }

  Stream<List<Transaction>> watchAll() => _newestFirst().watch();

  // One-shot read (vs. [watchAll]) -- used by the export/backup feature, which
  // needs a single snapshot rather than a live subscription.
  Future<List<Transaction>> getAllOnce() => _newestFirst().get();

  Future<int> insertOne(TransactionsCompanion entry) {
    return into(transactions).insert(entry);
  }

  Future<Transaction?> findById(String id) {
    return (select(
      transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsert(TransactionsCompanion entry) {
    return into(transactions).insertOnConflictUpdate(entry);
  }

  Future<int> deleteById(String id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  Stream<int> watchBalance() {
    final incomeSum = transactions.amountMinor.sum(
      filter: transactions.type.equalsValue(TransactionType.income),
    );
    final expenseSum = transactions.amountMinor.sum(
      filter: transactions.type.equalsValue(TransactionType.expense),
    );
    final query = selectOnly(transactions)..addColumns([incomeSum, expenseSum]);
    return query.watchSingle().map((row) {
      final income = row.read(incomeSum) ?? 0;
      final expense = row.read(expenseSum) ?? 0;
      return income - expense;
    });
  }
}
