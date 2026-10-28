import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_export_service.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/analysis_reference_fixture.dart';

void main() {
  const service = PlateAnalysisService();
  PlateAnalysisSeries drugA(Plate p) =>
      service.analyze(p).series.singleWhere((s) => s.groupId == 'a');

  test('separates references for two treatments sharing a result unit', () {
    final plate = referencePlate(manual: true);
    final report = service.analyze(plate);
    final a = drugA(plate);
    final b = report.series.singleWhere((s) => s.groupId == 'b');
    expect(a.normalizedPercent, closeTo(50, 1e-9));
    expect(b.normalizedPercent, closeTo(50, 1e-9));
    expect(a.reference!.blankWellLabels, ['A1']);
    expect(a.reference!.controlWellLabels, ['B1']);
    expect(b.reference!.controlWellLabels, ['B2']);
    expect(a.reference!.controlCorrectedMean, closeTo(1, 1e-9));
    expect(b.reference!.controlCorrectedMean, closeTo(2, 1e-9));
    final tsv = const PlateAnalysisExportService().buildTsv(plate, report);
    expect(
        tsv,
        contains(
            'a\tDrug A\ttreatment\t10\tµM\tOD450\tmanual\tA1\tB1\t0.1\t1.1\t1'));
    expect(
        tsv,
        contains(
            'b\tDrug B\ttreatment\t10\tµM\tOD450\tmanual\tA2\tB2\t0.2\t2.2\t2'));
  });

  test(
      'legacy automatic references retain role priority and expose coordinates',
      () {
    final a = drugA(referencePlate());
    expect(a.reference!.manual, false);
    expect(a.reference!.blankWellLabels, ['A1', 'A2']);
    expect(a.reference!.controlWellLabels, ['B1', 'B2']);
    expect(a.normalizedPercent, closeTo(30, 1e-9));
    final manual = referencePlate(manual: true);
    expect(
        drugA(manual.copyWith(analysisReferences: [referenceB]))
            .normalizedPercent,
        closeTo(30, 1e-9));
  });

  test(
      'averages selected replicates but never silently drops an invalid reference',
      () {
    final plate = referencePlate().copyWith(analysisReferences: [
      const PlateAnalysisReferenceSelection(
          groupId: 'a',
          resultUnit: 'OD450',
          blankWellLabels: ['A1', 'A2'],
          controlWellLabels: ['B1', 'B2']),
    ]);
    expect(drugA(plate).normalizedPercent, closeTo(30, 1e-9));
    final changed = plate.copyWith(wells: [
      for (final w in plate.wells)
        w.label == 'B1' ? w.copyWith(excluded: true) : w
    ]);
    expect(drugA(changed).normalizedPercent, isNull);
    expect(drugA(changed).reference!.controlWellLabels, ['B1', 'B2']);
  });

  for (final entry in <String, Well Function(Well)>{
    'excluded': (w) => w.copyWith(excluded: true),
    'unmeasured': (w) => w.copyWith(resultValue: null),
    'unit changed': (w) => w.copyWith(resultUnit: 'RFU'),
    'role changed': (w) => w.copyWith(role: WellRole.sample),
  }.entries) {
    test('invalid control (${entry.key}) blocks normalization without fallback',
        () {
      final original = referencePlate(manual: true);
      final plate = original.copyWith(wells: [
        for (final w in original.wells) w.label == 'B1' ? entry.value(w) : w
      ]);
      final a = drugA(plate);
      expect(a.normalizedPercent, isNull);
      expect(a.blankCorrectedMean, .5);
      expect(a.reference!.controlWellLabels, ['B1']);
      expect(a.reference!.warnings.join(), contains('B1'));
    });
  }

  test('invalid blank blocks correction and normalization including TSV', () {
    final original = referencePlate(manual: true);
    final plate = original.copyWith(wells: [
      for (final w in original.wells)
        w.label == 'A1' ? w.copyWith(excluded: true) : w
    ]);
    final a = drugA(plate);
    expect(a.rawMean, .6);
    expect(a.blankCorrectedMean, isNull);
    expect(a.normalizedPercent, isNull);
    final tsv = const PlateAnalysisExportService()
        .buildTsv(plate, service.analyze(plate));
    expect(tsv, contains('Blank 기준 확인 필요: A1'));
    expect(tsv,
        contains('Drug A\ttreatment\t10\tµM\tOD450\t1\tC1\t0\t\t0.6\t\t\t\t'));
  });

  test('zero denominator and explicit absence never reuse automatic controls',
      () {
    final original = referencePlate(manual: true);
    final zero = original.copyWith(wells: [
      for (final w in original.wells)
        w.label == 'B1' ? w.copyWith(resultValue: .1) : w
    ]);
    expect(drugA(zero).normalizedPercent, isNull);
    expect(drugA(zero).reference!.warnings.join(), contains('평균이 0'));
    final none = original.copyWith(analysisReferences: [
      const PlateAnalysisReferenceSelection(
          groupId: 'a',
          resultUnit: 'OD450',
          blankWellLabels: [],
          controlWellLabels: [])
    ]);
    expect(drugA(none).blankCorrectedMean, .6);
    expect(drugA(none).normalizedPercent, isNull);
    expect(drugA(none).reference!.manual, true);
  });

  test('a selection applies only to its group and exact trimmed result unit',
      () {
    final original = referencePlate(manual: true);
    final plate = original.copyWith(wells: [
      for (final w in original.wells)
        w.label == 'C1' ? w.copyWith(resultUnit: ' RFU ') : w
    ]);
    final a = drugA(plate);
    expect(a.reference!.manual, false);
    expect(a.reference!.controlWellLabels, ['B4']);
    expect(a.normalizedPercent, closeTo(15, 1e-9));
  });

  test('missing selected coordinates remain visible and disable calculation',
      () {
    final plate = referencePlate().copyWith(analysisReferences: [
      const PlateAnalysisReferenceSelection(
          groupId: 'a',
          resultUnit: 'OD450',
          blankWellLabels: ['A1'],
          controlWellLabels: ['Z99'])
    ]);
    final a = drugA(Plate.fromJson(plate.toJson()));
    expect(a.normalizedPercent, isNull);
    expect(a.reference!.warnings.join(), contains('Z99'));
  });

  test('references survive disk, history restore and full backup round trips',
      () async {
    final dir = await Directory.systemTemp.createTemp('analysis-references-');
    addTearDown(() => dir.delete(recursive: true));
    final repository = FilePlateRepository(rootDirectory: dir.path);
    final original = referencePlate(manual: true);
    await repository.savePlate(original);
    final loaded = (await repository.loadPlate('e'))!;
    expect(loaded.analysisReferences.map((s) => s.toJson()),
        original.analysisReferences.map((s) => s.toJson()));
    final snapshot =
        PlateSnapshot.fromJson(PlateSnapshot.fromPlate(loaded).toJson());
    final restored = snapshot.restore(id: 'p', experimentId: 'e');
    expect(drugA(restored).normalizedPercent, closeTo(50, 1e-9));
    const backup = EasyCheckBackupService();
    final encoded = backup.encode(experiments: [
      Experiment(
          id: 'e',
          title: 'Test',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026))
    ], plates: [
      restored
    ]);
    expect(backup.decode(encoded).schemaVersion, 5);
    expect(drugA(backup.decode(encoded).plates.single).normalizedPercent,
        closeTo(50, 1e-9));
    // Version 1 files remain readable and acquire references only on save.
    final legacy = original.toJson()..remove('analysisReferences');
    final file = File('${dir.path}/plates/e.json');
    await file.writeAsString(jsonEncode({'schemaVersion': 1, 'data': legacy}));
    expect((await repository.loadPlate('e'))!.analysisReferences, isEmpty);
    final legacyBackup = jsonDecode(encoded) as Map<String, dynamic>;
    legacyBackup['schemaVersion'] = 2;
    legacyBackup['plates'] = [legacy];
    expect(
        backup
            .decode(jsonEncode(legacyBackup))
            .plates
            .single
            .analysisReferences,
        isEmpty);
  });

  test('malformed or duplicate reference settings are rejected', () {
    final plate = referencePlate().toJson();
    for (final bad in [
      'bad',
      [1],
      [referenceA.toJson(), referenceA.toJson()],
      [
        {
          ...referenceA.toJson(),
          'blankWellLabels': ['A1', 'A1']
        }
      ],
      [
        {...referenceA.toJson(), 'controlWellLabels': null}
      ],
      [
        {...referenceA.toJson(), 'resultUnit': ' '}
      ],
      [
        {
          ...referenceA.toJson(),
          'blankWellLabels': ['a1']
        }
      ],
    ]) {
      expect(() => Plate.fromJson({...plate, 'analysisReferences': bad}),
          throwsFormatException);
    }
  });

  test('exports tiny reference measurements without rounding to zero', () {
    final original = referencePlate(manual: true);
    final plate = original.copyWith(wells: [
      for (final w in original.wells)
        w.label == 'A1' ? w.copyWith(resultValue: 1e-9) : w
    ]);
    expect(
        const PlateAnalysisExportService()
            .buildTsv(plate, service.analyze(plate)),
        contains('1e-9'));
  });
}
