import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/theme/app_colors.dart';
import 'package:stockflow/features/categories/bloc/category_totals_cubit.dart';
import 'package:stockflow/features/categories/domain/entities/category_total_entity.dart';
import 'package:stockflow/features/categories/presentation/widgets/spending_chart.dart';
import 'package:stockflow/features/transactions/presentation/format.dart';

/// Card showing total expense per category, reactively updated from
/// [CategoryTotalsCubit]. Styled to match [BalanceSummaryCard]. Collapsible
/// to free up vertical space for the transaction list below it.
class CategoryTotalsCard extends StatefulWidget {
  const CategoryTotalsCard({super.key});

  @override
  State<CategoryTotalsCard> createState() => _CategoryTotalsCardState();
}

class _CategoryTotalsCardState extends State<CategoryTotalsCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: EdgeInsets.fromLTRB(18, 16, 18, _expanded ? 8 : 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.lineSoft),
          color: colors.surfaceRaised,
        ),
        child: BlocBuilder<CategoryTotalsCubit, List<CategoryTotalEntity>>(
          builder: (context, totals) {
            final sorted = [...totals]
              ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));

            final grandTotal = sorted.fold<int>(
              0,
              (sum, t) => sum + t.totalMinor,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SPENDING BY CATEGORY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                          color: colors.inkFaint,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            formatAmountMinor(grandTotal),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.inkSoft,
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: colors.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_expanded
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            if (sorted.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Text(
                                  'No expenses yet',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.inkFaint,
                                  ),
                                ),
                              )
                            else ...[
                              SpendingChart(totals: sorted),
                              const SizedBox(height: 8),
                              ...sorted.map(
                                (entity) => _CategoryTotalRow(
                                  entity: entity,
                                  maxTotalMinor: sorted.first.totalMinor,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryTotalRow extends StatelessWidget {
  const _CategoryTotalRow({required this.entity, required this.maxTotalMinor});

  final CategoryTotalEntity entity;
  final int maxTotalMinor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = parseHexColor(entity.colorHex);
    final name = entity.name;
    final fraction = maxTotalMinor == 0
        ? 0.0
        : entity.totalMinor / maxTotalMinor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsetsDirectional.only(end: 10),
            decoration: color == null
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.inkFaint, width: 1.5),
                  )
                : BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(
            width: 84,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: color == null ? FontWeight.w500 : FontWeight.w600,
                fontStyle: color == null ? FontStyle.italic : FontStyle.normal,
                color: color == null ? colors.inkFaint : colors.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: colors.lineSoft,
                valueColor: AlwaysStoppedAnimation(color ?? colors.inkFaint),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              formatAmountMinor(entity.totalMinor),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.expense,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
