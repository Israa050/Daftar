import 'package:flutter/material.dart';

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final value = int.tryParse(hex.replaceFirst('#', 'FF'), radix: 16);
  return value == null ? null : Color(value);
}

String formatAmountMinor(int amountMinor) {
  final sign = amountMinor < 0 ? '-' : '';
  final abs = amountMinor.abs();
  final whole = abs ~/ 100;
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '\u200E$sign\$$whole.$cents';
}

/// Parses a user-typed amount (e.g. the text in the amount field) into
/// minor units (cents). Returns null if [input] isn't a valid, positive
/// number -- callers should treat that the same as a failed validation.
///
/// Rounds to the nearest cent rather than truncating, so a typed value
/// like "19.999" (three decimal places) becomes 2000, not 1999 -- and
/// uses round() specifically to avoid the double bankers'-rounding
/// surprises Dart's num.round() does NOT have (it always rounds
/// half-away-from-zero), matching how a user reads "19.995" as "$20.00".
int? parseAmountToMinor(String input) {
  final parsed = double.tryParse(input.trim());
  if (parsed == null || parsed.isNaN || !parsed.isFinite || parsed <= 0) {
    return null;
  }
  return (parsed * 100).round();
}

String formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
