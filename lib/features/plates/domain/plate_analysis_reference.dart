import '../../../shared/data/json_validation.dart';
import 'well.dart';
import 'well_role.dart';

/// A manual reference applies to all concentrations/roles of one group and unit.
/// Absence of a selection means automatic references; empty lists mean none.
class PlateAnalysisReferenceSelection {
  const PlateAnalysisReferenceSelection({
    required this.groupId,
    required this.resultUnit,
    required this.blankWellLabels,
    required this.controlWellLabels,
  });

  final String? groupId;
  final String resultUnit;
  final List<String> blankWellLabels;
  final List<String> controlWellLabels;

  factory PlateAnalysisReferenceSelection.fromJson(Map<String, Object?> json) {
    List<String> labels(String field) {
      final value = json[field];
      if (value is! List ||
          value.any((v) =>
              v is! String || !RegExp(r'^[A-Z]+[1-9][0-9]*$').hasMatch(v)) ||
          value.toSet().length != value.length) {
        throw FormatException('Invalid reference coordinates: $field');
      }
      return List<String>.from(value);
    }

    final groupId = json['groupId'];
    final unit = json['resultUnit'];
    if ((groupId != null && (groupId is! String || groupId.trim().isEmpty)) ||
        unit is! String ||
        unit.isEmpty ||
        unit.trim() != unit) {
      throw const FormatException('Invalid analysis reference target.');
    }
    return PlateAnalysisReferenceSelection(
      groupId: groupId as String?,
      resultUnit: unit,
      blankWellLabels: labels('blankWellLabels'),
      controlWellLabels: labels('controlWellLabels'),
    );
  }

  Map<String, Object?> toJson() => {
        'groupId': groupId,
        'resultUnit': resultUnit,
        'blankWellLabels': blankWellLabels,
        'controlWellLabels': controlWellLabels,
      };

  static List<PlateAnalysisReferenceSelection> parseList(Object? json) {
    final values = jsonObjectList(json, 'analysisReferences')
        .map(PlateAnalysisReferenceSelection.fromJson)
        .toList();
    final targets = <(String?, String)>{};
    for (final value in values) {
      if (!targets.add((value.groupId, value.resultUnit))) {
        throw const FormatException('Duplicate analysis reference target.');
      }
    }
    return values;
  }
}

String analysisResultUnit(Well well) {
  final unit = well.resultUnit?.trim();
  return unit == null || unit.isEmpty ? '결과값' : unit;
}

const analysisControlRoles = [
  WellRole.vehicleControl,
  WellRole.untreatedControl,
  WellRole.negativeControl,
];
