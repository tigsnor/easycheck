import 'dart:convert';
import 'dart:io';

import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/experiment_completion_review.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/cell_condition.dart';
import 'package:easycheck/features/plates/domain/measured_condition_review.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_export_service.dart';
import 'package:easycheck/features/plates/domain/plate_export_service.dart';
import 'package:easycheck/features/plates/domain/plate_validation_service.dart';
import 'package:easycheck/features/plates/domain/well.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/templates/data/file_plate_template_repository.dart';
import 'package:easycheck/features/plates/templates/domain/plate_template.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/cell_condition_fixture.dart';

void main() {
  const analysis = PlateAnalysisService();
  Experiment experiment() => Experiment(
      id: 'e',
      title: 'Cells',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      cellCountLabel: 'old free text');
  PlateAnalysisSeries treated(Plate p, CellCondition? condition) =>
      analysis.analyze(p).series.singleWhere(
          (s) => s.role == WellRole.treatment && s.cellCondition == condition);

  test(
      'cell conditions validate numbers and units without guessing legacy values',
      () {
    final old = cellPlate().wells.first.toJson()..remove('cellCondition');
    expect(Well.fromJson(old).cellCondition, isNull);
    for (final c in [
      hekLow,
      const CellCondition(name: 'HeLa'),
      const CellCondition(name: 'HeLa', density: 0, unit: 'cells/mL'),
      const CellCondition(name: 'H', density: 1.234567891e5, unit: 'cells/mL')
    ]) {
      expect(CellCondition.fromJson(c.toJson()), c);
    }
    for (final value in [
      42,
      {'name': ''},
      {'name': ' H '},
      {'name': 'H', 'density': -1, 'unit': 'cells/well'},
      {'name': 'H', 'density': double.nan, 'unit': 'cells/well'},
      {'name': 'H', 'density': double.infinity, 'unit': 'cells/well'},
      {'name': 'H', 'density': '100', 'unit': 'cells/well'},
      {'name': 'H', 'density': 100, 'unit': 'µM'},
      {'name': 'H', 'unit': 'cells/well'}
    ]) {
      expect(() => CellCondition.fromJson(value), throwsFormatException);
    }
    final well = cellPlate().wells.first;
    expect(well.copyWith(note: 'memo').cellCondition, hekLow);
    expect(well.copyWith(cellCondition: null).concentrationValue, 10);
    expect(well.copyWith(cellCondition: null).cellCondition, isNull);
  });

  test(
      'types, densities, absent conditions and units form distinct replicates and references',
      () {
    final plate = cellPlate();
    final low = treated(plate, hekLow);
    expect(low.includedWellLabels, ['A1', 'A2']);
    expect(low.replicateCount, 2);
    expect(low.rawMean, closeTo(0.7, 1e-10));
    expect(low.reference!.blankWellLabels, ['A10']);
    expect(low.reference!.controlWellLabels, ['A6']);
    expect(low.normalizedPercent, closeTo(200 / 3, 1e-9));
    expect(treated(plate, hekHigh).reference!.controlWellLabels, ['A7']);
    expect(treated(plate, hela).normalizedPercent, closeTo(50, 1e-9));
    expect(treated(plate, null).normalizedPercent, isNull);
    const perMl =
        CellCondition(name: 'HEK293', density: 5000, unit: 'cells/mL');
    final changed = plate.copyWith(wells: [
      for (final w in plate.wells)
        w.label == 'A2' ? w.copyWith(cellCondition: perMl) : w
    ]);
    expect(treated(changed, hekLow).replicateCount, 1);
    expect(treated(changed, perMl).normalizedPercent, isNull);
    final issues = const PlateValidationService().validate(changed).issues;
    expect(
        issues
            .singleWhere((i) => i.code == 'replicate_insufficient')
            .wellLabels,
        containsAll(['A1', 'A2', 'A3', 'A4', 'A5']));
  });

  test(
      'manual references are scoped by cells; common blank is explicit and changed controls invalidate',
      () {
    const lowReference = PlateAnalysisReferenceSelection(
        groupId: 'drug',
        resultUnit: 'OD450',
        cellCondition: hekLow,
        blankWellLabels: ['A9'],
        controlWellLabels: ['A6']);
    const highReference = PlateAnalysisReferenceSelection(
        groupId: 'drug',
        resultUnit: 'OD450',
        cellCondition: hekHigh,
        blankWellLabels: [],
        controlWellLabels: []);
    var p =
        cellPlate().copyWith(analysisReferences: [lowReference, highReference]);
    p = Plate.fromJson(p.toJson());
    expect(treated(p, hekLow).normalizedPercent, closeTo(62.5, 1e-9));
    expect(treated(p, hekHigh).normalizedPercent, isNull);
    expect(treated(p, hela).reference!.manual, false);
    final changed = p.copyWith(wells: [
      for (final w in p.wells)
        w.label == 'A6' ? w.copyWith(cellCondition: hela) : w
    ]);
    expect(treated(changed, hekLow).normalizedPercent, isNull);
    expect(treated(changed, hekLow).reference!.warnings.join(),
        contains('세포 조건 변경'));
    expect(
        () => Plate.fromJson(p.copyWith(
            analysisReferences: [lowReference, lowReference]).toJson()),
        throwsFormatException);
    // A legacy selection is not inherited by newly assigned cellular conditions.
    final legacy = p.copyWith(analysisReferences: [
      const PlateAnalysisReferenceSelection(
          groupId: 'drug',
          resultUnit: 'OD450',
          blankWellLabels: ['A9'],
          controlWellLabels: ['A6'])
    ]);
    expect(treated(legacy, hekLow).reference!.manual, false);
    expect(treated(legacy, null).normalizedPercent, isNull);
  });

  test(
      'changing cells on measured, zero or excluded wells requires correction and preserves snapshots',
      () {
    final before = cellPlate().copyWith(wells: [
      for (final w in cellPlate().wells)
        w.label == 'A1' ? w.copyWith(resultValue: 0, excluded: true) : w
    ]);
    final after = before.copyWith(wells: [
      for (final w in before.wells)
        w.label == 'A1' ? w.copyWith(cellCondition: hela) : w
    ]);
    final review = MeasuredConditionReview.compare(before, after);
    expect(review.changes.single.fields.single.label, '세포 조건');
    expect(review.record('파종 기록 정정'), contains('HEK293'));
    expect(review.record('파종 기록 정정'), contains('HeLa'));
    final restored =
        PlateSnapshot.fromJson(PlateSnapshot.fromPlate(before).toJson())
            .restore(id: 'p', experimentId: 'e');
    expect(restored.wells.first.cellCondition, hekLow);
    expect(restored.wells.first.resultValue, 0);
    expect(restored.wells.first.excluded, true);
  });

  test('cell-only wells count as planned measurements at completion', () {
    final empty = Plate(id: 'p', experimentId: 'e', name: 'Cells');
    final p = empty.copyWith(wells: [
      for (final w in empty.wells)
        w.label == 'A1' ? w.copyWith(cellCondition: hekLow) : w
    ]);
    final review =
        const ExperimentCompletionReviewService().review(experiment(), p);
    expect(review.issues.any((i) => i.wellLabels.contains('A1')), true);
    expect(review.issues.any((i) => i.title.contains('빈 배치')), false);
  });

  test(
      'plate and analysis TSV preserve explicit cell columns and numerical precision',
      () {
    final p = cellPlate();
    final layout = const PlateExportService().buildTsv(p);
    final tsv =
        const PlateAnalysisExportService().buildTsv(p, analysis.analyze(p));
    for (final output in [layout, tsv]) {
      expect(output, contains('cell_type\tcell_density\tcell_density_unit'));
      expect(output, contains('HEK293\t5000\tcells/well'));
      expect(output, contains('HEK293\t10000\tcells/well'));
      expect(output, contains('HeLa\t5000\tcells/well'));
    }
  });

  test(
      'disk, template, history and backup restore all cell conditions while legacy remains readable',
      () async {
    final dir = await Directory.systemTemp.createTemp('cell-roundtrip-');
    addTearDown(() => dir.delete(recursive: true));
    final repo = FilePlateRepository(rootDirectory: dir.path);
    final templates = FilePlateTemplateRepository(rootDirectory: dir.path);
    final p = cellPlate().copyWith(revisions: [
      PlateRevision(
          id: 'r',
          changedAt: DateTime.utc(2026),
          summary: 'Cells',
          snapshot: PlateSnapshot.fromPlate(cellPlate()))
    ]);
    await repo.savePlate(p);
    final loaded = (await repo.loadPlate('e'))!;
    expect(loaded.toJson(), p.toJson());
    final template = PlateTemplate.fromPlate(id: 't', name: 'Cells', plate: p);
    await templates.saveTemplate(template);
    final design = (await templates.loadTemplates())
        .single
        .instantiate(plateId: 'new', experimentId: 'new');
    expect(design.wells.map((w) => w.cellCondition),
        p.wells.map((w) => w.cellCondition));
    expect(design.wells.map((w) => w.resultValue), everyElement(isNull));
    const backup = EasyCheckBackupService();
    final decoded = backup.decode(backup.encode(
        experiments: [experiment()], plates: [loaded], templates: [template]));
    expect(decoded.schemaVersion, 8);
    expect(decoded.plates.single.toJson(), p.toJson());
    expect(decoded.templates.single.toJson(), template.toJson());
    expect(decoded.experiments.single.cellCountLabel, 'old free text');
    final legacy = p.toJson()..remove('revisions');
    for (final w in legacy['wells'] as List) {
      (w as Map).remove('cellCondition');
    }
    await File('${dir.path}/plates/e.json')
        .writeAsString(jsonEncode({'schemaVersion': 2, 'data': legacy}));
    expect((await repo.loadPlate('e'))!.wells.map((w) => w.cellCondition),
        everyElement(isNull));
    final legacyTemplate = template.toJson();
    for (final w in legacyTemplate['wells'] as List) {
      (w as Map).remove('cellCondition');
    }
    await File('${dir.path}/plate_templates.json').writeAsString(jsonEncode({
      'schemaVersion': 1,
      'data': [legacyTemplate]
    }));
    expect(
        (await templates.loadTemplates())
            .single
            .wells
            .map((w) => w.cellCondition),
        everyElement(isNull));
  });
}
