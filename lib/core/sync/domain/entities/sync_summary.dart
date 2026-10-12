/// What one full sync did: rows pushed to the server and rows pulled from it.
class SyncSummary {
  const SyncSummary({required this.pushedCount, required this.pulledCount});

  final int pushedCount;
  final int pulledCount;
}
