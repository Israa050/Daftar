import 'package:flutter/material.dart';
import 'package:stockflow/features/categories/domain/entities/category_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_entity.dart';
import 'package:stockflow/features/transactions/presentation/widgets/transaction_tile.dart';
import 'package:stockflow/features/transactions/presentation/widgets/transactions_empty_state.dart';

/// Sliver list of transactions, or an empty-state placeholder when [data] is
/// empty. Meant to sit inside the home screen's [CustomScrollView], so the
/// whole page scrolls as one.
class TransactionsList extends StatelessWidget {
  const TransactionsList({
    super.key,
    required this.data,
    required this.onDelete,
    required this.categories,
  });

  final List<TransactionEntity> data;
  final ValueChanged<TransactionEntity> onDelete;
  final List<CategoryEntity> categories;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: TransactionsEmptyState(),
      );
    }

    final categoriesById = {for (final c in categories) c.id: c};

    return SliverPadding(
      // Extra bottom space so the last row can scroll above the add button.
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      sliver: SliverList.separated(
        itemCount: data.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final transaction = data[index];
          return TransactionTile(
            transaction: transaction,
            onDelete: () => onDelete(transaction),
            category: categoriesById[transaction.categoryId],
          );
        },
      ),
    );
  }
}
