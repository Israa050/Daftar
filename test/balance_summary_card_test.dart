import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/theme/app_theme.dart';
import 'package:stockflow/features/transactions/presentation/format.dart';
import 'package:stockflow/features/transactions/presentation/widgets/balance_summary_card.dart';

// Chosen so the balance never equals an income or expense pill, which would
// make the text finders match more than one widget:
//   1000 - 300 = 700,  then  1000 - 100 = 900.
const _income = 1000;

Widget _card({required int expense, required bool disableAnimations}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(
          body: BalanceSummaryCard(income: _income, expense: expense),
        ),
      ),
    ),
  );
}

void main() {
  final before = find.text(formatAmountMinor(700));
  final after = find.text(formatAmountMinor(900));

  group('BalanceSummaryCard balance animation', () {
    testWidgets('shows the balance', (tester) async {
      await tester.pumpWidget(_card(expense: 300, disableAnimations: false));

      expect(before, findsOneWidget);
    });

    testWidgets('cross-fades from the old balance to the new one', (
      tester,
    ) async {
      await tester.pumpWidget(_card(expense: 300, disableAnimations: false));
      await tester.pumpWidget(_card(expense: 100, disableAnimations: false));

      // Part-way through the transition both values are on screen.
      await tester.pump(const Duration(milliseconds: 100));
      expect(before, findsOneWidget);
      expect(after, findsOneWidget);

      // Once it settles only the new balance is left.
      await tester.pumpAndSettle();
      expect(before, findsNothing);
      expect(after, findsOneWidget);
    });

    testWidgets(
      'with reduced motion the new balance replaces the old at once',
      (tester) async {
        await tester.pumpWidget(_card(expense: 300, disableAnimations: true));
        await tester.pumpWidget(_card(expense: 100, disableAnimations: true));
        await tester.pump();

        expect(after, findsOneWidget);
        expect(before, findsNothing);
      },
    );
  });
}
