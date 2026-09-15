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

class PlateRevision {
  const PlateRevision({
    required this.id,
    required this.changedAt,
    required this.summary,
    this.snapshot,
  });

  factory PlateRevision.fromJson(Map<String, Object?> json) {
    return PlateRevision(
      id: json['id'] as String,
      changedAt: DateTime.parse(json['changedAt'] as String).toUtc(),
      summary: json['summary'] as String,
      snapshot: json['snapshot'] is Map<String, Object?>
          ? PlateSnapshot.fromJson(json['snapshot'] as Map<String, Object?>)
          : null,
    );
  }

  final String id;
  final DateTime changedAt;
  final String summary;
  final PlateSnapshot? snapshot;

  Map<String, Object?> toJson() => {
    'id': id,
    'changedAt': changedAt.toUtc().toIso8601String(),
    'summary': summary,
    'snapshot': snapshot?.toJson(),
  };
}

class PlateSnapshot {
  const PlateSnapshot({
    required this.name,
    required this.rowCount,
    required this.columnCount,
    required this.wells,
    required this.groups,
    required this.notes,
    required this.importHistory,
  });

  factory PlateSnapshot.fromPlate(Plate plate) => PlateSnapshot(
    name: plate.name,
    rowCount: plate.rowCount,
    columnCount: plate.columnCount,
    wells: plate.wells,
    groups: plate.groups,
    notes: plate.notes,
    importHistory: plate.importHistory,
  );

  factory PlateSnapshot.fromJson(Map<String, Object?> json) => PlateSnapshot(
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

  final String name;
  final int rowCount;
  final int columnCount;
  final List<Well> wells;
  final List<WellGroup> groups;
  final String notes;
  final List<PlateResultImportRecord> importHistory;

  Map<String, Object?> toJson() => {
    'name': name,
    'rowCount': rowCount,
    'columnCount': columnCount,
    'wells': wells.map((well) => well.toJson()).toList(),
    'groups': groups.map((group) => group.toJson()).toList(),
    'notes': notes,
    'importHistory': importHistory.map((item) => item.toJson()).toList(),
  };

  Plate restore({required String id, required String experimentId}) => Plate(
    id: id,
    experimentId: experimentId,
    name: name,
    rowCount: rowCount,
    columnCount: columnCount,
    wells: wells,
    groups: groups,
    notes: notes,
    importHistory: importHistory,
  );
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
    this.revisions = const [],
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
      revisions: (json['revisions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(PlateRevision.fromJson)
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
  final List<PlateRevision> revisions;

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
      'revisions': revisions.map((revision) => revision.toJson()).toList(),
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
    List<PlateRevision>? revisions,
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
      revisions: revisions ?? this.revisions,
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
