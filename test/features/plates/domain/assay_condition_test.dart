import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/domain/measured_condition_review.dart';
import 'package:easycheck/features/plates/domain/plate_export_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_export_service.dart';
import 'package:easycheck/features/plates/domain/plate_validation_service.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:easycheck/features/plates/templates/data/file_plate_template_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/experiment_completion_review.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import '../../../support/assay_condition_fixture.dart';
import '../../../support/cell_condition_fixture.dart';

void main() {
  const analysis = PlateAnalysisService();
  Experiment experiment() => Experiment(
      id: 'e',
      title: 'Assay',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026));
  PlateAnalysisSeries series(Plate plate, AssayCondition? condition) =>
      analysis.analyze(plate).series.singleWhere(
          (s) => s.role == WellRole.treatment && s.assayCondition == condition);
  PlateAnalysisReferenceSelection selection(
          {AssayCondition? condition = dmsoLow,
          List<String> blanks = const ['A4'],
          List<String> controls = const ['A3']}) =>
      PlateAnalysisReferenceSelection(
          groupId: 'drug',
          resultUnit: 'OD450',
          cellCondition: hekLow,
          assayCondition: condition,
          blankWellLabels: blanks,
          controlWellLabels: controls);

  test(
      'strict environment values distinguish unknown, no vehicle, names and exact percent',
      () {
    expect(
        const AssayCondition(medium: 'DMEM + 10% FBS', vehiclePercent: -0.0)
            .key,
        noVehicle.key);
    expect(AssayCondition.fromJson(dmsoLow.toJson()), dmsoLow);
    expect({dmsoLow, dmsoHigh, rpmi, ethanol, noVehicle}.length, 5);
    for (final invalid in [
      null,
      {},
      {...dmsoLow.toJson(), 'medium': ' '},
      {...dmsoLow.toJson(), 'vehicle': ''},
      {...dmsoLow.toJson(), 'vehiclePercent': -0.1},
      {...dmsoLow.toJson(), 'vehiclePercent': 101},
      {...dmsoLow.toJson(), 'vehiclePercent': double.nan},
      {...dmsoLow.toJson(), 'vehiclePercent': double.infinity},
      {...dmsoLow.toJson(), 'vehicle': null}
    ]) {
      expect(() => AssayCondition.fromJson(invalid), throwsFormatException);
    }
    final well = assayPlate().wells.first;
    expect(Well.fromJson(well.toJson()).assayCondition, dmsoLow);
    expect(well.copyWith(note: 'keep').assayCondition, dmsoLow);
    expect(well.copyWith(assayCondition: null).assayCondition, isNull);
    final old = well.toJson()..remove('assayCondition');
    expect(Well.fromJson(old).assayCondition, isNull);
  });

  test(
      'automatic statistics and references separate medium, vehicle, percent and legacy wells',
      () {
    final p = assayPlate();
    expect(
        analysis.analyze(p).series.where((s) => s.role == WellRole.treatment),
        hasLength(6));
    final a = series(p, dmsoLow);
    expect(a.replicateCount, 2);
    expect(a.includedWellLabels, ['A1', 'A2']);
    expect(a.reference!.blankWellLabels, ['A4']);
    expect(a.reference!.controlWellLabels, ['A3']);
    expect(a.normalizedPercent, closeTo(66.6666667, 1e-6));
    expect(series(p, dmsoHigh).reference!.controlWellLabels, ['B3']);
    expect(series(p, rpmi).normalizedPercent, closeTo(50, 1e-10));
    expect(series(p, ethanol).reference!.controlWellLabels, ['D3']);
    expect(series(p, noVehicle).reference!.controlWellLabels, ['F3']);
    expect(series(p, null).reference!.controlWellLabels, ['E3']);
    expect(analysis.analyze(p).blankMeanByUnit['OD450'], 0.1);
    expect(analysis.analyze(p).controlByUnit['OD450']!.rawMean, 0.9);
  });

  test(
      'manual references require exact environment and shared cell-free blank stays explicit',
      () {
    final p = assayPlate();
    final shared = series(
        p.copyWith(analysisReferences: [
          selection(blanks: ['A5'])
        ]),
        dmsoLow);
    expect(shared.reference!.blankValid, true);
    expect(shared.normalizedPercent, closeTo(62.5, 1e-10));
    final wrongControl = series(
        p.copyWith(analysisReferences: [
          selection(controls: ['A3', 'B3'])
        ]),
        dmsoLow);
    expect(wrongControl.normalizedPercent, isNull);
    expect(wrongControl.reference!.controlRawMean, isNull);
    expect(wrongControl.reference!.warnings.join(), contains('B3'));
    final wrongBlank = series(
        p.copyWith(analysisReferences: [
          selection(blanks: ['B4'])
        ]),
        dmsoLow);
    expect(wrongBlank.blankCorrectedMean, isNull);
    expect(wrongBlank.rawMean, closeTo(0.7, 1e-10));
    final legacy = series(
        p.copyWith(analysisReferences: [
          selection(condition: null, blanks: [], controls: [])
        ]),
        dmsoLow);
    expect(legacy.reference!.manual, false);
    final changed = p.copyWith(analysisReferences: [
      selection()
    ], wells: [
      for (final w in p.wells)
        w.label == 'A3' ? w.copyWith(assayCondition: dmsoHigh) : w
    ]);
    expect(series(changed, dmsoLow).normalizedPercent, isNull);
    expect(series(changed, dmsoLow).reference!.manual, true);
    expect(
        PlateAnalysisReferenceSelection.parseList(
            [selection().toJson(), selection(condition: dmsoHigh).toJson()]),
        hasLength(2));
    expect(
        () => PlateAnalysisReferenceSelection.parseList(
            [selection().toJson(), selection().toJson()]),
        throwsFormatException);
  });

  test(
      'environment changes on zero/excluded measurements require review and snapshot preserves old values',
      () {
    final p = assayPlate();
    final before = p.copyWith(wells: [
      for (final w in p.wells)
        w.label == 'A1' ? w.copyWith(resultValue: 0, excluded: true) : w
    ]);
    final after = before.copyWith(wells: [
      for (final w in before.wells)
        w.label == 'A1' ? w.copyWith(assayCondition: rpmi) : w
    ]);
    final review = MeasuredConditionReview.compare(before, after);
    expect(
        review.changes.single.fields.any((f) => f.label == '배지·용매 조건'), true);
    final restored =
        PlateSnapshot.fromJson(PlateSnapshot.fromPlate(before).toJson())
            .restore(id: 'p', experimentId: 'e');
    expect(restored.wells.first.assayCondition, dmsoLow);
    expect(restored.wells.first.resultValue, 0);
    expect(restored.wells.first.excluded, true);
  });

  test(
      'environment-only well counts as planned and mismatched references appear in completion review',
      () {
    final p = Plate(id: 'p', experimentId: 'e', name: 'empty');
    final planned = p.copyWith(wells: [
      p.wells.first.copyWith(assayCondition: noVehicle),
      ...p.wells.skip(1)
    ]);
    expect(
        const PlateValidationService()
            .validate(planned)
            .issues
            .any((i) => i.code == 'layout_empty'),
        false);
    expect(
        const ExperimentCompletionReviewService()
            .review(experiment(), planned)
            .issues
            .any((i) =>
                i.wellLabels.contains('A1') && i.title.contains('결과 미입력')),
        true);
    final issues = const ExperimentCompletionReviewService()
        .review(
            experiment(),
            assayPlate().copyWith(analysisReferences: [
              selection(controls: ['B3'])
            ]))
        .issues;
    expect(
        issues.any(
            (i) => i.message.contains('B3') && i.title.contains(dmsoLow.label)),
        true);
  });

  test(
      'TSV appends explicit environment including zero and preserves old columns',
      () {
    final p = assayPlate();
    for (final output in [
      const PlateExportService().buildTsv(p),
      const PlateAnalysisExportService().buildTsv(p, analysis.analyze(p))
    ]) {
      expect(output, contains('medium\tvehicle\tvehicle_percent_vv'));
      expect(output, contains('DMEM + 10% FBS\tDMSO\t0.1'));
      expect(output, contains('DMEM + 10% FBS\t없음\t0'));
      expect(output, contains('cell_type\tcell_density\tcell_density_unit'));
    }
  });

  test(
      'file, history, templates and fresh backup restoration preserve environment and reference scope',
      () async {
    final root = await Directory.systemTemp.createTemp('assay-');
    final restored = await Directory.systemTemp.createTemp('assay-restored-');
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() => restored.delete(recursive: true));
    final p = assayPlate().copyWith(analysisReferences: [
      selection()
    ], revisions: [
      PlateRevision(
          id: 'r',
          changedAt: DateTime.utc(2026),
          summary: 'before',
          snapshot: PlateSnapshot.fromPlate(assayPlate()))
    ]);
    final repo = FilePlateRepository(rootDirectory: root.path);
    await repo.savePlate(p);
    expect(
        jsonDecode(await File('${root.path}/plates/e.json').readAsString())[
            'schemaVersion'],
        5);
    expect(
        (await FilePlateRepository(rootDirectory: root.path).loadPlate('e'))!
            .toJson(),
        p.toJson());
    final template =
        PlateTemplate.fromPlate(id: 't', name: 'Conditions', plate: p);
    final templates = FilePlateTemplateRepository(rootDirectory: root.path);
    await templates.saveTemplate(template);
    expect(
        jsonDecode(await File('${root.path}/plate_templates.json')
            .readAsString())['schemaVersion'],
        3);
    final design = (await templates.loadTemplates())
        .single
        .instantiate(plateId: 'new', experimentId: 'new');
    expect(design.wells.first.assayCondition, dmsoLow);
    expect(design.wells.first.resultValue, isNull);
    const codec = EasyCheckBackupService();
    final encoded = codec.encode(
        experiments: [experiment()], plates: [p], templates: [template]);
    final backup = codec.decode(encoded);
    expect(backup.schemaVersion, 11);
    await FileBackupRecoveryService(rootDirectory: restored.path)
        .recover(backup);
    expect(
        (await FilePlateRepository(rootDirectory: restored.path)
                .loadPlate('e'))!
            .toJson(),
        p.toJson());
    final bad = jsonDecode(encoded);
    bad['plates'][0]['wells'][0]['assayCondition']['vehiclePercent'] = 101;
    expect(() => codec.decode(jsonEncode(bad)), throwsFormatException);
    final legacy = p.toJson()..remove('revisions');
    for (final well in legacy['wells'] as List) {
      (well as Map).remove('assayCondition');
    }
    for (final reference in legacy['analysisReferences'] as List) {
      (reference as Map).remove('assayCondition');
    }
    await File('${root.path}/plates/e.json')
        .writeAsString(jsonEncode({'schemaVersion': 3, 'data': legacy}));
    expect((await repo.loadPlate('e'))!.wells.map((w) => w.assayCondition),
        everyElement(isNull));
    final oldTemplate = template.toJson();
    for (final well in oldTemplate['wells'] as List) {
      (well as Map).remove('assayCondition');
    }
    await File('${root.path}/plate_templates.json').writeAsString(jsonEncode({
      'schemaVersion': 2,
      'data': [oldTemplate]
    }));
    expect(
        (await templates.loadTemplates())
            .single
            .wells
            .map((w) => w.assayCondition),
        everyElement(isNull));
    final oldBackup = jsonDecode(encoded);
    oldBackup['schemaVersion'] = 9;
    oldBackup['plates'] = [legacy];
    oldBackup['templates'] = [oldTemplate];
    expect(
        codec
            .decode(jsonEncode(oldBackup))
            .plates
            .single
            .wells
            .map((w) => w.assayCondition),
        everyElement(isNull));
  });
}
