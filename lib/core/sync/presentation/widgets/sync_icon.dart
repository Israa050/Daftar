import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stockflow/core/sync/cubit/sync_cubit.dart';

/// The sync icon: a cloud at rest, and a spinning sync arrow while
/// [SyncCubit] is syncing.
///
/// The spin is the one explicit animation in the app, because it has to
/// start and stop with sync state rather than glide to a target value. The
/// controller is created here and disposed in [dispose], so no ticker
/// survives the widget. Under reduced motion it shows the sync arrow but
/// never spins.
///
/// Size and color come from the surrounding [IconTheme], so it fits both an
/// app-bar [IconButton] and a button's leading icon.
class SyncIcon extends StatefulWidget {
  const SyncIcon({super.key});

  @override
  State<SyncIcon> createState() => _SyncIconState();
}

class _SyncIconState extends State<SyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _syncing = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    // SyncCubit can already be syncing when this mounts: it starts a sync in
    // its constructor when the app opens online.
    _syncing = context.read<SyncCubit>().state is SyncInProgress;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _updateSpin();
  }

  /// Spin only while syncing and only when the user has not asked for
  /// reduced motion; otherwise stop and rest at the start.
  void _updateSpin() {
    if (_syncing && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SyncCubit, SyncState>(
      listener: (context, state) {
        setState(() => _syncing = state is SyncInProgress);
        _updateSpin();
      },
      child: _syncing
          ? RotationTransition(
              turns: _controller,
              child: const Icon(Icons.sync),
            )
          : const Icon(Icons.cloud_upload_outlined),
    );
  }
}
