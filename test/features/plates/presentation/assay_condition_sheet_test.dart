import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/plates/domain/assay_condition.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_analysis_reference.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/analysis_reference_sheet.dart';
import 'package:easycheck/features/plates/presentation/widgets/assay_condition_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/assay_condition_fixture.dart';
import '../../../support/cell_condition_fixture.dart';
import 'plate_editor_screen_test.dart'
    show FakePlateRepository, FakePlateTemplateRepository;

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<FakePlateRepository> open(WidgetTester tester,
      {Plate? plate, bool readOnly = false, bool analysis = false}) async {
    final repo = FakePlateRepository()
      ..plate = plate ?? Plate(id: 'p', experimentId: 'e', name: 'Assay');
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: PlateEditorScreen(
            experimentId: 'e',
            repository: repo,
            readOnly: readOnly,
            openAnalysisOnLoad: analysis,
            templateRepository: FakePlateTemplateRepository())));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> edit(WidgetTester tester, String position) async {
    await tap(tester, key(position));
    await tap(tester, key('assign-assay-condition-action'));
  }

  Future<void> enter(WidgetTester tester, AssayCondition condition) async {
    await tester.enterText(key('assay-medium-input'), condition.medium);
    await tester.enterText(key('assay-vehicle-input'), condition.vehicle ?? '');
    await tester.enterText(
        key('assay-percent-input'), condition.vehiclePercent.toString());
    await tap(tester, key('apply-assay-condition'));
  }

  testWidgets(
      'assigns row environments, reuses conditions, and preserves cells and treatment',
      (tester) async {
    final original = assayPlate().copyWith(wells: [
      for (final w in assayPlate().wells)
        w.copyWith(resultValue: null, assayCondition: null)
    ]);
    final repo = await open(tester, plate: original);
    await edit(tester, 'row-header-A');
    await enter(tester, dmsoLow);
    await edit(tester, 'row-header-B');
    await enter(tester, dmsoHigh);
    await edit(tester, 'well-C1');
    await tap(tester, find.widgetWithText(ActionChip, dmsoLow.label));
    await tap(tester, key('apply-assay-condition'));
    expect(repo.plate!.wells.take(12).map((w) => w.assayCondition),
        everyElement(dmsoLow));
    expect(repo.plate!.wells.skip(12).take(12).map((w) => w.assayCondition),
        everyElement(dmsoHigh));
    expect(repo.plate!.wells[24].assayCondition, dmsoLow);
    expect(repo.plate!.wells.first.cellCondition, hekLow);
    expect(repo.plate!.wells.first.concentrationValue, 10);
    final count = repo.saveCount;
    await edit(tester, 'well-A1');
    expect(tester.widget<TextField>(key('assay-medium-input')).controller!.text,
        dmsoLow.medium);
    await tap(tester, key('apply-assay-condition'));
    expect(repo.saveCount, count);
  });

  testWidgets(
      'dirty close and explicit clear preserve other conditions and distinguish unknown from zero',
      (tester) async {
    final p = assayPlate().copyWith(wells: [
      for (final w in assayPlate().wells) w.copyWith(resultValue: null)
    ]);
    final repo = await open(tester, plate: p);
    await edit(tester, 'well-A1');
    await tester.enterText(key('assay-medium-input'), 'PBS');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('배지·용매 조건 입력을 버릴까요?'), findsOneWidget);
    await tap(tester, find.text('계속 편집'));
    await tap(tester, key('close-assay-condition'));
    await tap(tester, find.text('입력 버리고 닫기'));
    expect(repo.saveCount, 0);
    await edit(tester, 'well-A1');
    await tap(tester, key('clear-assay-condition'));
    await tap(tester, find.text('취소'));
    expect(repo.plate!.wells.first.assayCondition, dmsoLow);
    await tap(tester, key('clear-assay-condition'));
    await tap(tester, find.widgetWithText(FilledButton, '배지·용매 조건 해제'));
    expect(repo.plate!.wells.first.assayCondition, isNull);
    expect(repo.plate!.wells.first.cellCondition, hekLow);
    await edit(tester, 'well-A1');
    expect(
        tester.widget<TextField>(key('assay-percent-input')).controller!.text,
        isEmpty);
    await enter(tester, noVehicle);
    expect(repo.plate!.wells.first.assayCondition, noVehicle);
  });

  testWidgets(
      'measured zero excluded well requires reason and failed save retries one historical snapshot',
      (tester) async {
    final original = assayPlate().copyWith(wells: [
      for (final w in assayPlate().wells)
        w.label == 'A1' ? w.copyWith(resultValue: 0, excluded: true) : w
    ]);
    final repo = await open(tester, plate: original);
    await edit(tester, 'well-A1');
    await enter(tester, rpmi);
    expect(repo.saveCount, 0);
    expect(find.textContaining('변경 전: ${dmsoLow.label}'), findsOneWidget);
    await tap(tester, key('confirm-condition-correction'));
    expect(find.text('측정 후 조건을 바꾸는 사유를 입력해주세요.'), findsOneWidget);
    await tester.enterText(key('condition-correction-reason'), '실제 배지 확인');
    repo.failNextSave = true;
    await tap(tester, key('confirm-condition-correction'));
    expect(repo.plate!.toJson(), original.toJson());
    await tap(tester, key('retry-save-button'));
    expect(repo.plate!.wells.first.assayCondition, rpmi);
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.wells.first.excluded, true);
    expect(repo.plate!.revisions.single.snapshot!.wells.first.assayCondition,
        dmsoLow);
    expect(repo.plate!.revisions.single.summary, contains('실제 배지 확인'));
  });

  testWidgets(
      'manual reference candidates filter environment and allow only the matching shared blank',
      (tester) async {
    PlateAnalysisReferenceSelection? saved;
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: Scaffold(
            body: AnalysisReferenceSheet(
                plate: assayPlate(),
                groupId: 'drug',
                groupLabel: 'Drug',
                resultUnit: 'OD450',
                cellCondition: hekLow,
                assayCondition: dmsoLow,
                onSave: (selection) async {
                  saved = selection;
                  return false;
                }))));
    await tester.pumpAndSettle();
    await tap(tester, key('automatic-references'));
    expect(key('reference-control-A3'), findsOneWidget);
    for (final row in ['B', 'C', 'D', 'E', 'F']) {
      expect(key('reference-control-${row}3'), findsNothing);
    }
    expect(key('reference-blank-A5'), findsOneWidget);
    expect(key('reference-blank-B4'), findsNothing);
    await tap(tester, key('reference-control-A3'));
    await tap(tester, key('reference-blank-A5'));
    await tap(tester, key('save-analysis-references'));
    expect(saved!.assayCondition, dmsoLow);
    expect(saved!.blankWellLabels, ['A5']);
    expect(saved!.controlWellLabels, ['A3']);
  });

  testWidgets(
      'analysis saves one environment reference without replacing another and read-only prevents condition editing',
      (tester) async {
    const high = PlateAnalysisReferenceSelection(
        groupId: 'drug',
        resultUnit: 'OD450',
        cellCondition: hekLow,
        assayCondition: dmsoHigh,
        blankWellLabels: [],
        controlWellLabels: []);
    final repo = await open(tester,
        plate: assayPlate().copyWith(analysisReferences: [high]),
        analysis: true);
    await tap(tester,
        key('edit-reference-drug-OD450-${hekLow.key}-assay-${dmsoLow.key}'));
    await tap(tester, key('automatic-references'));
    await tap(tester, key('reference-control-A3'));
    await tap(tester, key('reference-blank-A5'));
    await tap(tester, key('save-analysis-references'));
    expect(repo.plate!.analysisReferences, hasLength(2));
    expect(
        repo.plate!.analysisReferences
            .singleWhere((s) => s.assayCondition == dmsoHigh)
            .toJson(),
        high.toJson());
    await tester.pumpWidget(const SizedBox());
    final locked = await open(tester, plate: repo.plate, readOnly: true);
    await tap(tester, key('well-A1'));
    expect(key('assign-assay-condition-action'), findsNothing);
    expect(locked.saveCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '320px large text and keyboard expose missing medium and invalid percentage without inventing defaults',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    AssayConditionDraft? result;
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    child: const Text('Open'),
                    onPressed: () async {
                      result = await showModalBottomSheet<AssayConditionDraft>(
                          context: context,
                          isScrollControlled: true,
                          isDismissible: false,
                          enableDrag: false,
                          builder: (_) => AssayConditionSheet(wells: [
                                Plate(id: 'p', experimentId: 'e', name: 'Empty')
                                    .wells
                                    .first
                              ], available: const []));
                    })))));
    await tap(tester, find.text('Open'));
    await tap(tester, key('apply-assay-condition'));
    expect(
        tester.getBottomRight(find.text('배지/버퍼를 입력해주세요.')).dy, lessThan(460));
    await tester.enterText(key('assay-medium-input'), 'PBS');
    for (final value in ['', '-1', '101', 'NaN', 'Infinity']) {
      await tester.enterText(key('assay-percent-input'), value);
      await tap(tester, key('apply-assay-condition'));
      final error = find.text('최종 용매 비율을 0~100 사이 숫자로 입력해주세요.');
      expect(tester.getBottomRight(error).dy, lessThan(460));
      expect(result, isNull);
    }
    await tester.enterText(key('assay-percent-input'), '0.1');
    await tap(tester, key('apply-assay-condition'));
    expect(find.textContaining('용매 이름이 없으면'), findsOneWidget);
    await tester.enterText(key('assay-vehicle-input'), 'DMSO');
    await tester.enterText(key('assay-percent-input'), '1e-3');
    await tap(tester, key('apply-assay-condition'));
    expect(
        result!.condition,
        const AssayCondition(
            medium: 'PBS', vehicle: 'DMSO', vehiclePercent: 0.001));
    expect(tester.takeException(), isNull);
  });
}
