import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/app_version.dart';

void main() {
  test('appVersion matches the version in pubspec.yaml', () {
    // `flutter test` runs from the project root.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'no version: line found in pubspec.yaml');
    expect(
      appVersion,
      match!.group(1),
      reason:
          'Bump appVersion in lib/core/app_version.dart together with the '
          'version in pubspec.yaml: exports are stamped with it.',
    );
  });
}
