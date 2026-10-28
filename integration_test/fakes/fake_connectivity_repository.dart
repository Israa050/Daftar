import 'dart:async';

import 'package:stockflow/core/connectivity/domain/connectivity_repository.dart';
import 'package:stockflow/core/connectivity/domain/network_status.dart';
import 'package:stockflow/core/result.dart';

/// A connectivity source the test controls: call [setStatus] to go offline or
/// online on command, instead of depending on the device's real network.
class FakeConnectivityRepository implements ConnectivityRepository {
  // Broadcast, so more than one listener can attach without an
  // "already listened to" error.
  final _controller = StreamController<NetworkStatus>.broadcast();
  NetworkStatus _status = NetworkStatus.online;

  /// Changes the status and tells everyone listening.
  void setStatus(NetworkStatus status) {
    _status = status;
    _controller.add(status);
  }

  @override
  Future<Result<NetworkStatus>> checkConnectivity() async => Success(_status);

  @override
  Stream<NetworkStatus> watchConnectivityChanges() => _controller.stream;

  Future<void> dispose() => _controller.close();
}
