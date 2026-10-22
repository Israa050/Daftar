import 'package:flutter/material.dart';
import 'package:stockflow/core/theme/app_colors.dart';
import 'package:stockflow/features/categories/domain/entities/category_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:stockflow/features/transactions/presentation/format.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.onDelete,
    this.category,
  });

  final TransactionEntity transaction;
  final VoidCallback onDelete;
  final CategoryEntity? category;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isIncome = transaction.type == TransactionType.income;
    final color = isIncome ? colors.income : colors.expense;
    final wash = isIncome ? colors.incomeWash : colors.expenseWash;
    final sign = isIncome ? '+' : '-';
    final categoryColor = parseHexColor(category?.colorHex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Dismissible(
        key: ValueKey(transaction.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: colors.expenseWash,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Icon(Icons.delete_outline, color: colors.expense),
        ),
        onDismissed: (_) => onDelete(),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.lineSoft),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(
                  isIncome
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            transaction.note?.isNotEmpty == true
                                ? transaction.note!
                                : (isIncome ? 'Income' : 'Expense'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (category != null) ...[
                          const SizedBox(width: 6),
                          _CategoryPill(
                            name: category!.name,
                            color: categoryColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      formatDate(transaction.timestamp),
                      style: TextStyle(fontSize: 11.5, color: colors.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '\u200E$sign${formatAmountMinor(transaction.amountMinor)}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.name, required this.color});

  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: colors.lineSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color ?? colors.inkFaint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
