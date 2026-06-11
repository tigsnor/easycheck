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
}
