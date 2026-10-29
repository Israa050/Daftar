import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stockflow/core/theme/app_theme.dart';
import 'package:stockflow/features/categories/domain/entities/category_entity.dart';
import 'package:stockflow/features/transactions/bloc/transactions_bloc.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:stockflow/features/transactions/presentation/widgets/add_transaction_sheet.dart';

class _MockTransactionsBloc
    extends MockBloc<TransactionsEvent, TransactionsState>
    implements TransactionsBloc {}

final _categories = [
  CategoryEntity(id: 'food', name: 'Food', colorHex: '#FF9800'),
  CategoryEntity(id: 'bills', name: 'Bills', colorHex: '#F44336'),
];

void main() {
  late _MockTransactionsBloc bloc;
  late StreamController<TransactionsState> states;

  setUpAll(() => registerFallbackValue(AppLaunchEvent()));

  setUp(() {
    bloc = _MockTransactionsBloc();
    states = StreamController<TransactionsState>.broadcast();
  });

  tearDown(() => states.close());

  /// Opens the sheet through its real entry point, [showAddTransactionSheet].
  Future<void> openSheet(
    WidgetTester tester, {
    List<CategoryEntity> categories = const [],
  }) async {
    whenListen(
      bloc,
      states.stream,
      initialState: Loaded(data: const [], categories: categories),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: BlocProvider<TransactionsBloc>.value(
          value: bloc,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddTransactionSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder amountField() => find.widgetWithText(TextFormField, 'Amount');
  Finder noteField() => find.widgetWithText(TextFormField, 'Note (optional)');

  /// Every AddTransactionEvent the sheet sent to the bloc. verify() fails when
  /// there were no calls, so use [expectNothingSent] for that case.
  List<AddTransactionEvent> sentEvents() => verify(
    () => bloc.add(captureAny()),
  ).captured.whereType<AddTransactionEvent>().toList();

  void expectNothingSent() =>
      verifyNever(() => bloc.add(any(that: isA<AddTransactionEvent>())));

  group('AddTransactionSheet', () {
    testWidgets('shows the form: type, amount, note and Save', (tester) async {
      await openSheet(tester);

      expect(find.text('Add transaction'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(amountField(), findsOneWidget);
      expect(noteField(), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows no category chips when there are no categories', (
      tester,
    ) async {
      await openSheet(tester);

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('lists each category as a chip', (tester) async {
      await openSheet(tester, categories: _categories);

      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Bills'), findsOneWidget);
    });

    testWidgets('an empty amount is rejected and nothing is sent', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter an amount'), findsOneWidget);
      expectNothingSent();
    });

    testWidgets('an invalid amount is rejected and nothing is sent', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.enterText(amountField(), 'abc');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.text('Enter a valid positive amount'), findsOneWidget);
      expectNothingSent();
    });

    testWidgets('a valid amount sends an expense in minor units', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.enterText(amountField(), '12.50');
      await tester.tap(find.text('Save'));
      await tester.pump();

      final event = sentEvents().single;
      expect(event.amountMinor, 1250);
      expect(event.type, TransactionType.expense);
      expect(event.note, isNull);
      expect(event.categoryId, isNull);
    });

    testWidgets('sends the chosen type, trimmed note and category', (
      tester,
    ) async {
      await openSheet(tester, categories: _categories);

      await tester.tap(find.text('Income'));
      await tester.pump();
      await tester.tap(find.text('Bills'));
      await tester.pump();
      await tester.enterText(amountField(), '300');
      await tester.enterText(noteField(), '  Rent refund  ');
      await tester.tap(find.text('Save'));
      await tester.pump();

      final event = sentEvents().single;
      expect(event.amountMinor, 30000);
      expect(event.type, TransactionType.income);
      expect(event.note, 'Rent refund');
      expect(event.categoryId, 'bills');
    });

    testWidgets('tapping a selected category again clears it', (tester) async {
      await openSheet(tester, categories: _categories);

      await tester.tap(find.text('Food'));
      await tester.pump();
      await tester.tap(find.text('Food'));
      await tester.pump();
      await tester.enterText(amountField(), '5');
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(sentEvents().single.categoryId, isNull);
    });

    testWidgets('Save is disabled while submitting, and the sheet closes on '
        'success', (tester) async {
      await openSheet(tester);

      await tester.enterText(amountField(), '5');
      await tester.tap(find.text('Save'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      states.add(Loaded(data: const [], categories: const []));
      await tester.pumpAndSettle();

      expect(find.byType(AddTransactionSheet), findsNothing);
    });

    testWidgets('on an error the sheet stays open, shows it, and Save works '
        'again', (tester) async {
      await openSheet(tester);

      await tester.enterText(amountField(), '5');
      await tester.tap(find.text('Save'));
      await tester.pump();

      states.add(
        TransactionsError(message: 'Disk full', previousData: const []),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(AddTransactionSheet), findsOneWidget);
      expect(find.text('Disk full'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  });
}
