import '../../../shared/models/well_position.dart';
import 'well.dart';
import 'well_group.dart';

class Plate {
  Plate({
    required this.id,
    required this.experimentId,
    required this.name,
    this.rowCount = 8,
    this.columnCount = 12,
    List<Well>? wells,
    this.groups = const [],
    this.notes = '',
  }) : wells = wells ?? _buildEmptyWells(rowCount, columnCount);

  factory Plate.fromJson(Map<String, Object?> json) {
    return Plate(
      id: json['id'] as String,
      experimentId: json['experimentId'] as String,
      name: json['name'] as String? ?? '96-well Plate',
      rowCount: json['rowCount'] as int? ?? 8,
      columnCount: json['columnCount'] as int? ?? 12,
      wells: (json['wells'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(Well.fromJson)
          .toList(),
      groups: (json['groups'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(WellGroup.fromJson)
          .toList(),
      notes: json['notes'] as String? ?? '',
    );
  }

  final String id;
  final String experimentId;
  final String name;
  final int rowCount;
  final int columnCount;
  final List<Well> wells;
  final List<WellGroup> groups;
  final String notes;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'experimentId': experimentId,
      'name': name,
      'rowCount': rowCount,
      'columnCount': columnCount,
      'wells': wells.map((well) => well.toJson()).toList(),
      'groups': groups.map((group) => group.toJson()).toList(),
      'notes': notes,
    };
  }

  Plate copyWith({
    String? id,
    String? experimentId,
    String? name,
    int? rowCount,
    int? columnCount,
    List<Well>? wells,
    List<WellGroup>? groups,
    String? notes,
  }) {
    return Plate(
      id: id ?? this.id,
      experimentId: experimentId ?? this.experimentId,
      name: name ?? this.name,
      rowCount: rowCount ?? this.rowCount,
      columnCount: columnCount ?? this.columnCount,
      wells: wells ?? this.wells,
      groups: groups ?? this.groups,
      notes: notes ?? this.notes,
    );
  }

  static List<Well> _buildEmptyWells(int rowCount, int columnCount) {
    return [
      for (var row = 0; row < rowCount; row++)
        for (var column = 0; column < columnCount; column++)
          Well(
            position: WellPosition(rowIndex: row, columnIndex: column),
          ),
    ];
  }

  Well wellAt(WellPosition position) {
    return wells.firstWhere((well) => well.position == position);
  }
}
