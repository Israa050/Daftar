import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/sync/cubit/pending_sync_cubit.dart';
import 'package:stockflow/core/sync/presentation/widgets/sync_icon.dart';
import 'package:stockflow/core/sync/presentation/widgets/sync_sheet.dart';

/// App-bar action showing how many local changes are waiting to sync.
///
/// Always shown so sync stays reachable; the count badge only appears when
/// there is something queued. Tapping opens the sync sheet. The copy says
/// "waiting to sync", never "failed" -- a queued row is unconfirmed, not
/// broken (see docs/sync-queue.md).
class PendingSyncBadge extends StatelessWidget {
  const PendingSyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PendingSyncCubit, int>(
      builder: (context, count) {
        final tooltip = switch (count) {
          0 => 'Sync',
          1 => '1 change waiting to sync',
          _ => '$count changes waiting to sync',
        };

        const icon = SyncIcon();

        return IconButton(
          tooltip: tooltip,
          onPressed: () => showSyncSheet(context),
          icon: count == 0 ? icon : Badge(label: Text('$count'), child: icon),
        );
      },
    );
  }
}
