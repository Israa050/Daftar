import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/theme/app_colors.dart';
import 'package:stockflow/features/transactions/bloc/transactions_bloc.dart';
import 'package:stockflow/features/categories/domain/entities/category_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:stockflow/features/transactions/presentation/format.dart';

Future<void> showAddTransactionSheet(BuildContext context) {
  final bloc = context.read<TransactionsBloc>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) =>
        BlocProvider.value(value: bloc, child: const AddTransactionSheet()),
  );
}

class AddTransactionSheet extends StatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  TransactionType _type = TransactionType.expense;
  bool _isSubmitting = false;
  String? _categoryId;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // Guaranteed non-null: the form validator below already rejects any
    // input parseAmountToMinor would reject.
    final amountMinor = parseAmountToMinor(_amountController.text)!;
    final note = _noteController.text.trim();

    setState(() => _isSubmitting = true);

    context.read<TransactionsBloc>().add(
      AddTransactionEvent(
        amountMinor: amountMinor,
        type: _type,
        note: note.isEmpty ? null : note,
        categoryId: _categoryId,
      ),
    );
  }

  /// After a submit: stay open and show the error, or close on success.
  void _onBlocState(BuildContext context, TransactionsState state) {
    if (state is TransactionsError) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.message)));
    } else if (state is Loaded) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final state = context.watch<TransactionsBloc>().state;
    final categories = state is Loaded ? state.categories : <CategoryEntity>[];
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: BlocListener<TransactionsBloc, TransactionsState>(
        listenWhen: (previous, current) => _isSubmitting,
        listener: _onBlocState,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const _SheetTitle(),
                const SizedBox(height: 18),
                _TypeSelector(
                  selected: _type,
                  onChanged: (type) => setState(() => _type = type),
                ),
                const SizedBox(height: 16),
                if (categories.isNotEmpty) ...[
                  _CategoryChips(
                    categories: categories,
                    selectedId: _categoryId,
                    onChanged: (id) => setState(() => _categoryId = id),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\$',
                  ),
                  validator: _validateAmount,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                _SaveButton(isSubmitting: _isSubmitting, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Null when [value] is a valid positive amount, otherwise the message to
/// show under the field. Mirrors what [parseAmountToMinor] accepts.
String? _validateAmount(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Enter an amount';
  if (parseAmountToMinor(trimmed) == null) {
    return 'Enter a valid positive amount';
  }
  return null;
}

/// The small grabber bar at the top of the sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: colors.line,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      'Add transaction',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w700,
        color: colors.ink,
      ),
    );
  }
}

/// Expense / income toggle.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});

  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TransactionType>(
      segments: const [
        ButtonSegment(
          value: TransactionType.expense,
          label: Text('Expense'),
          icon: Icon(Icons.remove),
        ),
        ButtonSegment(
          value: TransactionType.income,
          label: Text('Income'),
          icon: Icon(Icons.add),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// One chip per category. Tapping the selected chip again clears the choice
/// (reported as a null id).
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  final List<CategoryEntity> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: categories.map((category) {
        final categoryColor = parseHexColor(category.colorHex);
        return ChoiceChip(
          avatar: categoryColor == null
              ? null
              : CircleAvatar(backgroundColor: categoryColor),
          label: Text(category.name),
          selected: selectedId == category.id,
          selectedColor: categoryColor?.withValues(alpha: 0.3),
          onSelected: (selected) => onChanged(selected ? category.id : null),
        );
      }).toList(),
    );
  }
}

/// The Save button, which swaps its label for a spinner while submitting.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.isSubmitting, required this.onPressed});

  final bool isSubmitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FilledButton(
      onPressed: isSubmitting ? null : onPressed,
      child: isSubmitting
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.accentInk,
              ),
            )
          : const Text('Save'),
    );
  }
}
