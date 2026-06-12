import '../../domain/plate.dart';
import '../../domain/well.dart';
import '../../domain/well_group.dart';

class PlateTemplate {
  const PlateTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.rowCount,
    required this.columnCount,
    required this.wells,
    required this.groups,
    this.notes = '',
  });

  factory PlateTemplate.fromPlate({
    required String id,
    required String name,
    required Plate plate,
    DateTime? createdAt,
  }) {
    final now = (createdAt ?? DateTime.now()).toUtc();
    return PlateTemplate(
      id: id,
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
      rowCount: plate.rowCount,
      columnCount: plate.columnCount,
      wells: plate.wells.map(_withoutResult).toList(),
      groups: [...plate.groups],
      notes: plate.notes,
    );
  }

  factory PlateTemplate.fromJson(Map<String, Object?> json) {
    return PlateTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      rowCount: json['rowCount'] as int? ?? 8,
      columnCount: json['columnCount'] as int? ?? 12,
      wells: (json['wells'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(Well.fromJson)
          .map(_withoutResult)
          .toList(),
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(WellGroup.fromJson)
          .toList(),
      notes: json['notes'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowCount;
  final int columnCount;
  final List<Well> wells;
  final List<WellGroup> groups;
  final String notes;

  Plate instantiate({
    required String plateId,
    required String experimentId,
    String plateName = '96-well Plate',
  }) {
    return Plate(
      id: plateId,
      experimentId: experimentId,
      name: plateName,
      rowCount: rowCount,
      columnCount: columnCount,
      wells: wells.map(_withoutResult).toList(),
      groups: [...groups],
      notes: notes,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'rowCount': rowCount,
      'columnCount': columnCount,
      'wells': wells.map((well) => _withoutResult(well).toJson()).toList(),
      'groups': groups.map((group) => group.toJson()).toList(),
      'notes': notes,
    };
  }

  static Well _withoutResult(Well well) {
    return well.copyWith(resultValue: null, resultUnit: null, excluded: false);
  }
}
