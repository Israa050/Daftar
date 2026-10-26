import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockflow/core/extensions/motion_extension.dart';

const _duration = Duration(milliseconds: 200);

/// Pumps a [MediaQuery] with the given reduced-motion flag and returns what
/// `context.motion(_duration)` gives inside it.
Future<Duration> _motionWith(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  late Duration result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Builder(
        builder: (context) {
          result = context.motion(_duration);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  group('MotionX.motion', () {
    testWidgets('keeps the duration when animations are on', (tester) async {
      expect(await _motionWith(tester, disableAnimations: false), _duration);
    });

    testWidgets('is zero when the system asks to reduce motion', (
      tester,
    ) async {
      expect(await _motionWith(tester, disableAnimations: true), Duration.zero);
    });
  });
}
