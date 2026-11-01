import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/assay_condition.dart';
import '../domain/cell_condition.dart';

/// Display colors depend only on the condition, not group, position or other
/// conditions. Reopening/restoring a plate therefore keeps the same colors.
abstract final class ConditionColors {
  static Color cell(CellCondition condition) => _color(
      'cell',
      jsonEncode([
        condition.name,
        condition.density == 0 ? 0.0 : condition.density,
        condition.unit
      ]));

  static Color medium(AssayCondition condition) =>
      _color('medium', condition.key);

  static Color _color(String layer, String key) {
    // Stable across runtimes; do not use String.hashCode for persisted meaning.
    var hash = 0;
    for (final unit in '$layer:$key'.codeUnits) {
      hash = (hash * 131 + unit) & 0x7fffffff;
    }
    // A wide hue range with readable pastel fills. Codes/labels distinguish
    // similar hues when many conditions coexist; color is never an identifier.
    return HSLColor.fromAHSL(
            1, (hash % 360).toDouble(), 0.55 + ((hash >> 9) % 15) / 100, 0.82)
        .toColor();
  }
}
