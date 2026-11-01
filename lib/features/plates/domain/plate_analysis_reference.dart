import 'assay_condition.dart';
import 'cell_condition.dart';
import '../../../shared/data/json_validation.dart';
import 'well.dart';
import 'well_role.dart';

/// A manual reference applies to all concentrations/roles of one group, unit, cell condition and assay condition.
/// Absence of a selection means automatic references; empty lists mean none.
class PlateAnalysisReferenceSelection {
  const PlateAnalysisReferenceSelection({
    required this.groupId,
    this.cellCondition,
    this.assayCondition,
    required this.resultUnit,
    required this.blankWellLabels,
    required this.controlWellLabels,
  });

  final String? groupId;
  final CellCondition? cellCondition;
  final AssayCondition? assayCondition;
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
      cellCondition: json['cellCondition'] == null
          ? null
          : CellCondition.fromJson(json['cellCondition']),
      assayCondition: json['assayCondition'] == null
          ? null
          : AssayCondition.fromJson(json['assayCondition']),
      blankWellLabels: labels('blankWellLabels'),
      controlWellLabels: labels('controlWellLabels'),
    );
  }

  Map<String, Object?> toJson() => {
        'groupId': groupId,
        'cellCondition': cellCondition?.toJson(),
        'assayCondition': assayCondition?.toJson(),
        'resultUnit': resultUnit,
        'blankWellLabels': blankWellLabels,
        'controlWellLabels': controlWellLabels,
      };

  static List<PlateAnalysisReferenceSelection> parseList(Object? json) {
    final values = jsonObjectList(json, 'analysisReferences')
        .map(PlateAnalysisReferenceSelection.fromJson)
        .toList();
    final targets = <(String?, String, CellCondition?, AssayCondition?)>{};
    for (final value in values) {
      if (!targets.add((
        value.groupId,
        value.resultUnit,
        value.cellCondition,
        value.assayCondition
      ))) {
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
