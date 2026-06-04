import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:flutter/material.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/shared/models/well_position.dart';

void main() {
  group('Plate serialization', () {
    test('round-trips well concentrations and roles', () {
      const group = WellGroup(
        id: 'group-1',
        name: 'Drug A',
        shortLabel: 'A',
        color: Color(0xFFE6D9FF),
      );
      final plate = Plate(
        id: 'plate-1',
        experimentId: 'experiment-1',
        name: '96-well Plate',
        groups: const [group],
      );
      final updatedWells = plate.wells.map((well) {
        if (well.position == const WellPosition(rowIndex: 0, columnIndex: 0)) {
          return well.copyWith(
            groupId: group.id,
            concentrationValue: 1000,
            concentrationUnit: 'µM',
            role: WellRole.treatment,
          );
        }
        return well;
      }).toList();

      final restored = Plate.fromJson(
        plate.copyWith(wells: updatedWells).toJson(),
      );
      final a1 = restored.wellAt(
        const WellPosition(rowIndex: 0, columnIndex: 0),
      );

      expect(restored.id, 'plate-1');
      expect(restored.experimentId, 'experiment-1');
      expect(restored.wells.length, 96);
      expect(restored.groups.single.name, 'Drug A');
      expect(restored.groups.single.shortLabel, 'A');
      expect(restored.groups.single.color.toARGB32(), 0xFFE6D9FF);
      expect(a1.groupId, 'group-1');
      expect(a1.concentrationValue, 1000);
      expect(a1.concentrationUnit, 'µM');
      expect(a1.role, WellRole.treatment);
    });
  });
}
