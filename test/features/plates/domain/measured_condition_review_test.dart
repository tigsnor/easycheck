import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/plates/domain/measured_condition_review.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_group.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import '../../../support/condition_review_fixture.dart';

void main() {
  test('zero, negative, excluded and edge wells all require condition review',
      () {
    final before = replaceWell(measuredPlate(), 'H12',
        (w) => w.copyWith(resultValue: -0.123456789123, excluded: true));
    var after =
        replaceWell(before, 'A1', (w) => w.copyWith(concentrationValue: 4));
    after = replaceWell(after, 'H12', (w) => w.copyWith(role: WellRole.blank));
    after = replaceWell(after, 'A2', (w) => w.copyWith(concentrationValue: 4));
    final review = MeasuredConditionReview.compare(before, after);
    expect(review.changes.map((c) => c.before.label), ['A1', 'H12']);
    expect(review.otherChangedWellCount, 1);
    expect(review.changes.last.resultBefore, contains('-0.123456789123'));
    expect(review.changes.last.resultBefore, contains('분석 제외'));
    expect(review.record('오기 정정'), contains('정정 사유: 오기 정정'));
    expect(review.record('오기 정정'), contains('농도: 2.0 µM → 4.0 µM'));
    expect(() => review.record('  '), throwsArgumentError);
  });

  test('each condition dimension is protected independently', () {
    final before = measuredPlate();
    final cases = <String, Well Function(Well)>{
      '그룹': (w) => w.copyWith(groupId: null),
      '역할': (w) => w.copyWith(role: WellRole.blank),
      '농도': (w) => w.copyWith(concentrationValue: 4),
      '부피': (w) => w.copyWith(volumeValue: 50),
      '반복 번호': (w) => w.copyWith(replicateIndex: 2),
      '결과 단위': (w) => w.copyWith(resultUnit: 'RFU'),
    };
    for (final entry in cases.entries) {
      final review = MeasuredConditionReview.compare(
          before, replaceWell(before, 'A1', entry.value));
      expect(review.changes.single.fields.map((f) => f.label),
          contains(entry.key));
    }
    expect(
        MeasuredConditionReview.compare(
                before,
                replaceWell(
                    before, 'A1', (w) => w.copyWith(concentrationUnit: 'nM')))
            .changes
            .single
            .fields
            .single
            .label,
        '농도');
    expect(
        MeasuredConditionReview.compare(before,
                replaceWell(before, 'A1', (w) => w.copyWith(volumeUnit: 'mL')))
            .changes
            .single
            .fields
            .single
            .label,
        '부피');
  });

  test(
      'group identity, name and inherited concentration unit changes are visible',
      () {
    final before = replaceWell(
        measuredPlate(), 'A1', (w) => w.copyWith(concentrationUnit: null));
    final renamed = before.copyWith(groups: const [
      WellGroup(
          id: 'g',
          name: 'Drug B',
          shortLabel: 'B',
          color: Colors.blue,
          concentrationUnit: 'nM')
    ]);
    final review = MeasuredConditionReview.compare(before, renamed);
    expect(review.changes.single.fields.map((f) => f.label), ['그룹', '농도']);
    expect(review.changes.single.fields.last.before, contains('µM (그룹 기준)'));
    final sameName = replaceWell(
        before.copyWith(groups: [
          ...before.groups,
          const WellGroup(
              id: 'other', name: 'Drug A', shortLabel: 'A', color: Colors.blue),
        ]),
        'A1',
        (w) => w.copyWith(groupId: 'other'));
    final identity = MeasuredConditionReview.compare(before, sameName);
    expect(identity.changes.single.fields.first.after, contains('다른 그룹'));
    expect(identity.record('그룹 연결 정정'), contains('그룹 연결 ID: g → other'));
  });

  test(
      'notes, exclusion and raw value edits alone do not trigger a condition review',
      () {
    final before = measuredPlate();
    expect(MeasuredConditionReview.compare(before, before).changes, isEmpty);
    final after = replaceWell(before, 'A1',
        (w) => w.copyWith(note: 'bubble', excluded: true, resultValue: -1));
    expect(MeasuredConditionReview.compare(before, after).changes, isEmpty);
    final cleared = replaceWell(
        before, 'A1', (w) => w.copyWith(resultValue: null, resultUnit: null));
    expect(MeasuredConditionReview.compare(before, cleared).changes, isEmpty);
    // Deleting a measurement must not conceal a simultaneous condition change.
    final changedAndCleared =
        replaceWell(cleared, 'A1', (w) => w.copyWith(concentrationValue: 4));
    expect(
        MeasuredConditionReview.compare(before, changedAndCleared)
            .changes
            .single
            .resultAfter,
        '측정값 없음');
  });

  test('removed coordinates are reported and result precision is retained', () {
    final before = replaceWell(measuredPlate(), 'H12',
        (w) => w.copyWith(resultValue: 1.234567891234e-8));
    final after = before.copyWith(
        wells: before.wells.where((w) => w.label != 'H12').toList());
    final review = MeasuredConditionReview.compare(before, after);
    expect(review.changes.single.before.label, 'H12');
    expect(review.changes.single.resultAfter, 'well 없음');
    expect(review.record('배치 정정'), contains('1.234567891234e-8'));
  });

  test(
      'review and original snapshot survive file save and fresh backup recovery',
      () async {
    final root = await Directory.systemTemp.createTemp('condition-review-');
    final restoredRoot =
        await Directory.systemTemp.createTemp('condition-restored-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => restoredRoot.delete(recursive: true));
    final before = measuredPlate();
    final after =
        replaceWell(before, 'A1', (w) => w.copyWith(concentrationValue: 4));
    final record =
        MeasuredConditionReview.compare(before, after).record('실제 분주 기록 확인');
    final saved = after.copyWith(revisions: [
      PlateRevision(
          id: 'r',
          changedAt: DateTime.utc(2026),
          summary: 'well 수정: A1\n$record',
          snapshot: PlateSnapshot.fromPlate(before))
    ]);
    final repo = FilePlateRepository(rootDirectory: root.path);
    await repo.savePlate(saved);
    final loaded = (await repo.loadPlate('e'))!;
    const codec = EasyCheckBackupService();
    final backup = codec.decode(codec.encode(experiments: [
      Experiment(
          id: 'e',
          title: 'Assay',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026))
    ], plates: [
      loaded
    ]));
    await FileBackupRecoveryService(rootDirectory: restoredRoot.path)
        .recover(backup);
    final restored =
        (await FilePlateRepository(rootDirectory: restoredRoot.path)
            .loadPlate('e'))!;
    expect(restored.toJson(), saved.toJson());
    expect(restored.revisions.single.snapshot!.wells.first.toJson(),
        before.wells.first.toJson());
    expect(restored.revisions.single.summary, contains('실제 분주 기록 확인'));
  });
}
