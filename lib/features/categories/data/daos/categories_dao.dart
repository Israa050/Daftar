import 'package:drift/drift.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/features/categories/data/dtos/category_total_row.dart';
import 'package:stockflow/features/categories/data/models/categories.dart';
import 'package:stockflow/features/transactions/data/models/transactions.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';

part 'categories_dao.g.dart';

/// All category queries, including the per-category spending totals (which join
/// transactions, hence both tables are declared).
@DriftAccessor(tables: [Categories, Transactions])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Stream<List<Category>> watchAll() => select(categories).watch();

  // One-shot read (vs. [watchAll]) -- used by the export/backup feature.
  Future<List<Category>> getAllOnce() => select(categories).get();

  Future<int> insertOne(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  Future<Category?> findById(String id) {
    return (select(
      categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsert(CategoriesCompanion entry) {
    return into(categories).insertOnConflictUpdate(entry);
  }

  Future<int> deleteById(String id) {
    return (delete(categories)..where((c) => c.id.equals(id))).go();
  }

  Future<bool> updateOne(CategoriesCompanion entry) {
    return update(categories).replace(entry);
  }

  Future<Category?> findByName(String name) {
    // .equals() is case-sensitive (SQLite's default BINARY collation), but
    // duplicate-name checks in the repository are meant to be
    // case-insensitive, so compare lowercased on both sides.
    return (select(categories)
          ..where((c) => c.name.lower().equals(name.toLowerCase())))
        .getSingleOrNull();
  }

  Stream<List<CategoryTotalRow>> watchExpenseTotals() {
    final total = transactions.amountMinor.sum();

    final query = selectOnly(transactions)
      ..addColumns([categories.id, categories.name, categories.colorHex, total])
      ..join([
        leftOuterJoin(
          categories,
          categories.id.equalsExp(transactions.categoryId),
        ),
      ])
      ..where(transactions.type.equalsValue(TransactionType.expense))
      ..groupBy([transactions.categoryId]);

    return query.watch().map(
      (rows) => [for (final row in rows) _toTotalRow(row, total)],
    );
  }

  CategoryTotalRow _toTotalRow(TypedResult row, Expression<int> total) {
    return CategoryTotalRow(
      categoryId: row.read(categories.id),
      categoryName: row.read(categories.name),
      colorHex: row.read(categories.colorHex),
      totalMinor: row.read(total) ?? 0,
    );
  }
}
