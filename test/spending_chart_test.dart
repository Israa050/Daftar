import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/theme/app_theme.dart';
import 'package:stockflow/features/categories/domain/entities/category_total_entity.dart';
import 'package:stockflow/features/categories/presentation/widgets/spending_chart.dart';

CategoryTotalEntity _total(String name, int minor) => CategoryTotalEntity(
  id: name,
  name: name,
  colorHex: '#FF5722',
  totalMinor: minor,
);

Widget _wrap(
  List<CategoryTotalEntity> totals, {
  TextDirection direction = TextDirection.ltr,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: SpendingChart(totals: totals)),
    ),
  );
}

/// The bar heights, in the order the chart draws them (left to right).
List<double> _barHeights(WidgetTester tester) {
  final chart = tester.widget<BarChart>(find.byType(BarChart));
  return chart.data.barGroups.map((g) => g.barRods.single.toY).toList();
}

void main() {
  group('SpendingChart', () {
    testWidgets('an empty list shows the empty state and no chart', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const []));

      expect(find.text('No spending yet'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('totals that are all zero also show the empty state', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap([_total('Food', 0), _total('Bills', 0)]));

      expect(find.text('No spending yet'), findsOneWidget);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('two totals draw two bars, largest first', (tester) async {
      await tester.pumpWidget(
        _wrap([_total('Food', 1200), _total('Bills', 500)]),
      );

      expect(find.text('No spending yet'), findsNothing);
      expect(find.byType(BarChart), findsOneWidget);
      expect(_barHeights(tester), [1200.0, 500.0]);
    });

    testWidgets(
      'right-to-left reverses the bars so the largest is on the right',
      (tester) async {
        await tester.pumpWidget(
          _wrap([
            _total('Food', 1200),
            _total('Bills', 500),
          ], direction: TextDirection.rtl),
        );

        expect(_barHeights(tester), [500.0, 1200.0]);
      },
    );
  });
}
