import '../../../shared/models/well_position.dart';
import 'well_role.dart';

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

  Well copyWith({
    String? groupId,
    WellRole? role,
    double? concentrationValue,
    String? concentrationUnit,
    double? volumeValue,
    String? volumeUnit,
    int? replicateIndex,
    String? note,
    double? resultValue,
    String? resultUnit,
    bool? excluded,
  }) {
    return Well(
      position: position,
      groupId: groupId ?? this.groupId,
      role: role ?? this.role,
      concentrationValue: concentrationValue ?? this.concentrationValue,
      concentrationUnit: concentrationUnit ?? this.concentrationUnit,
      volumeValue: volumeValue ?? this.volumeValue,
      volumeUnit: volumeUnit ?? this.volumeUnit,
      replicateIndex: replicateIndex ?? this.replicateIndex,
      note: note ?? this.note,
      resultValue: resultValue ?? this.resultValue,
      resultUnit: resultUnit ?? this.resultUnit,
      excluded: excluded ?? this.excluded,
    );
  }
}
