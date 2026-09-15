import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_validation_service.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PlateValidationService();
  const treatmentGroup = WellGroup(
    id: 'drug-a',
    name: 'Drug A',
    shortLabel: 'A',
    color: Color(0xFFE6D9FF),
    role: WellRole.treatment,
    concentrationUnit: 'µM',
  );

  test(
    'reports no warning for blank, control, and duplicate treatment wells',
    () {
      final plate = _plateWithWells(
        [
          _well('A1', role: WellRole.blank),
          _well('A2', role: WellRole.vehicleControl),
          _well(
            'B1',
            groupId: treatmentGroup.id,
            role: WellRole.treatment,
            concentration: 100,
          ),
          _well(
            'B2',
            groupId: treatmentGroup.id,
            role: WellRole.treatment,
            concentration: 100,
          ),
        ],
        groups: const [treatmentGroup],
      );

      final report = service.validate(plate);

      expect(report.isReady, isTrue);
      expect(report.warningCount, 0);
    },
  );

  test('warns about missing blank, control, and insufficient replicates', () {
    final plate = _plateWithWells(
      [
        _well(
          'A1',
          groupId: treatmentGroup.id,
          role: WellRole.treatment,
          concentration: 100,
        ),
      ],
      groups: const [treatmentGroup],
    );

    final report = service.validate(plate);
    final codes = report.issues.map((issue) => issue.code);

    expect(codes, containsAll(['blank_missing', 'control_missing']));
    expect(codes, contains('replicate_insufficient'));
    expect(report.warningCount, 3);
  });

  test('detects mixed units, incomplete results, and excluded wells', () {
    final plate = _plateWithWells(
      [
        _well('A1', role: WellRole.blank, result: 0.1),
        _well('A2', role: WellRole.vehicleControl, excluded: true),
        _well(
          'B1',
          groupId: treatmentGroup.id,
          role: WellRole.treatment,
          concentration: 100,
          unit: 'µM',
          result: 0.8,
        ),
        _well(
          'B2',
          groupId: treatmentGroup.id,
          role: WellRole.treatment,
          concentration: 100,
          unit: 'nM',
        ),
      ],
      groups: const [treatmentGroup],
    );

    final report = service.validate(plate);
    final codes = report.issues.map((issue) => issue.code).toList();

    expect(codes.any((code) => code.startsWith('mixed_units_')), isTrue);
    expect(codes, contains('result_incomplete'));
    expect(codes, contains('excluded_wells'));
  });
}

Plate _plateWithWells(
  List<Well> replacements, {
  List<WellGroup> groups = const [],
}) {
  final plate = Plate(
    id: 'plate-1',
    experimentId: 'experiment-1',
    name: '96-well Plate',
    groups: groups,
  );
  final byPosition = {for (final well in replacements) well.position: well};
  return plate.copyWith(
    wells: [for (final well in plate.wells) byPosition[well.position] ?? well],
  );
}

Well _well(
  String label, {
  String? groupId,
  WellRole role = WellRole.empty,
  double? concentration,
  String unit = 'µM',
  double? result,
  bool excluded = false,
}) {
  final rowIndex = label.codeUnitAt(0) - 'A'.codeUnitAt(0);
  final columnIndex = int.parse(label.substring(1)) - 1;
  return Well(
    position: WellPosition(rowIndex: rowIndex, columnIndex: columnIndex),
    groupId: groupId,
    role: role,
    concentrationValue: concentration,
    concentrationUnit: concentration == null ? null : unit,
    resultValue: result,
    resultUnit: result == null ? null : 'OD450',
    excluded: excluded,
  );
}
