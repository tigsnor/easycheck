import '../../plates/domain/plate.dart';
import '../../plates/domain/plate_analysis_service.dart';
import '../../plates/domain/plate_validation_service.dart';
import '../../plates/domain/well.dart';
import '../../plates/domain/well_role.dart';
import 'experiment.dart';

class CompletionReviewIssue {
  const CompletionReviewIssue(this.title, this.message,
      {this.wellLabels = const []});
  final String title;
  final String message;
  final List<String> wellLabels;
}

class ExperimentCompletionReview {
  const ExperimentCompletionReview(this.issues);
  final List<CompletionReviewIssue> issues;

  String record(String note) => [
        '완료 전 점검: ${issues.length}개 확인 항목',
        for (final issue in issues)
          '${issue.title}: ${issue.message}'
              '${issue.wellLabels.isEmpty ? '' : ' [${issue.wellLabels.join(', ')}]'}',
        if (note.trim().isNotEmpty) '검토 메모: ${note.trim()}',
      ].join('\n');
}

class ExperimentCompletionReviewService {
  const ExperimentCompletionReviewService();

  ExperimentCompletionReview review(Experiment experiment, Plate? plate) {
    final issues = <CompletionReviewIssue>[];
    final unfinished = experiment.tasks.where((task) => !task.isCompleted);
    if (unfinished.isNotEmpty) {
      issues.add(CompletionReviewIssue('미완료 단계 ${unfinished.length}개',
          unfinished.map((task) => task.title).join(', ')));
    }
    if (plate == null) {
      issues.add(const CompletionReviewIssue(
          'Plate 기록이 없습니다', 'Plate를 사용하지 않은 실험이면 검토 메모에 사유를 남겨 주세요.'));
      return ExperimentCompletionReview(issues);
    }
    final active = plate.wells.where((well) =>
        well.cellCondition != null ||
        well.groupId != null ||
        well.role != WellRole.empty ||
        well.concentrationValue != null ||
        well.volumeValue != null ||
        well.resultValue != null ||
        well.excluded);
    final included = active.where((well) => !well.excluded).toList();
    final missing = included.where((well) => well.resultValue == null).toList();
    void addWells(String title, String message, List<Well> wells) {
      if (wells.isNotEmpty) {
        issues.add(CompletionReviewIssue(title, message,
            wellLabels: wells.map((well) => well.label).toList()));
      }
    }

    addWells('결과 미입력 ${missing.length}개', '배치된 well의 측정 결과를 확인해 주세요.', missing);
    final excluded = plate.wells.where((well) => well.excluded).toList();
    addWells(
        '분석 제외 ${excluded.length}개', '의도한 제외인지 확인하고 사유를 남겨 주세요.', excluded);
    final measured =
        included.where((well) => well.resultValue != null).toList();
    addWells(
        '결과 단위 미입력',
        '단위가 없는 값입니다. 무차원 값이면 메모에 명시해 주세요.',
        measured
            .where((well) => (well.resultUnit ?? '').trim().isEmpty)
            .toList());
    final byGroup = <String?, List<Well>>{};
    for (final well in measured) {
      byGroup.putIfAbsent(well.groupId, () => []).add(well);
    }
    final names = {for (final group in plate.groups) group.id: group.name};
    for (final entry in byGroup.entries) {
      final units =
          entry.value.map((well) => (well.resultUnit ?? '').trim()).toSet();
      if (units.length > 1) {
        addWells(
            '${names[entry.key] ?? '그룹 없음'}의 결과 단위 혼용',
            '단위별로 따로 분석됩니다: ${units.map((u) => u.isEmpty ? '단위 없음' : u).join(', ')}',
            entry.value);
      }
    }
    for (final issue in const PlateValidationService().validate(plate).issues) {
      if (issue.code == 'result_incomplete' || issue.code == 'excluded_wells') {
        continue;
      }
      issues.add(CompletionReviewIssue(issue.title, issue.message,
          wellLabels: issue.wellLabels));
    }
    // Reuse the same reference validation as the analysis and export screens.
    final seen = <String>{};
    for (final series in const PlateAnalysisService().analyze(plate).series) {
      for (final warning in series.reference?.warnings ?? <String>[]) {
        final key =
            '${series.groupId}|${series.resultUnit}|${series.cellCondition?.key}|$warning';
        if (seen.add(key)) {
          issues.add(CompletionReviewIssue(
              '분석 기준 확인: ${series.label}${series.cellCondition == null ? '' : ' · ${series.cellCondition!.label}'}',
              warning,
              wellLabels: {
                ...series.includedWellLabels,
                ...?series.reference?.blankWellLabels,
                ...?series.reference?.controlWellLabels
              }
                  .where(
                      (label) => plate.wells.any((well) => well.label == label))
                  .toList()));
        }
      }
    }
    return ExperimentCompletionReview(issues);
  }
}
