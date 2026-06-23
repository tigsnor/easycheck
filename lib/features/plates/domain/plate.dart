import '../../../shared/models/well_position.dart';
import 'well.dart';
import 'well_group.dart';

class PlateResultImportRecord {
  const PlateResultImportRecord({
    required this.id,
    required this.sourceName,
    required this.importedAt,
    required this.valueCount,
    required this.resultUnit,
  });

  factory PlateResultImportRecord.fromJson(Map<String, Object?> json) {
    return PlateResultImportRecord(
      id: json['id'] as String,
      sourceName: json['sourceName'] as String? ?? 'unknown',
      importedAt: DateTime.parse(json['importedAt'] as String).toUtc(),
      valueCount: json['valueCount'] as int? ?? 0,
      resultUnit: json['resultUnit'] as String? ?? '',
    );
  }

  final String id;
  final String sourceName;
  final DateTime importedAt;
  final int valueCount;
  final String resultUnit;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'sourceName': sourceName,
      'importedAt': importedAt.toUtc().toIso8601String(),
      'valueCount': valueCount,
      'resultUnit': resultUnit,
    };
  }
}

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
    this.importHistory = const [],
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
      importHistory: (json['importHistory'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(PlateResultImportRecord.fromJson)
          .toList(),
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
  final List<PlateResultImportRecord> importHistory;

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
      'importHistory': importHistory.map((record) => record.toJson()).toList(),
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
    List<PlateResultImportRecord>? importHistory,
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
      importHistory: importHistory ?? this.importHistory,
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
