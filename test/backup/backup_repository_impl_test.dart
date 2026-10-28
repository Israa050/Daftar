import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/result.dart';
import 'package:stockflow/features/backup/data/backup_repository_impl.dart';
import 'package:stockflow/features/backup/domain/entities/exportable_source.dart';
import 'package:stockflow/features/backup/domain/entities/exported_file.dart';

class _FakeSource implements ExportableSource {
  _FakeSource(this.key, {this.rows = const [], this.error});

  @override
  final String key;
  final List<Map<String, Object?>> rows;
  final Object? error;

  @override
  Future<List<Map<String, Object?>>> exportRows() async {
    if (error != null) throw error!;
    return rows;
  }
}

// Arbitrary values, so the tests show the export stamps what it is given.
const _appVersion = '9.8.7';
const _schemaVersion = 42;

BackupRepositoryImpl _repository(List<ExportableSource> sources) =>
    BackupRepositoryImpl(
      sources: sources,
      appVersion: _appVersion,
      schemaVersion: _schemaVersion,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;

  setUp(() async {
    // The repository writes into path_provider's temp directory. There is no
    // platform behind it in a unit test, so point it at a throwaway folder.
    tempDir = await Directory.systemTemp.createTemp('backup_repository_test');
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      return call.method == 'getTemporaryDirectory' ? tempDir.path : null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    await tempDir.delete(recursive: true);
  });

  /// The exported file's JSON, read back from disk.
  Map<String, Object?> readJson(ExportedFile file) =>
      jsonDecode(File(file.path).readAsStringSync()) as Map<String, Object?>;

  Future<ExportedFile> exportOk(List<ExportableSource> sources) async {
    final result = await _repository(sources).exportToJson();
    expect(result, isA<Success<ExportedFile>>());
    return (result as Success<ExportedFile>).data;
  }

  group('BackupRepositoryImpl.exportToJson', () {
    test('writes each source\'s rows under its key', () async {
      final file = await exportOk([
        _FakeSource(
          'transactions',
          rows: [
            {'id': 't1', 'amountMinor': 500},
            {'id': 't2', 'amountMinor': 1200},
          ],
        ),
        _FakeSource(
          'categories',
          rows: [
            {'id': 'c1', 'name': 'Food'},
          ],
        ),
      ]);

      final json = readJson(file);
      expect(json['transactions'], [
        {'id': 't1', 'amountMinor': 500},
        {'id': 't2', 'amountMinor': 1200},
      ]);
      expect(json['categories'], [
        {'id': 'c1', 'name': 'Food'},
      ]);
    });

    test('reports a row count per source', () async {
      final file = await exportOk([
        _FakeSource(
          'transactions',
          rows: [
            {'id': 't1'},
            {'id': 't2'},
          ],
        ),
        _FakeSource(
          'categories',
          rows: [
            {'id': 'c1'},
          ],
        ),
      ]);

      expect(file.countsByKey, {'transactions': 2, 'categories': 1});
    });

    test('the reported size is the size of the file on disk', () async {
      final file = await exportOk([
        _FakeSource(
          'transactions',
          rows: [
            {'id': 't1'},
          ],
        ),
      ]);

      expect(file.byteSize, File(file.path).lengthSync());
      expect(file.byteSize, greaterThan(0));
    });

    test('the file is written to the temp directory', () async {
      final file = await exportOk([_FakeSource('transactions')]);

      expect(File(file.path).parent.path, tempDir.path);
      expect(File(file.path).existsSync(), isTrue);
    });

    test('stamps the app and schema versions it was given', () async {
      final file = await exportOk([_FakeSource('transactions')]);

      final json = readJson(file);
      expect(json['appVersion'], _appVersion);
      expect(json['schemaVersion'], _schemaVersion);
    });

    test('a source with no rows still appears, with a count of 0', () async {
      final file = await exportOk([_FakeSource('transactions')]);

      expect(readJson(file)['transactions'], isEmpty);
      expect(file.countsByKey, {'transactions': 0});
    });

    test(
      'returns a failure, and writes no file, when a source throws',
      () async {
        final result = await _repository([
          _FakeSource(
            'transactions',
            rows: [
              {'id': 't1'},
            ],
          ),
          _FakeSource('categories', error: StateError('database closed')),
        ]).exportToJson();

        expect(result, isA<Failure<ExportedFile>>());
        expect(
          (result as Failure<ExportedFile>).message,
          contains('database closed'),
        );
        expect(tempDir.listSync(), isEmpty);
      },
    );
  });
}
