import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/dilution/domain/dilution_plan.dart';
import 'package:easycheck/features/dilution/domain/dilution_service.dart';

void main() {
  group('DilutionService', () {
    test('builds a 2-fold dilution series with zero control', () {
      const service = DilutionService();
      const plan = DilutionPlan(
        startConcentration: 1000,
        dilutionFactor: 2,
        steps: 6,
        includeZeroControl: true,
      );

      expect(service.buildSeries(plan), [
        1000.0,
        500.0,
        250.0,
        125.0,
        62.5,
        31.25,
        0.0,
      ]);
    });

    test('builds a 10-fold dilution series without zero control', () {
      const service = DilutionService();
      const plan = DilutionPlan(
        startConcentration: 100,
        dilutionFactor: 10,
        steps: 4,
      );

      expect(service.buildSeries(plan), [100.0, 10.0, 1.0, 0.1]);
    });
  });
}
