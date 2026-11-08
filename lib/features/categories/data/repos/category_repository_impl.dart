import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/core/timestamps.dart';
import 'package:stockflow/core/sync/domain/entities/operation_type.dart';
import 'package:stockflow/core/database/app_database.dart';
import 'package:stockflow/core/sync/domain/repositories/sync_queue_repository.dart';
import 'package:stockflow/features/categories/data/daos/categories_dao.dart';
import 'package:stockflow/features/categories/data/dtos/category_total_row.dart';
import 'package:stockflow/features/categories/domain/entities/category_entity.dart';
import 'package:stockflow/features/categories/domain/entities/category_total_entity.dart';
import 'package:stockflow/features/categories/domain/repositories/category_repository.dart';
import 'package:uuid/uuid.dart';

class CategoryRepositoryImpl extends CategoryRepository {
  // [db] is held for transaction() -- see TransactionsRepositoryImpl: the
  // local write and its sync-queue row commit atomically across this DAO and
  // the sync queue.
  final AppDatabase db;
  final CategoriesDao dao;
  final SyncQueueRepository syncQueueRepository;

  CategoryRepositoryImpl({
    required this.db,
    required this.dao,
    required this.syncQueueRepository,
  });

  CategoryEntity _toEntity(Category category) {
    return CategoryEntity(
      id: category.id,
      name: category.name,
      colorHex: category.colorHex,
    );
  }

  @override
  Stream<List<CategoryEntity>> watchCategories() {
    return dao.watchAll().map((rows) => rows.map(_toEntity).toList());
  }

  @override
  Future<List<CategoryEntity>> getAllCategoriesOnce() async {
    final rows = await dao.getAllOnce();
    return rows.map(_toEntity).toList();
  }

  @override
  Stream<List<CategoryTotalEntity>> watchCategoryTotals() {
    return dao.watchExpenseTotals().map(
      (rows) => rows.map(_toCategoryTotalEntity).toList(),
    );
  }

  CategoryTotalEntity _toCategoryTotalEntity(CategoryTotalRow row) {
    return CategoryTotalEntity(
      id: row.categoryId ?? 'Uncategorized',
      name: row.categoryName ?? 'Uncategorized',
      colorHex: row.colorHex,
      totalMinor: row.totalMinor,
    );
  }

  @override
  Future<Result<void>> addCategory({
    required String name,
    String? colorHex,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const Failure('Category name cannot be empty');
    }

    final existing = await getCategoryByName(trimmedName);
    if (existing != null) {
      return const Failure('A category with this name already exists');
    }

    final id = const Uuid().v4();
    final now = nowForSync();
    final entry = CategoriesCompanion.insert(
      id: id,
      name: trimmedName,
      colorHex: Value(colorHex),
      updatedAt: Value(now),
    );

    final payload = jsonEncode({
      'id': id,
      'name': trimmedName,
      'colorHex': colorHex,
      'updatedAt': now.toIso8601String(),
    });

    try {
      await db.transaction(() async {
        await dao.insertOne(entry);
        final queued = await syncQueueRepository.enqueue(
          entityType: 'category',
          entityId: id,
          operation: OperationType.create,
          payload: payload,
        );

        // See TransactionsRepositoryImpl.addTransaction: a Failure must be
        // re-thrown to trigger Drift's rollback, then converted back to
        // Result below.
        if (queued case Failure(:final message)) {
          throw Exception(message);
        }
      });
      return const Success(null);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  @override
  Future<Result<int>> deleteCategory(String id) async {
    try {
      final result = await db.transaction(() async {
        final count = await dao.deleteById(id);
        final queued = await syncQueueRepository.enqueue(
          entityType: 'category',
          entityId: id,
          operation: OperationType.delete,
          payload: jsonEncode({'id': id}),
        );

        if (queued case Failure(:final message)) {
          throw Exception(message);
        }
        return count;
      });
      return Success(result);
    } catch (e) {
      return Failure(e.toString());
    }
  }

  @override
  Future<CategoryEntity?> getCategoryByName(String name) async {
    final row = await dao.findByName(name);
    return row == null ? null : _toEntity(row);
  }

  @override
  Future<Result<void>> updateCategory({
    required String id,
    required String name,
    String? colorHex,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return const Failure('Category name cannot be empty');
    }

    final existing = await getCategoryByName(trimmedName);
    if (existing != null && existing.id != id) {
      return const Failure('A category with this name already exists');
    }

    final now = nowForSync();
    final entry = CategoriesCompanion(
      id: Value(id),
      name: Value(trimmedName),
      colorHex: Value(colorHex),
      updatedAt: Value(now),
    );

    final payload = jsonEncode({
      'id': id,
      'name': trimmedName,
      'colorHex': colorHex,
      'updatedAt': now.toIso8601String(),
    });

    try {
      await db.transaction(() async {
        await dao.updateOne(entry);
        final queued = await syncQueueRepository.enqueue(
          entityType: 'category',
          entityId: id,
          operation: OperationType.update,
          payload: payload,
        );

        if (queued case Failure(:final message)) {
          throw Exception(message);
        }
      });
      return const Success(null);
    } catch (e) {
      return Failure(e.toString());
    }
  }
}
