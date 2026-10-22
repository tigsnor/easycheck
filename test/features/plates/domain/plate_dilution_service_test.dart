import 'package:easycheck/features/dilution/domain/dilution_direction.dart';
import 'package:easycheck/features/dilution/domain/dilution_plan.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_dilution_service.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/shared/models/well_position.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PlateDilutionService();
  const group = WellGroup(
    id: 'drug-a',
    name: 'Drug A',
    shortLabel: 'A',
    color: Color(0xFFE6D9FF),
    concentrationUnit: 'µM',
  );

  test('applies dilution series to default top-left wells with replicates', () {
    final plate = Plate(
      id: 'plate-1',
      experimentId: 'experiment-1',
      name: '96',
    );
    final updated = service.applySeries(
      plate: plate,
      plan: const DilutionPlan(
        startConcentration: 100,
        dilutionFactor: 2,
        steps: 3,
        includeZeroControl: true,
      ),
      group: group,
      replicateCount: 2,
      zeroControlRole: WellRole.vehicleControl,
      volumePerWell: 100,
      volumeUnit: 'µL',
    );

    expect(updated.groups.single.id, 'drug-a');
    expect(
      updated.wells.take(8).map((well) => well.concentrationValue).toList(),
      [100, 100, 50, 50, 25, 25, 0, 0],
    );
    expect(updated.wells[0].role, WellRole.treatment);
    expect(updated.wells[6].role, WellRole.vehicleControl);
    expect(updated.wells[7].role, WellRole.vehicleControl);
    expect(updated.wells[7].replicateIndex, 2);
    expect(updated.wells[0].volumeValue, 100);
    expect(updated.wells[0].volumeUnit, 'µL');
  });

  test(
    'uses selected positions and direction order when applying a series',
    () {
      final plate = Plate(
        id: 'plate-1',
        experimentId: 'experiment-1',
        name: '96',
      );
      final updated = service.applySeries(
        plate: plate,
        plan: const DilutionPlan(
          startConcentration: 90,
          dilutionFactor: 3,
          steps: 2,
          direction: DilutionDirection.leftToRight,
        ),
        group: group,
        replicateCount: 1,
        selectedPositions: {
          const WellPosition(rowIndex: 1, columnIndex: 1),
          const WellPosition(rowIndex: 0, columnIndex: 0),
          const WellPosition(rowIndex: 0, columnIndex: 1),
        },
      );

      expect(
        updated
            .wellAt(const WellPosition(rowIndex: 0, columnIndex: 0))
            .concentrationValue,
        90,
      );
      expect(
        updated
            .wellAt(const WellPosition(rowIndex: 0, columnIndex: 1))
            .concentrationValue,
        30,
      );
      expect(
        updated
            .wellAt(const WellPosition(rowIndex: 1, columnIndex: 1))
            .concentrationValue,
        isNull,
      );
    },
  );

  test('requires an explicit valid role for an appended zero control', () {
    for (final role in [null, WellRole.treatment, WellRole.empty]) {
      expect(
        () => service.applySeries(
          plate: Plate(id: 'p', experimentId: 'e', name: 'Plate'),
          plan: const DilutionPlan(
            startConcentration: 10,
            dilutionFactor: 2,
            steps: 1,
            includeZeroControl: true,
          ),
          group: group,
          replicateCount: 1,
          zeroControlRole: role,
        ),
        throwsArgumentError,
      );
    }
  });

  test('only appended controls receive the selected role, even at zero dose',
      () {
    for (final role in PlateDilutionService.zeroControlRoles) {
      final updated = service.applySeries(
        plate: Plate(id: 'p', experimentId: 'e', name: 'Plate'),
        plan: const DilutionPlan(
          startConcentration: 0,
          dilutionFactor: 2,
          steps: 2,
          includeZeroControl: true,
        ),
        group: group,
        replicateCount: 2,
        zeroControlRole: role,
      );
      expect(updated.wells.take(6).map((w) => w.concentrationValue),
          everyElement(0));
      expect(updated.wells.take(4).map((w) => w.role),
          everyElement(WellRole.treatment));
      expect(
          updated.wells.skip(4).take(2).map((w) => w.role), everyElement(role));
      expect(updated.wells[6].role, WellRole.empty);
      expect(updated.wells[5].replicateIndex, 2);
    }
  });

  test('zero treatment remains treatment when no control is requested', () {
    final updated = service.applySeries(
      plate: Plate(id: 'p', experimentId: 'e', name: 'Plate'),
      plan: const DilutionPlan(
        startConcentration: 0,
        dilutionFactor: 2,
        steps: 1,
      ),
      group: group,
      replicateCount: 1,
    );
    expect(updated.wells.first.concentrationValue, 0);
    expect(updated.wells.first.role, WellRole.treatment);
    expect(updated.wells[1].role, WellRole.empty);
  });
}
