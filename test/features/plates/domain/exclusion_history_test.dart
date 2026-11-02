import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/exclusion_comparison.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/domain/plate_exclusion_event.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/assay_condition_fixture.dart';
import '../../../support/exclusion_event_fixture.dart';
import '../../../support/cell_condition_fixture.dart';

void main() {
  test(
      'events retain raw zero and reject malformed state, reason, date, number and duplicate IDs',
      () {
    final event = exclusionEvent(0);
    expect(
        PlateExclusionEvent.fromJson(event.toJson()).toJson(), event.toJson());
    for (final bad in <Map<String, Object?>>[
      {'wellLabel': 'A0'},
      {'changedAt': 'yesterday'},
      {'changedAt': '2026-02-30T10:00:00Z'},
      {'changedAt': '2026-11-02T10:00:00'},
      {'source': 'unknown'},
      {'reason': ' '},
      {'beforeExcluded': 'false'},
      {'afterExcluded': false},
      {'beforeResult': double.nan},
      {'afterResult': '0'},
      {'beforeUnit': 42},
    ]) {
      expect(() => PlateExclusionEvent.fromJson({...event.toJson(), ...bad}),
          throwsFormatException);
    }
    expect(
        () => PlateExclusionEvent.parseList([event.toJson(), event.toJson()]),
        throwsFormatException);
    expect(PlateExclusionEvent.parseList(null), isEmpty);
    final before = assayPlate();
    final after = before.copyWith(wells: [
      for (final w in before.wells)
        w.label == 'A1' ? w.copyWith(excluded: true) : w
    ]);
    final changes = PlateExclusionEvent.changes(
        before: before.wells,
        after: after.wells,
        at: DateTime.utc(2026),
        actionId: 'action',
        source: ExclusionChangeSource.undo,
        reason: '실행 취소');
    expect(changes.single.wellLabel, 'A1');
    expect(changes.single.beforeResult, before.wells.first.resultValue);
    expect(changes.single.afterResult, before.wells.first.resultValue);
  });

  test(
      'comparison restores selected observations virtually and separates all-excluded series',
      () {
    final p = assayPlate();
    final plate = p.copyWith(wells: [
      for (final w in p.wells)
        w.label == 'A1'
            ? w.copyWith(resultValue: 10)
            : w.label == 'A2'
                ? w.copyWith(resultValue: 30, excluded: true)
                : w
    ]);
    final before = jsonEncode(plate.toJson());
    final comparison = ExclusionComparison(plate, wellLabel: 'A2');
    final row = comparison.rows.singleWhere((r) =>
        (r.current ?? r.hypothetical)!.role == WellRole.treatment &&
        (r.current ?? r.hypothetical)!.assayCondition == dmsoLow);
    expect(row.current!.rawMean, 10);
    expect(row.current!.standardDeviation, isNull);
    expect(row.hypothetical!.rawMean, 20);
    expect(row.hypothetical!.standardDeviation, closeTo(14.1421356, 1e-6));
    expect(comparison.reinstatedLabels, ['A2']);
    expect(jsonEncode(plate.toJson()), before);
    final allExcluded = plate.copyWith(wells: [
      for (final w in plate.wells)
        ['A1', 'A2'].contains(w.label) ? w.copyWith(excluded: true) : w
    ]);
    final emptyRow = ExclusionComparison(allExcluded).rows.singleWhere((r) =>
        (r.current ?? r.hypothetical)!.role == WellRole.treatment &&
        (r.current ?? r.hypothetical)!.assayCondition == dmsoLow);
    expect(emptyRow.current, isNull);
    expect(emptyRow.hypothetical!.rawMean, 20);
  });

  test(
      'control/blank reinstatement recalculates other series without relaxing cell/assay/unit matching',
      () {
    final p = assayPlate();
    final plate = p.copyWith(wells: [
      for (final w in p.wells)
        ['A3', 'A4', 'B3'].contains(w.label) ? w.copyWith(excluded: true) : w
    ], analysisReferences: [
      const PlateAnalysisReferenceSelection(
          groupId: 'drug',
          resultUnit: 'OD450',
          cellCondition: hekLow,
          assayCondition: dmsoLow,
          blankWellLabels: ['A4'],
          controlWellLabels: ['A3'])
    ]);
    final comparison = ExclusionComparison(plate);
    final row = comparison.rows.singleWhere((r) =>
        (r.current ?? r.hypothetical)!.role == WellRole.treatment &&
        (r.current ?? r.hypothetical)!.assayCondition == dmsoLow);
    expect(row.current!.normalizedPercent, isNull);
    expect(row.current!.reference!.warnings.join(), contains('기준 확인 필요'));
    expect(row.hypothetical!.normalizedPercent, closeTo(66.6666667, 1e-6));
    expect(row.hypothetical!.reference!.controlWellLabels, ['A3']);
    final onlyOther = ExclusionComparison(plate, wellLabel: 'B3');
    final unchanged = onlyOther.hypothetical.series.singleWhere(
        (s) => s.role == WellRole.treatment && s.assayCondition == dmsoLow);
    expect(unchanged.normalizedPercent, isNull);
    final unmeasured = p.copyWith(wells: [
      for (final w in p.wells) w.label == 'H12' ? w.copyWith(excluded: true) : w
    ]);
    final noResult = ExclusionComparison(unmeasured, wellLabel: 'H12');
    expect(noResult.current.includedWellCount,
        noResult.hypothetical.includedWellCount);
  });

  test(
      'more than twenty events persist through file restart and fresh backup recovery; legacy data and templates remain compatible',
      () async {
    final root = await Directory.systemTemp.createTemp('exclusion-events-');
    final recovery =
        await Directory.systemTemp.createTemp('exclusion-recovery-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => recovery.delete(recursive: true));
    final p = assayPlate().copyWith(
        exclusionEvents: [for (var i = 0; i < 35; i++) exclusionEvent(i)]);
    final repo = FilePlateRepository(rootDirectory: root.path);
    await repo.savePlate(p);
    expect(
        (await FilePlateRepository(rootDirectory: root.path).loadPlate('e'))!
            .exclusionEvents,
        hasLength(35));
    const codec = EasyCheckBackupService();
    final encoded = codec.encode(experiments: [
      Experiment(
          id: 'e',
          title: 'Assay',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026))
    ], plates: [
      p
    ]);
    final backup = codec.decode(encoded);
    expect(backup.schemaVersion, 11);
    await FileBackupRecoveryService(rootDirectory: recovery.path)
        .recover(backup);
    final restored = (await FilePlateRepository(rootDirectory: recovery.path)
        .loadPlate('e'))!;
    expect(restored.toJson(), p.toJson());
    final malformed = jsonDecode(encoded);
    malformed['plates'][0]['exclusionEvents'][0]['afterExcluded'] = 'true';
    expect(() => codec.decode(jsonEncode(malformed)), throwsFormatException);
    final old = p.toJson()..remove('exclusionEvents');
    await File('${root.path}/plates/e.json')
        .writeAsString(jsonEncode({'schemaVersion': 4, 'data': old}));
    expect((await repo.loadPlate('e'))!.exclusionEvents, isEmpty);
    final oldBackup = jsonDecode(encoded)..['schemaVersion'] = 10;
    oldBackup['plates'] = [old];
    expect(codec.decode(jsonEncode(oldBackup)).plates.single.exclusionEvents,
        isEmpty);
    final template = PlateTemplate.fromPlate(id: 't', name: 'Design', plate: p);
    expect(
        template
            .instantiate(plateId: 'copy', experimentId: 'copy')
            .exclusionEvents,
        isEmpty);
    expect(
        PlateSnapshot.fromPlate(p)
            .restore(id: 'p', experimentId: 'e')
            .exclusionEvents,
        isEmpty);
  });
}
