import 'dilution_direction.dart';

class DilutionPlan {
  const DilutionPlan({
    required this.startConcentration,
    required this.dilutionFactor,
    required this.steps,
    this.includeZeroControl = false,
    this.direction = DilutionDirection.topToBottom,
  })  : assert(startConcentration >= 0),
        assert(dilutionFactor > 0),
        assert(steps > 0);

  final double startConcentration;
  final double dilutionFactor;
  final int steps;
  final bool includeZeroControl;
  final DilutionDirection direction;
}
