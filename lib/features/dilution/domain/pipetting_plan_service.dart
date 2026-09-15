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

class SerialTransferPlan {
  const SerialTransferPlan({
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
  final List<SerialTransferStep> steps;
}

class SerialTransferStep {
  const SerialTransferStep({
    required this.concentration,
    required this.sourceConcentration,
    required this.totalVolume,
    required this.sourceVolume,
    required this.diluentVolume,
    required this.transferToNextVolume,
    required this.dispenseVolume,
  });

  final double concentration;
  final double? sourceConcentration;
  final double totalVolume;
  final double sourceVolume;
  final double diluentVolume;
  final double transferToNextVolume;
  final double dispenseVolume;

  bool get hasLowSourceVolume => sourceVolume > 0 && sourceVolume < 1;
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

  SerialTransferPlan buildSerialTransferPlan({
    required double stockConcentration,
    required String concentrationUnit,
    required List<double> concentrations,
    required double volumePerWell,
    required String volumeUnit,
    required int replicateCount,
    double overagePercent = 10,
  }) {
    _validateInputs(
      stockConcentration: stockConcentration,
      concentrations: concentrations,
      volumePerWell: volumePerWell,
      replicateCount: replicateCount,
      overagePercent: overagePercent,
    );

    final positiveConcentrations =
        concentrations.where((concentration) => concentration > 0).toList();
    for (var index = 1; index < positiveConcentrations.length; index++) {
      if (positiveConcentrations[index] >= positiveConcentrations[index - 1]) {
        throw ArgumentError.value(
          concentrations,
          'concentrations',
          'must be ordered from highest to lowest for serial transfer',
        );
      }
    }

    final dispenseVolume =
        volumePerWell * replicateCount * (1 + overagePercent / 100);
    final requiredVolumes = List<double>.filled(
      positiveConcentrations.length,
      dispenseVolume,
    );
    for (var index = positiveConcentrations.length - 2; index >= 0; index--) {
      final nextRequired = requiredVolumes[index + 1];
      final transferToNext = nextRequired *
          positiveConcentrations[index + 1] /
          positiveConcentrations[index];
      requiredVolumes[index] += transferToNext;
    }

    final steps = <SerialTransferStep>[];
    for (var index = 0; index < positiveConcentrations.length; index++) {
      final concentration = positiveConcentrations[index];
      final sourceConcentration =
          index == 0 ? stockConcentration : positiveConcentrations[index - 1];
      final totalVolume = requiredVolumes[index];
      final sourceVolume = totalVolume * concentration / sourceConcentration;
      final transferToNext = index == positiveConcentrations.length - 1
          ? 0.0
          : requiredVolumes[index + 1] *
              positiveConcentrations[index + 1] /
              concentration;
      steps.add(
        SerialTransferStep(
          concentration: concentration,
          sourceConcentration: sourceConcentration,
          totalVolume: _normalize(totalVolume),
          sourceVolume: _normalize(sourceVolume),
          diluentVolume: _normalize(totalVolume - sourceVolume),
          transferToNextVolume: _normalize(transferToNext),
          dispenseVolume: _normalize(dispenseVolume),
        ),
      );
    }
    if (concentrations.any((concentration) => concentration == 0)) {
      steps.add(
        SerialTransferStep(
          concentration: 0,
          sourceConcentration: null,
          totalVolume: _normalize(dispenseVolume),
          sourceVolume: 0,
          diluentVolume: _normalize(dispenseVolume),
          transferToNextVolume: 0,
          dispenseVolume: _normalize(dispenseVolume),
        ),
      );
    }

    return SerialTransferPlan(
      stockConcentration: stockConcentration,
      concentrationUnit: concentrationUnit,
      volumePerWell: volumePerWell,
      volumeUnit: volumeUnit,
      replicateCount: replicateCount,
      overagePercent: overagePercent,
      steps: steps,
    );
  }

  void _validateInputs({
    required double stockConcentration,
    required List<double> concentrations,
    required double volumePerWell,
    required int replicateCount,
    required double overagePercent,
  }) {
    if (!stockConcentration.isFinite || stockConcentration <= 0) {
      throw ArgumentError.value(stockConcentration, 'stockConcentration');
    }
    if (!volumePerWell.isFinite || volumePerWell <= 0) {
      throw ArgumentError.value(volumePerWell, 'volumePerWell');
    }
    if (replicateCount <= 0) {
      throw ArgumentError.value(replicateCount, 'replicateCount');
    }
    if (!overagePercent.isFinite || overagePercent < 0) {
      throw ArgumentError.value(overagePercent, 'overagePercent');
    }
    if (concentrations.isEmpty ||
        concentrations.any(
          (concentration) =>
              !concentration.isFinite ||
              concentration < 0 ||
              concentration > stockConcentration,
        )) {
      throw ArgumentError.value(concentrations, 'concentrations');
    }
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
