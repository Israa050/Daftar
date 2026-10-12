/// The current time in UTC at whole-second precision.
///
/// Drift stores `DateTime` as whole seconds, so a local row written with
/// `DateTime.now()` silently loses its milliseconds while the sync payload
/// built from the same value keeps them. The server then holds a slightly
/// newer `updated_at` than the local row, and a pull sees the device's own
/// push as a remote change. Truncating once, before both the local write and
/// the payload are built, keeps them identical.
///
/// Trade-off: last-write-wins resolves at one-second granularity, so two
/// edits in the same second tie, and a tie keeps the local copy.
DateTime nowForSync() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
    now.second,
  );
}
