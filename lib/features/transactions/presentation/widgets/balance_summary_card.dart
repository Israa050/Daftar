import 'package:flutter/material.dart';
import 'package:stockflow/core/extensions/motion_extension.dart';
import 'package:stockflow/core/theme/app_colors.dart';
import 'package:stockflow/core/theme/app_theme.dart';
import 'package:stockflow/features/transactions/presentation/format.dart';
import 'package:stockflow/features/transactions/presentation/widgets/stat_pill.dart';

/// Balance card at the top of the transactions screen: current balance
/// plus income/expense stat pills, styled after the approved design.
class BalanceSummaryCard extends StatelessWidget {
  const BalanceSummaryCard({
    super.key,
    required this.income,
    required this.expense,
  });

  final int income;
  final int expense;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final balance = income - expense;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.lineSoft),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [colors.accentWash, colors.surfaceRaised],
            stops: const [0.0, 0.7],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BALANCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: colors.inkFaint,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: context.motion(const Duration(milliseconds: 200)),
              child: Text(
                formatAmountMinor(balance),
                // The key tells AnimatedSwitcher this is a new value to
                // cross-fade to; without it the text would just swap.
                key: ValueKey(balance),
                style: TextStyle(
                  fontFamily: appDisplayFontFamily,
                  fontSize: 34,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                  color: colors.ink,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatPill(
                    icon: Icons.arrow_downward_rounded,
                    iconColor: colors.income,
                    iconWash: colors.incomeWash,
                    label: 'Income',
                    amountMinor: income,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatPill(
                    icon: Icons.arrow_upward_rounded,
                    iconColor: colors.expense,
                    iconWash: colors.expenseWash,
                    label: 'Expense',
                    amountMinor: expense,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
