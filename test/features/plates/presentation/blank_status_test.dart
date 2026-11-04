import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_export_service.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  for (final hasBlank in [true, false]) {
    testWidgets(
        'zero blank is applied, missing blank explicitly uses raw values: $hasBlank',
        (tester) async {
      final base = Plate(id: 'p', experimentId: 'e', name: 'P');
      final plate = base.copyWith(wells: [
        for (final w in base.wells)
          switch (w.label) {
            'A1' when hasBlank => w.copyWith(
                role: WellRole.blank, resultValue: 0, resultUnit: 'OD450'),
            'A2' => w.copyWith(
                role: WellRole.vehicleControl,
                resultValue: 1,
                resultUnit: 'OD450'),
            'B1' => w.copyWith(
                role: WellRole.treatment,
                concentrationValue: 10,
                resultValue: .5,
                resultUnit: 'OD450'),
            _ => w,
          }
      ]);
      final report = const PlateAnalysisService().analyze(plate);
      final tsv = const PlateAnalysisExportService().buildTsv(plate, report);
      expect(tsv, contains('blank_correction_status'));
      expect(tsv, contains(hasBlank ? '\tapplied\n' : '\tnot_applied\n'));
      final repo = FakePlateRepository()..plate = plate;
      await tester.pumpWidget(MaterialApp(
          home: PlateEditorScreen(experimentId: 'e', repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('show-analysis-action')));
      await tester.pumpAndSettle();
      expect(find.textContaining(hasBlank ? 'Blank 보정 ·' : '보정 안 됨 · 원값 ·'),
          findsWidgets);
      if (!hasBlank) {
        expect(find.textContaining('Control 대비 · 원값 기준 ·'), findsWidgets);
      }
      expect(repo.saveCount, 0);
    });
  }

  for (final excluded in [false, true]) {
    testWidgets(
        'manual ${excluded ? 'excluded' : 'unmeasured'} Blank requires reference review instead of raw fallback',
        (tester) async {
      final base = Plate(id: 'p', experimentId: 'e', name: 'P');
      final plate = base.copyWith(
        analysisReferences: const [
          PlateAnalysisReferenceSelection(
              groupId: null,
              resultUnit: 'OD450',
              blankWellLabels: ['A1'],
              controlWellLabels: ['A2'])
        ],
        wells: [
          for (final w in base.wells)
            switch (w.label) {
              'A1' => w.copyWith(
                  role: WellRole.blank,
                  resultValue: excluded ? 0 : null,
                  resultUnit: 'OD450',
                  excluded: excluded),
              'A2' => w.copyWith(
                  role: WellRole.vehicleControl,
                  resultValue: 1,
                  resultUnit: 'OD450'),
              'B1' => w.copyWith(
                  role: WellRole.treatment,
                  concentrationValue: 10,
                  resultValue: .5,
                  resultUnit: 'OD450'),
              _ => w,
            }
        ],
      );
      final report = const PlateAnalysisService().analyze(plate);
      final treatment =
          report.series.singleWhere((s) => s.role == WellRole.treatment);
      expect(treatment.rawMean, .5);
      expect(treatment.reference!.blankValid, false);
      expect(treatment.blankCorrectedMean, isNull);
      expect(treatment.normalizedPercent, isNull);
      final tsv = const PlateAnalysisExportService().buildTsv(plate, report);
      expect(tsv, contains('\tinvalid_reference\n'));
      expect(tsv, isNot(contains('\tnot_applied\n')));

      final repo = FakePlateRepository()..plate = plate;
      await tester.pumpWidget(MaterialApp(
          home: PlateEditorScreen(experimentId: 'e', repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('show-analysis-action')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Blank 기준 확인 필요 ·'), findsWidgets);
      expect(find.textContaining('보정 안 됨 · 원값 ·'), findsNothing);
      expect(find.textContaining('Control 대비 · 원값 기준 ·'), findsNothing);
      expect(repo.saveCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
