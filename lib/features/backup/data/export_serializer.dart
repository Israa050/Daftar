import 'dart:convert';

/// Wraps the exported rows in an envelope with the metadata a future import
/// needs: the format version, which app and database schema wrote the file,
/// when, and how many rows each source has.
Map<String, Object?> buildEnvelope(
  Map<String, List<Map<String, Object?>>> sourceData, {
  required String appVersion,
  required int schemaVersion,
}) {
  return {
    'formatVersion': 1,
    'appVersion': appVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
    'counts': sourceData.map((key, rows) => MapEntry(key, rows.length)),
    ...sourceData,
  };
}

String encodeExport(
  Map<String, List<Map<String, Object?>>> sourceData, {
  required String appVersion,
  required int schemaVersion,
}) {
  final result = buildEnvelope(
    sourceData,
    appVersion: appVersion,
    schemaVersion: schemaVersion,
  );
  return jsonEncode(result);
}
