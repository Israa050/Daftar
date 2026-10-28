import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/features/backup/data/export_serializer.dart';

// Arbitrary values, so the tests show the envelope stamps what it is given
// rather than something hard-coded.
const _appVersion = '9.8.7';
const _schemaVersion = 42;

Map<String, Object?> _build(Map<String, List<Map<String, Object?>>> data) =>
    buildEnvelope(data, appVersion: _appVersion, schemaVersion: _schemaVersion);

String _encode(Map<String, List<Map<String, Object?>>> data) =>
    encodeExport(data, appVersion: _appVersion, schemaVersion: _schemaVersion);

void main() {
  // A representative two-source payload reused across cases.
  final sampleData = <String, List<Map<String, Object?>>>{
    'transactions': [
      {'id': 't1', 'amountMinor': 500},
      {'id': 't2', 'amountMinor': 250},
    ],
    'categories': [
      {'id': 'c1', 'name': 'Food'},
    ],
  };

  group('buildEnvelope', () {
    test('stamps the format version and the app and schema versions given', () {
      final envelope = _build(sampleData);

      expect(envelope['formatVersion'], 1);
      expect(envelope['appVersion'], _appVersion);
      expect(envelope['schemaVersion'], _schemaVersion);
    });

    test('exportedAt is a valid UTC ISO-8601 instant', () {
      final envelope = _build(sampleData);

      final exportedAt = envelope['exportedAt'] as String;
      expect(exportedAt, endsWith('Z'));

      final parsed = DateTime.parse(exportedAt);
      expect(parsed.isUtc, isTrue);
      // Sanity: it's "now", not some epoch default.
      expect(
        parsed.difference(DateTime.now().toUtc()).abs(),
        lessThan(const Duration(minutes: 1)),
      );
    });

    test('counts maps each source key to its row-list length', () {
      final envelope = _build(sampleData);

      expect(envelope['counts'], {'transactions': 2, 'categories': 1});
    });

    test('source data is spread onto the envelope at the top level', () {
      final envelope = _build(sampleData);

      expect(envelope['transactions'], same(sampleData['transactions']));
      expect(envelope['categories'], same(sampleData['categories']));
    });

    test('a source with zero rows -> count 0, key still present as []', () {
      final envelope = _build({
        'transactions': [],
        'categories': [
          {'id': 'c1'},
        ],
      });

      expect(envelope['counts'], {'transactions': 0, 'categories': 1});
      expect(envelope['transactions'], isEmpty);
    });

    test('empty sourceData -> empty counts, metadata still present', () {
      final envelope = _build({});

      expect(envelope['counts'], isEmpty);
      expect(envelope['formatVersion'], 1);
      expect(envelope['schemaVersion'], _schemaVersion);
      expect(envelope['exportedAt'], isA<String>());
    });

    test('counts does not collide with a source literally named "counts"', () {
      // Documents current behaviour: a source key of "counts" is spread
      // AFTER the computed counts entry, so the source data wins.
      final envelope = _build({
        'counts': [
          {'id': 'x'},
        ],
      });

      expect(envelope['counts'], [
        {'id': 'x'},
      ]);
    });
  });

  group('encodeExport', () {
    test('returns a JSON string that decodes back to the envelope', () {
      final decoded = jsonDecode(_encode(sampleData)) as Map<String, Object?>;

      expect(decoded['formatVersion'], 1);
      expect(decoded['appVersion'], _appVersion);
      expect(decoded['schemaVersion'], _schemaVersion);
      expect(decoded['counts'], {'transactions': 2, 'categories': 1});
      expect(decoded['transactions'], sampleData['transactions']);
      expect(decoded['categories'], sampleData['categories']);
      expect(DateTime.parse(decoded['exportedAt'] as String).isUtc, isTrue);
    });

    test('produces valid JSON for an empty payload', () {
      final decoded = jsonDecode(_encode({})) as Map<String, Object?>;

      expect(decoded['counts'], isEmpty);
      expect(decoded['formatVersion'], 1);
    });

    test('nested row values survive the JSON round-trip unchanged', () {
      final data = {
        'transactions': [
          {
            'id': 't1',
            'note': null,
            'amountMinor': 1234,
            'tags': ['a', 'b'],
          },
        ],
      };

      final decoded = jsonDecode(_encode(data)) as Map<String, Object?>;

      expect(decoded['transactions'], data['transactions']);
    });
  });
}
