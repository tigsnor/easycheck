import '../../../shared/models/well_position.dart';
import 'well_role.dart';

const _unset = Object();

class Well {
  const Well({
    required this.position,
    this.groupId,
    this.role = WellRole.empty,
    this.concentrationValue,
    this.concentrationUnit,
    this.volumeValue,
    this.volumeUnit = 'µL',
    this.replicateIndex,
    this.note = '',
    this.resultValue,
    this.resultUnit,
    this.excluded = false,
  });

  factory Well.fromJson(Map<String, Object?> json) {
    return Well(
      position: WellPosition(
        rowIndex: json['rowIndex'] as int,
        columnIndex: json['columnIndex'] as int,
      ),
      groupId: json['groupId'] as String?,
      role: WellRoleJson.fromName(json['role'] as String?),
      concentrationValue: (json['concentrationValue'] as num?)?.toDouble(),
      concentrationUnit: json['concentrationUnit'] as String?,
      volumeValue: (json['volumeValue'] as num?)?.toDouble(),
      volumeUnit: json['volumeUnit'] as String? ?? 'µL',
      replicateIndex: json['replicateIndex'] as int?,
      note: json['note'] as String? ?? '',
      resultValue: (json['resultValue'] as num?)?.toDouble(),
      resultUnit: json['resultUnit'] as String?,
      excluded: json['excluded'] as bool? ?? false,
    );
  }

  final WellPosition position;
  final String? groupId;
  final WellRole role;
  final double? concentrationValue;
  final String? concentrationUnit;
  final double? volumeValue;
  final String volumeUnit;
  final int? replicateIndex;
  final String note;
  final double? resultValue;
  final String? resultUnit;
  final bool excluded;

  String get label => position.label;

  Map<String, Object?> toJson() {
    return {
      'rowIndex': position.rowIndex,
      'columnIndex': position.columnIndex,
      'groupId': groupId,
      'role': role.name,
      'concentrationValue': concentrationValue,
      'concentrationUnit': concentrationUnit,
      'volumeValue': volumeValue,
      'volumeUnit': volumeUnit,
      'replicateIndex': replicateIndex,
      'note': note,
      'resultValue': resultValue,
      'resultUnit': resultUnit,
      'excluded': excluded,
    };
  }

  Well copyWith({
    Object? groupId = _unset,
    WellRole? role,
    Object? concentrationValue = _unset,
    Object? concentrationUnit = _unset,
    Object? volumeValue = _unset,
    String? volumeUnit,
    Object? replicateIndex = _unset,
    String? note,
    Object? resultValue = _unset,
    Object? resultUnit = _unset,
    bool? excluded,
  }) {
    return Well(
      position: position,
      groupId: identical(groupId, _unset) ? this.groupId : groupId as String?,
      role: role ?? this.role,
      concentrationValue: identical(concentrationValue, _unset)
          ? this.concentrationValue
          : (concentrationValue as num?)?.toDouble(),
      concentrationUnit: identical(concentrationUnit, _unset)
          ? this.concentrationUnit
          : concentrationUnit as String?,
      volumeValue: identical(volumeValue, _unset)
          ? this.volumeValue
          : (volumeValue as num?)?.toDouble(),
      volumeUnit: volumeUnit ?? this.volumeUnit,
      replicateIndex: identical(replicateIndex, _unset)
          ? this.replicateIndex
          : replicateIndex as int?,
      note: note ?? this.note,
      resultValue: identical(resultValue, _unset)
          ? this.resultValue
          : (resultValue as num?)?.toDouble(),
      resultUnit: identical(resultUnit, _unset)
          ? this.resultUnit
          : resultUnit as String?,
      excluded: excluded ?? this.excluded,
    );
  }
}
