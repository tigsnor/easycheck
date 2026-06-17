class PipettingPlan {
  const PipettingPlan({
    required this.stockConcentration,
    required this.concentrationUnit,
    required this.volumePerWell,
    required this.volumeUnit,
    required this.replicateCount,
    required this.overagePercent,
    required this.steps,
  });

  final double stockConcentration;
  final String concentrationUnit;
  final double volumePerWell;
  final String volumeUnit;
  final int replicateCount;
  final double overagePercent;
  final List<PipettingStep> steps;

  double get totalPreparedVolume =>
      steps.fold(0, (total, step) => total + step.totalVolume);
}

class PipettingStep {
  const PipettingStep({
    required this.concentration,
    required this.totalVolume,
    required this.stockVolume,
    required this.diluentVolume,
  });

  final double concentration;
  final double totalVolume;
  final double stockVolume;
  final double diluentVolume;

  bool get hasLowStockVolume => stockVolume > 0 && stockVolume < 1;
}

class PipettingPlanService {
  const PipettingPlanService();

  PipettingPlan buildDirectDilutionPlan({
    required double stockConcentration,
    required String concentrationUnit,
    required List<double> concentrations,
    required double volumePerWell,
    required String volumeUnit,
    required int replicateCount,
    double overagePercent = 10,
  }) {
    if (!stockConcentration.isFinite || stockConcentration <= 0) {
      throw ArgumentError.value(
        stockConcentration,
        'stockConcentration',
        'must be greater than zero',
      );
    }
    if (!volumePerWell.isFinite || volumePerWell <= 0) {
      throw ArgumentError.value(
        volumePerWell,
        'volumePerWell',
        'must be greater than zero',
      );
    }
    if (replicateCount <= 0) {
      throw ArgumentError.value(
        replicateCount,
        'replicateCount',
        'must be greater than zero',
      );
    }
    if (!overagePercent.isFinite || overagePercent < 0) {
      throw ArgumentError.value(
        overagePercent,
        'overagePercent',
        'must be zero or greater',
      );
    }
    if (concentrations.isEmpty ||
        concentrations.any(
          (concentration) =>
              !concentration.isFinite ||
              concentration < 0 ||
              concentration > stockConcentration,
        )) {
      throw ArgumentError.value(
        concentrations,
        'concentrations',
        'must be between zero and the stock concentration',
      );
    }

    final totalVolume =
        volumePerWell * replicateCount * (1 + overagePercent / 100);
    final steps = [
      for (final concentration in concentrations)
        _buildStep(
          stockConcentration: stockConcentration,
          concentration: concentration,
          totalVolume: totalVolume,
        ),
    ];

    return PipettingPlan(
      stockConcentration: stockConcentration,
      concentrationUnit: concentrationUnit,
      volumePerWell: volumePerWell,
      volumeUnit: volumeUnit,
      replicateCount: replicateCount,
      overagePercent: overagePercent,
      steps: steps,
    );
  }

  PipettingStep _buildStep({
    required double stockConcentration,
    required double concentration,
    required double totalVolume,
  }) {
    final stockVolume = totalVolume * concentration / stockConcentration;
    return PipettingStep(
      concentration: concentration,
      totalVolume: _normalize(totalVolume),
      stockVolume: _normalize(stockVolume),
      diluentVolume: _normalize(totalVolume - stockVolume),
    );
  }

  double _normalize(double value) {
    final fixed = value.toStringAsFixed(10);
    return double.parse(fixed.replaceFirst(RegExp(r'\.?0+$'), ''));
  }
}
