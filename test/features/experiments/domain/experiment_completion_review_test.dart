import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/experiment_completion_review.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/analysis_reference_fixture.dart';

void main() {
  const service = ExperimentCompletionReviewService();
  final experiment = Experiment(
      id: 'e',
      title: 'Assay',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026));
  Plate empty() => Plate(id: 'p', experimentId: 'e', name: 'Plate');

  test('flags all missing assigned wells, excludes unused and excluded wells',
      () {
    final p = empty();
    final plate = p.copyWith(wells: [
      for (final w in p.wells)
        if (w.label == 'A1')
          w.copyWith(role: WellRole.sample)
        else if (w.label == 'H12')
          w.copyWith(volumeValue: 10)
        else if (w.label == 'A2')
          w.copyWith(role: WellRole.sample, excluded: true)
        else
          w
    ]);
    final review = service.review(experiment, plate);
    expect(
        review.issues
            .singleWhere((i) => i.title.startsWith('결과 미입력'))
            .wellLabels,
        ['A1', 'H12']);
    expect(
        review.issues
            .singleWhere((i) => i.title.startsWith('분석 제외'))
            .wellLabels,
        ['A2']);
  });

  test(
      'zero and negative results are measured; missing and mixed units distinct',
      () {
    final p = empty();
    final plate = p.copyWith(wells: [
      for (final w in p.wells)
        if (w.label == 'A1')
          w.copyWith(resultValue: 0, resultUnit: ' OD450 ')
        else if (w.label == 'A2')
          w.copyWith(resultValue: -1, resultUnit: 'OD450')
        else if (w.label == 'A3')
          w.copyWith(resultValue: 2)
        else
          w
    ]);
    final issues = service.review(experiment, plate).issues;
    expect(issues.where((i) => i.title.startsWith('결과 미입력')), isEmpty);
    expect(
        issues.singleWhere((i) => i.title == '결과 단위 미입력').wellLabels, ['A3']);
    expect(issues.singleWhere((i) => i.title.endsWith('결과 단위 혼용')).wellLabels,
        ['A1', 'A2', 'A3']);
  });

  test(
      'missing plate and unfinished tasks are reviewable; not 96 missing wells',
      () {
    final review = service.review(
        experiment.copyWith(tasks: const [
          ExperimentTask(id: '1', title: '측정'),
          ExperimentTask(id: '2', title: '준비', isCompleted: true),
        ]),
        null);
    expect(review.issues.length, 2);
    expect(review.issues.first.message, '측정');
    expect(service.review(experiment, empty()).issues.single.title,
        'Plate layout이 비어 있습니다');
  });

  test('analysis reference failures are included without altering results', () {
    final p = referencePlate(manual: true);
    final plate = p.copyWith(wells: [
      for (final w in p.wells) w.label == 'A1' ? w.copyWith(excluded: true) : w
    ]);
    final before = plate.toJson().toString();
    final review = service.review(experiment, plate);
    expect(
        review.issues
            .where((i) => i.title.startsWith('분석 기준 확인'))
            .any((i) => i.message.contains('A1')),
        true);
    expect(plate.toJson().toString(), before);
  });

  test('completion snapshot and note survive backup round trip', () {
    final review = service.review(experiment, null);
    final completed = experiment.copyWith(
        status: ExperimentStatus.completed,
        completedAt: DateTime.utc(2026),
        revisions: [
          ExperimentRevision(
              id: 'r',
              changedAt: DateTime.utc(2026),
              summary: '실험 완료',
              reason: review.record('현미경 관찰만 수행'))
        ]);
    const backups = EasyCheckBackupService();
    final restored = backups
        .decode(backups.encode(experiments: [completed], plates: []))
        .experiments
        .single;
    expect(restored.revisions.single.reason, completed.revisions.single.reason);
    expect(restored.revisions.single.reason, contains('현미경 관찰만 수행'));
    expect(restored.status, ExperimentStatus.completed);
  });
}
