import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opens the on-disk SQLite connection backing [AppDatabase].
///
/// The file is still named `transactions.sqlite` for backwards compatibility:
/// renaming it would orphan every existing install's data.
QueryExecutor openAppDatabaseConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'transactions.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
