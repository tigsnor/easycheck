import 'package:flutter/material.dart';

import 'well_role.dart';

class WellGroup {
  const WellGroup({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.color,
    this.compoundName,
    this.role = WellRole.treatment,
    this.concentrationUnit = 'µM',
    this.notes = '',
  });

  final String id;
  final String name;
  final String shortLabel;
  final Color color;
  final String? compoundName;
  final WellRole role;
  final String concentrationUnit;
  final String notes;
}
