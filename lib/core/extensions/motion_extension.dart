import 'package:flutter/material.dart';

extension MotionX on BuildContext {
  Duration motion(Duration d) =>
      MediaQuery.disableAnimationsOf(this) ? Duration.zero : d;
}
