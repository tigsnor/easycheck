import 'dilution_plan.dart';

class DilutionService {
  const DilutionService();

  List<double> buildSeries(DilutionPlan plan) {
    final concentrations = <double>[];

    for (var index = 0; index < plan.steps; index++) {
      final divisor = _pow(plan.dilutionFactor, index);
      concentrations.add(_normalize(plan.startConcentration / divisor));
    }

    if (plan.includeZeroControl) {
      concentrations.add(0);
    }

    return concentrations;
  }

  double _pow(double base, int exponent) {
    var value = 1.0;
    for (var index = 0; index < exponent; index++) {
      value *= base;
    }
    return value;
  }

  double _normalize(double value) {
    final fixed = value.toStringAsFixed(10);
    return double.parse(fixed.replaceFirst(RegExp(r'\.?0+$'), ''));
  }
}
