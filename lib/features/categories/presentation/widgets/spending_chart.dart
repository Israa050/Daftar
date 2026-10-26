import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:stockflow/core/theme/app_colors.dart';
import 'package:stockflow/features/categories/domain/entities/category_total_entity.dart';
import 'package:stockflow/features/transactions/presentation/format.dart';

class SpendingChart extends StatelessWidget {
  const SpendingChart({super.key, required this.totals});
  final List<CategoryTotalEntity> totals;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (!totals.any((t) => t.totalMinor > 0)) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text(
            'No spending yet',
            style: TextStyle(fontSize: 12.5, color: colors.inkFaint),
          ),
        ),
      );
    }
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final ordered = isRtl ? totals.reversed.toList() : totals;

    final groups = [
      for (var i = 0; i < ordered.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: ordered[i].totalMinor.toDouble(),
              color: parseHexColor(ordered[i].colorHex) ?? colors.inkFaint,
              width: 18,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
    ];
    final maxMinor = ordered.fold<int>(
      0,
      (m, t) => t.totalMinor > m ? t.totalMinor : m,
    );
    final maxY = maxMinor * 1.1;

    // No value axis: the rows below the chart give every exact amount, and
    // tapping a bar shows its tooltip.
    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      bottomTitles: const AxisTitles(),
      leftTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
    );

    final touch = BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final t = ordered[groupIndex];
          return BarTooltipItem(
            '${t.name}\n${formatAmountMinor(t.totalMinor)}',
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            textDirection: Directionality.of(context),
          );
        },
      ),
    );

    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          barGroups: groups,
          titlesData: titles,
          barTouchData: touch,
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}
