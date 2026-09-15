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

  factory WellGroup.fromJson(Map<String, Object?> json) {
    return WellGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      shortLabel: json['shortLabel'] as String? ?? '',
      color: Color(json['color'] as int? ?? 0xFFE6D9FF),
      compoundName: json['compoundName'] as String?,
      role: WellRoleJson.fromName(json['role'] as String?),
      concentrationUnit: json['concentrationUnit'] as String? ?? 'µM',
      notes: json['notes'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String shortLabel;
  final Color color;
  final String? compoundName;
  final WellRole role;
  final String concentrationUnit;
  final String notes;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'shortLabel': shortLabel,
      'color': color.toARGB32(),
      'compoundName': compoundName,
      'role': role.name,
      'concentrationUnit': concentrationUnit,
      'notes': notes,
    };
  }
}
