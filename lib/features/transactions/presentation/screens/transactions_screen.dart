import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/connectivity/presentation/widgets/offline_banner.dart';
import 'package:stockflow/core/sync/presentation/widgets/pending_sync_badge.dart';
import 'package:stockflow/features/backup/presentation/widgets/export_action.dart';
import 'package:stockflow/features/transactions/bloc/transactions_bloc.dart';
import 'package:stockflow/features/categories/domain/entities/category_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_entity.dart';
import 'package:stockflow/features/transactions/domain/entities/transaction_type.dart';
import 'package:stockflow/features/categories/presentation/screens/categories_screen.dart';
import 'package:stockflow/features/transactions/presentation/widgets/add_transaction_sheet.dart';
import 'package:stockflow/features/transactions/presentation/widgets/balance_summary_card.dart';
import 'package:stockflow/features/categories/presentation/widgets/category_totals_card.dart';
import 'package:stockflow/features/transactions/presentation/widgets/transactions_list.dart';
import 'package:stockflow/features/transactions/presentation/widgets/undo_snackbar_content.dart';

const _undoDuration = Duration(seconds: 5);

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  // Ids that have been swiped away but whose delete is still pending
  // (i.e. the user might still hit Undo). Hiding them locally keeps the
  // rendered list in sync with what Dismissible already removed, instead
  // of waiting on the bloc's async delete + refresh round trip.
  final Set<String> _pendingDeleteIds = {};

  @override
  void initState() {
    super.initState();
    context.read<TransactionsBloc>().add(AppLaunchEvent());
  }

  void _handleSwipeToDelete(TransactionEntity transaction) {
    setState(() => _pendingDeleteIds.add(transaction.id));

    final bloc = context.read<TransactionsBloc>();
    var undone = false;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: UndoSnackBarContent(
              message: transaction.note?.isNotEmpty == true
                  ? 'Deleted "${transaction.note}"'
                  : 'Transaction deleted',
              duration: _undoDuration,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                undone = true;
                if (!mounted) return;
                setState(() => _pendingDeleteIds.remove(transaction.id));
              },
            ),
            duration: _undoDuration,
          ),
        )
        .closed
        .then((_) {
          if (undone) return;
          bloc.add(DeleteTransactionEvent(id: transaction.id));
          // _pendingDeleteIds is pruned via onConfirmedGone once the bloc
          // confirms the row is actually gone, so it never grows unbounded.
        });
  }

  void _handleConfirmedGone(List<String> ids) {
    if (!mounted) return;
    setState(() => _pendingDeleteIds.removeAll(ids));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          const PendingSyncBadge(),
          const ExportAction(),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Manage categories',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: _TransactionsBody(
              pendingDeleteIds: _pendingDeleteIds,
              onDelete: _handleSwipeToDelete,
              onConfirmedGone: _handleConfirmedGone,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddTransactionSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

class _TransactionsBody extends StatelessWidget {
  const _TransactionsBody({
    required this.pendingDeleteIds,
    required this.onDelete,
    required this.onConfirmedGone,
  });

  /// Ids the parent is hiding locally while their delete is still undoable.
  final Set<String> pendingDeleteIds;

  /// Called when the user swipes a row away.
  final void Function(TransactionEntity transaction) onDelete;

  /// Called with the ids that the bloc has now confirmed are gone, so the
  /// parent can drop them from [pendingDeleteIds].
  final void Function(List<String> ids) onConfirmedGone;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TransactionsBloc, TransactionsState>(
      builder: (context, state) {
        final allData = switch (state) {
          TransactionsInitial() => null,
          Loaded(:final data) => data,
          TransactionsError(:final previousData) => previousData,
        };
        final categories = switch (state) {
          Loaded(:final categories) => categories,
          _ => const <CategoryEntity>[],
        };

        if (state is TransactionsError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          });
        }

        if (allData == null) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is Loaded && pendingDeleteIds.isNotEmpty) {
          final stillPresent = allData.map((t) => t.id).toSet();
          final confirmedGone = pendingDeleteIds
              .where((id) => !stillPresent.contains(id))
              .toList();
          if (confirmedGone.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onConfirmedGone(confirmedGone),
            );
          }
        }

        final data = pendingDeleteIds.isEmpty
            ? allData
            : allData.where((t) => !pendingDeleteIds.contains(t.id)).toList();

        final income = data
            .where((t) => t.type == TransactionType.income)
            .fold<int>(0, (sum, t) => sum + t.amountMinor);
        final expense = data
            .where((t) => t.type == TransactionType.expense)
            .fold<int>(0, (sum, t) => sum + t.amountMinor);

        // One scroll view for the whole page: the cards scroll away with the
        // list instead of staying pinned and squeezing it.
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BalanceSummaryCard(income: income, expense: expense),
            ),
            const SliverToBoxAdapter(child: CategoryTotalsCard()),
            TransactionsList(
              data: data,
              onDelete: onDelete,
              categories: categories,
            ),
          ],
        );
      },
    );
  }
}
