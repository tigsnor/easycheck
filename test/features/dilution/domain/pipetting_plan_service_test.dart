import 'package:easycheck/features/dilution/domain/pipetting_plan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = PipettingPlanService();

  test('builds direct stock dilution volumes with replicate overage', () {
    final plan = service.buildDirectDilutionPlan(
      stockConcentration: 1000,
      concentrationUnit: 'µM',
      concentrations: const [100, 50, 0],
      volumePerWell: 100,
      volumeUnit: 'µL',
      replicateCount: 2,
      overagePercent: 10,
    );

    expect(plan.steps, hasLength(3));
    expect(plan.steps[0].totalVolume, 220);
    expect(plan.steps[0].stockVolume, 22);
    expect(plan.steps[0].diluentVolume, 198);
    expect(plan.steps[1].stockVolume, 11);
    expect(plan.steps[1].diluentVolume, 209);
    expect(plan.steps[2].stockVolume, 0);
    expect(plan.steps[2].diluentVolume, 220);
    expect(plan.totalPreparedVolume, 660);
  });

  test('marks sub-microliter stock volumes as low volume', () {
    final plan = service.buildDirectDilutionPlan(
      stockConcentration: 10000,
      concentrationUnit: 'µM',
      concentrations: const [1],
      volumePerWell: 100,
      volumeUnit: 'µL',
      replicateCount: 1,
      overagePercent: 0,
    );

    expect(plan.steps.single.stockVolume, 0.01);
    expect(plan.steps.single.hasLowStockVolume, isTrue);
  });

  test('rejects a target concentration above the stock concentration', () {
    expect(
      () => service.buildDirectDilutionPlan(
        stockConcentration: 50,
        concentrationUnit: 'µM',
        concentrations: const [100],
        volumePerWell: 100,
        volumeUnit: 'µL',
        replicateCount: 1,
      ),
      throwsArgumentError,
    );
  });

  test('builds serial transfers backwards to preserve dispense volume', () {
    final plan = service.buildSerialTransferPlan(
      stockConcentration: 1000,
      concentrationUnit: 'µM',
      concentrations: const [100, 50, 25, 0],
      volumePerWell: 100,
      volumeUnit: 'µL',
      replicateCount: 2,
      overagePercent: 10,
    );

    expect(plan.steps, hasLength(4));
    expect(plan.steps[0].totalVolume, 385);
    expect(plan.steps[0].sourceVolume, 38.5);
    expect(plan.steps[0].transferToNextVolume, 165);
    expect(plan.steps[0].dispenseVolume, 220);
    expect(plan.steps[1].totalVolume, 330);
    expect(plan.steps[1].sourceVolume, 165);
    expect(plan.steps[1].transferToNextVolume, 110);
    expect(plan.steps[2].totalVolume, 220);
    expect(plan.steps[2].sourceVolume, 110);
    expect(plan.steps[2].transferToNextVolume, 0);
    expect(plan.steps[3].concentration, 0);
    expect(plan.steps[3].sourceConcentration, isNull);
    expect(plan.steps[3].diluentVolume, 220);
  });

  test('rejects ascending concentrations for serial transfer', () {
    expect(
      () => service.buildSerialTransferPlan(
        stockConcentration: 1000,
        concentrationUnit: 'µM',
        concentrations: const [50, 100],
        volumePerWell: 100,
        volumeUnit: 'µL',
        replicateCount: 2,
      ),
      throwsArgumentError,
    );
  });
}
