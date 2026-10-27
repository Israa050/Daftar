import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/connectivity/cubit/connectivity_cubit.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/sync/cubit/pending_sync_cubit.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';
import 'package:stockflow/core/sync/presentation/widgets/sync_icon.dart';

class SyncNowButton extends StatelessWidget {
  const SyncNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, syncState) {
        final offline =
            context.watch<ConnectivityCubit>().state == NetworkStatus.offline;
        final pendingCount = context.watch<PendingSyncCubit>().state;
        final inProgress = syncState is SyncInProgress;

        final String? disabledReason;
        if (inProgress) {
          disabledReason = 'Syncing…';
        } else if (offline) {
          disabledReason = "You're offline";
        } else if (pendingCount == 0) {
          disabledReason = 'Nothing to sync';
        } else {
          disabledReason = null;
        }

        final button = FilledButton.tonalIcon(
          onPressed: disabledReason != null
              ? null
              : () => context.read<SyncCubit>().syncNow(),
          icon: const SyncIcon(),
          label: const Text('Sync now'),
        );

        return disabledReason == null
            ? button
            : Tooltip(message: disabledReason, child: button);
      },
    );
  }
}
