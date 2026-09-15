import 'package:flutter/material.dart';

import '../../../plates/domain/well.dart';
import '../../../plates/domain/well_group.dart';
import '../../../plates/domain/well_role.dart';
import '../../../../shared/models/well_position.dart';
import 'plate_template.dart';

class DefaultPlateTemplates {
  const DefaultPlateTemplates._();

  static List<PlateTemplate> get all => [_cck8TwoFoldTriplicate];

  static List<PlateTemplate> mergeWithSaved(List<PlateTemplate> saved) {
    final savedIds = saved.map((template) => template.id).toSet();
    return [
      ...saved,
      for (final template in all)
        if (!savedIds.contains(template.id)) template,
    ];
  }

  static final PlateTemplate _cck8TwoFoldTriplicate = PlateTemplate(
    id: 'default-cck8-twofold-triplicate',
    name: '기본 · CCK-8 2배 희석 3반복',
    createdAt: DateTime.utc(2026, 6, 16),
    updatedAt: DateTime.utc(2026, 6, 16),
    rowCount: 8,
    columnCount: 12,
    groups: const [
      WellGroup(
        id: 'blank',
        name: 'Blank',
        shortLabel: 'BLK',
        color: Color(0xFFE5E7EB),
        role: WellRole.blank,
      ),
      WellGroup(
        id: 'vehicle',
        name: 'Vehicle control',
        shortLabel: 'VC',
        color: Color(0xFFBFDBFE),
        role: WellRole.vehicleControl,
      ),
      WellGroup(
        id: 'drug-a',
        name: 'Drug A 2배 희석',
        shortLabel: 'A',
        color: Color(0xFFFBCFE8),
        compoundName: 'Drug A',
        role: WellRole.treatment,
        concentrationUnit: 'µM',
      ),
      WellGroup(
        id: 'drug-b',
        name: 'Drug B 2배 희석',
        shortLabel: 'B',
        color: Color(0xFFDDD6FE),
        compoundName: 'Drug B',
        role: WellRole.treatment,
        concentrationUnit: 'µM',
      ),
    ],
    wells: _cck8Wells,
    notes:
        'Blank 3반복, Vehicle control 3반복, Drug A/B 2배 희석 3반복 예시입니다. 실제 실험 농도와 배치는 적용 전 확인하세요.',
  );

  static final List<Well> _cck8Wells = [
    for (var row = 0; row < 8; row++)
      for (var column = 0; column < 12; column++)
        _cck8Well(rowIndex: row, columnIndex: column),
  ];

  static Well _cck8Well({required int rowIndex, required int columnIndex}) {
    final position = WellPosition(rowIndex: rowIndex, columnIndex: columnIndex);
    if (columnIndex < 3) {
      return Well(
        position: position,
        groupId: 'blank',
        role: WellRole.blank,
        volumeValue: 100,
        replicateIndex: columnIndex + 1,
        note: 'Medium + reagent only',
      );
    }
    if (columnIndex < 6) {
      return Well(
        position: position,
        groupId: 'vehicle',
        role: WellRole.vehicleControl,
        concentrationValue: 0,
        concentrationUnit: '% vehicle',
        volumeValue: 100,
        replicateIndex: columnIndex - 2,
      );
    }
    final concentration = _cck8Concentrations[rowIndex];
    if (columnIndex < 9) {
      return Well(
        position: position,
        groupId: 'drug-a',
        role: WellRole.treatment,
        concentrationValue: concentration,
        concentrationUnit: 'µM',
        volumeValue: 100,
        replicateIndex: columnIndex - 5,
      );
    }
    return Well(
      position: position,
      groupId: 'drug-b',
      role: WellRole.treatment,
      concentrationValue: concentration,
      concentrationUnit: 'µM',
      volumeValue: 100,
      replicateIndex: columnIndex - 8,
    );
  }

  static const List<double> _cck8Concentrations = [
    100,
    50,
    25,
    12.5,
    6.25,
    3.125,
    1.5625,
    0,
  ];
}
