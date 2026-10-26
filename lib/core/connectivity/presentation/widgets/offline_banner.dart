import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/connectivity/cubit/connectivity_cubit.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/extensions/motion_extension.dart';

/// A thin strip shown above the screen content while the device has no
/// network interface. Driven by [ConnectivityCubit]; collapses to nothing
/// when back online.
///
/// The copy says "saved on this device" rather than anything about syncing
/// or retrying -- see docs/sync-queue.md. Every change is written locally
/// and queued regardless of connectivity, so being offline is not a failure
/// state, just an informational one.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<ConnectivityCubit, NetworkStatus>(
      builder: (context, status) {
        final offline = status == NetworkStatus.offline;

        return AnimatedSize(
          duration: context.motion(const Duration(milliseconds: 200)),
          alignment: Alignment.topCenter,
          child: offline
              ? Material(
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 16,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Offline — changes are saved on this device',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}
