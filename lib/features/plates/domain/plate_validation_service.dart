import 'plate.dart';
import 'well.dart';
import 'well_role.dart';

enum PlateValidationSeverity { warning, info }

class PlateValidationIssue {
  const PlateValidationIssue({
    required this.code,
    required this.severity,
    required this.title,
    required this.message,
    this.wellLabels = const [],
  });

  final String code;
  final PlateValidationSeverity severity;
  final String title;
  final String message;
  final List<String> wellLabels;
}

class PlateValidationReport {
  const PlateValidationReport(this.issues);

  final List<PlateValidationIssue> issues;

  bool get isReady => warningCount == 0;

  int get warningCount => issues
      .where((issue) => issue.severity == PlateValidationSeverity.warning)
      .length;

  int get infoCount => issues
      .where((issue) => issue.severity == PlateValidationSeverity.info)
      .length;
}

class PlateValidationService {
  const PlateValidationService();

  static const _controlRoles = {
    WellRole.negativeControl,
    WellRole.positiveControl,
    WellRole.vehicleControl,
    WellRole.untreatedControl,
  };

  static const _replicateRoles = {
    WellRole.treatment,
    WellRole.sample,
    WellRole.standard,
  };

  PlateValidationReport validate(Plate plate) {
    final activeWells = plate.wells.where(_isActive).toList();
    if (activeWells.isEmpty) {
      return const PlateValidationReport([
        PlateValidationIssue(
          code: 'layout_empty',
          severity: PlateValidationSeverity.info,
          title: 'Plate layout이 비어 있습니다',
          message: '실험군을 지정하거나 희석 계산을 적용해 주세요.',
        ),
      ]);
    }

    final issues = <PlateValidationIssue>[
      if (!activeWells.any((well) => well.role == WellRole.blank))
        const PlateValidationIssue(
          code: 'blank_missing',
          severity: PlateValidationSeverity.warning,
          title: 'Blank가 없습니다',
          message: '배경 신호 보정을 위해 Blank well 추가를 검토하세요.',
        ),
      if (!activeWells.any((well) => _controlRoles.contains(well.role)))
        const PlateValidationIssue(
          code: 'control_missing',
          severity: PlateValidationSeverity.warning,
          title: 'Control이 없습니다',
          message:
              '결과 비교를 위한 positive, negative, vehicle 또는 untreated control을 추가하세요.',
        ),
    ];

    issues.addAll(_mixedUnitIssues(plate, activeWells));
    final replicateIssue = _replicateIssue(plate, activeWells);
    if (replicateIssue != null) {
      issues.add(replicateIssue);
    }

    final includedWells = activeWells.where((well) => !well.excluded).toList();
    final enteredResultCount =
        includedWells.where((well) => well.resultValue != null).length;
    if (enteredResultCount > 0 && enteredResultCount < includedWells.length) {
      final missingWells =
          includedWells.where((well) => well.resultValue == null).toList();
      issues.add(
        PlateValidationIssue(
          code: 'result_incomplete',
          severity: PlateValidationSeverity.info,
          title: '측정 결과가 일부만 입력되었습니다',
          message: '${missingWells.length}개 well의 결과값이 비어 있습니다.',
          wellLabels: missingWells.map((well) => well.label).toList(),
        ),
      );
    }

    final excludedWells = activeWells.where((well) => well.excluded).toList();
    if (excludedWells.isNotEmpty) {
      issues.add(
        PlateValidationIssue(
          code: 'excluded_wells',
          severity: PlateValidationSeverity.info,
          title: '분석 제외 well이 있습니다',
          message: '${excludedWells.length}개 well이 결과 분석에서 제외됩니다.',
          wellLabels: excludedWells.map((well) => well.label).toList(),
        ),
      );
    }

    return PlateValidationReport(issues);
  }

  Iterable<PlateValidationIssue> _mixedUnitIssues(
    Plate plate,
    List<Well> activeWells,
  ) sync* {
    for (final group in plate.groups) {
      final groupWells =
          activeWells.where((well) => well.groupId == group.id).toList();
      final units = groupWells
          .map((well) => well.concentrationUnit)
          .whereType<String>()
          .where((unit) => unit.trim().isNotEmpty)
          .toSet();
      if (units.length > 1) {
        yield PlateValidationIssue(
          code: 'mixed_units_${group.id}',
          severity: PlateValidationSeverity.warning,
          title: '${group.name}의 농도 단위가 섞여 있습니다',
          message: '사용 중인 단위: ${units.join(', ')}',
          wellLabels: groupWells.map((well) => well.label).toList(),
        );
      }
    }
  }

  PlateValidationIssue? _replicateIssue(Plate plate, List<Well> activeWells) {
    final counts = <String, List<Well>>{};
    for (final well in activeWells) {
      if (!_replicateRoles.contains(well.role) || well.excluded) {
        continue;
      }
      final concentration = well.concentrationValue;
      if (well.groupId == null || concentration == null) {
        continue;
      }
      final key =
          '${well.groupId}|$concentration|${well.concentrationUnit ?? ''}';
      counts.putIfAbsent(key, () => []).add(well);
    }

    final insufficient =
        counts.values.where((wells) => wells.length < 2).toList();
    if (insufficient.isEmpty) {
      return null;
    }

    final groupNames = {for (final group in plate.groups) group.id: group.name};
    final labels = insufficient
        .expand((wells) => wells)
        .map((well) => well.label)
        .toList();
    final affectedGroups = insufficient
        .map((wells) => groupNames[wells.first.groupId] ?? '이름 없는 그룹')
        .toSet()
        .join(', ');
    return PlateValidationIssue(
      code: 'replicate_insufficient',
      severity: PlateValidationSeverity.warning,
      title: '반복 well이 부족한 조건이 있습니다',
      message: '$affectedGroups의 ${insufficient.length}개 조건이 반복 2개 미만입니다.',
      wellLabels: labels,
    );
  }

  bool _isActive(Well well) {
    return well.groupId != null ||
        well.role != WellRole.empty ||
        well.concentrationValue != null ||
        well.resultValue != null;
  }
}
