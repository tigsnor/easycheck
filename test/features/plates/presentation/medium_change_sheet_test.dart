import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/medium_change_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/assay_condition_fixture.dart';
import 'plate_editor_screen_test.dart' show FakePlateRepository;

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, String value) async {
    await tester.pumpAndSettle();
    if (key(value).evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(key(value));
    await tester.pumpAndSettle();
    await tester.tap(key(value));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String field, String value) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('medium-change-$field'));
    await tester.enterText(key('medium-change-$field'), value);
  }

  Plate source({bool measured = false}) {
    final p = assayPlate();
    return p.copyWith(wells: [
      p.wells.first.copyWith(
          volumeValue: 100,
          volumeUnit: 'µL',
          resultValue: measured ? 0 : null,
          excluded: measured),
      ...p.wells.skip(1),
    ]);
  }

  Future<FakePlateRepository> open(WidgetTester tester,
      {Plate? plate, bool readOnly = false}) async {
    final repo = FakePlateRepository()..plate = plate ?? source();
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: PlateEditorScreen(
            experimentId: 'e', repository: repo, readOnly: readOnly)));
    await tester.pumpAndSettle();
    await tap(tester, 'well-A1');
    if (!readOnly) await tap(tester, 'medium-change-action');
    return repo;
  }

  Future<void> incoming(WidgetTester tester,
      {String volume = '20',
      String concentration = '0',
      String percent = '0'}) async {
    await enter(tester, 'incoming-volume', volume);
    await enter(tester, 'incoming-concentration', concentration);
    await enter(tester, 'incoming-percent', percent);
    await tap(tester, 'calculate-medium-change');
  }

  Future<void> apply(WidgetTester tester) async {
    await tap(tester, 'confirm-medium-change');
    await tap(tester, 'apply-medium-change');
  }

  testWidgets(
      'plain full replacement needs no reagent unit, invalidates on mode change and preserves measured records',
      (tester) async {
    final before = source(measured: true);
    final repo = await open(tester, plate: before);
    await tap(tester, 'medium-only-replacement');
    expect(key('medium-change-unit'), findsNothing);
    expect(key('medium-change-incoming-concentration'), findsNothing);
    await enter(tester, 'incoming-volume', '150');
    await enter(tester, 'medium', 'Fresh medium');
    await tap(tester, 'calculate-medium-change');
    expect(find.textContaining('처리 농도·단위 기록 해제'), findsOneWidget);
    await tap(tester, 'medium-only-replacement');
    expect(key('medium-change-final-volume'), findsNothing);
    await tap(tester, 'medium-only-replacement');
    await tap(tester, 'calculate-medium-change');
    await apply(tester);
    expect(repo.saveCount, 0);
    await tester.enterText(key('condition-correction-reason'), '배지만 전체 교체 기록');
    await tap(tester, 'confirm-condition-correction');
    final after = repo.plate!.wells.first;
    expect(after.volumeValue, 150);
    expect(after.concentrationValue, isNull);
    expect(after.concentrationUnit, isNull);
    expect(after.assayCondition!.medium, 'Fresh medium');
    expect(after.assayCondition!.vehiclePercent, 0);
    expect(after.assayCondition!.vehicle, isNull);
    expect(after.cellCondition, before.wells.first.cellCondition);
    expect(after.resultValue, 0);
    expect(after.excluded, true);
    expect(after.role, before.wells.first.role);
    expect(repo.plate!.revisions.length, 1);
  });

  for (final landscape in [false, true]) {
    testWidgets(
        'medium sheet keeps title and close inside device safe area, landscape=$landscape',
        (tester) async {
      final size = landscape ? const Size(852, 393) : const Size(393, 852);
      final insets = landscape
          ? const FakeViewPadding(left: 59, right: 59, bottom: 21)
          : const FakeViewPadding(top: 59, bottom: 34);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(tester.view.reset);
      final repo = await open(tester);
      final close = key('close-medium-change');
      final title = find.text('배지 추가·교체 계산');
      for (final finder in [close, title]) {
        final rect = tester.getRect(finder);
        expect(rect.top, greaterThanOrEqualTo(insets.top));
        expect(rect.left, greaterThanOrEqualTo(insets.left));
        expect(rect.right, lessThanOrEqualTo(size.width - insets.right));
      }
      // Opening a keyboard must not remove the route's top/lateral protection.
      tester.view.viewInsets = FakeViewPadding(bottom: landscape ? 160 : 300);
      tester.view.padding = FakeViewPadding(
          top: insets.top, left: insets.left, right: insets.right);
      await tester.pumpAndSettle();
      await tester.ensureVisible(close);
      await tester.pumpAndSettle();
      final rect = tester.getRect(close);
      expect(rect.top, greaterThanOrEqualTo(insets.top));
      expect(rect.bottom,
          lessThanOrEqualTo(size.height - (landscape ? 160 : 300)));
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(MediumChangeSheet), findsNothing);
      expect(repo.saveCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'previews partial replacement, invalidates stale results and explicitly records final conditions',
      (tester) async {
    final repo = await open(tester);
    final before = repo.plate!;
    expect(
        tester
            .widget<TextField>(key('medium-change-initial-volume'))
            .controller!
            .text,
        '100.0');
    expect(
        tester
            .widget<TextField>(key('medium-change-incoming-percent'))
            .controller!
            .text,
        isEmpty);
    await tap(tester, 'medium-change-mode-replacePart');
    await enter(tester, 'removed-volume', '40');
    await incoming(tester);
    expect(find.text('최종 부피 80 µL'), findsOneWidget);
    expect(find.text('최종 시약 농도 7.5 µM'), findsOneWidget);
    expect(tester.widget<FilledButton>(key('apply-medium-change')).onPressed,
        isNull);
    expect(repo.saveCount, 0);
    await enter(tester, 'incoming-volume', '30');
    await tester.pumpAndSettle();
    expect(key('apply-medium-change'), findsNothing);
    await enter(tester, 'incoming-volume', '20');
    await tap(tester, 'calculate-medium-change');
    await apply(tester);
    expect(find.byType(MediumChangeSheet), findsNothing);
    expect(repo.plate!.wells.first.volumeValue, 80);
    expect(repo.plate!.wells.first.concentrationValue, 7.5);
    expect(repo.plate!.wells.first.assayCondition!.vehiclePercent,
        closeTo(.075, 1e-12));
    expect(repo.plate!.wells.first.cellCondition,
        before.wells.first.cellCondition);
    expect(repo.plate!.wells.first.groupId, before.wells.first.groupId);
    expect(repo.plate!.wells.first.role, before.wells.first.role);
    expect(repo.plate!.wells[1].toJson(), before.wells[1].toJson());
    expect(repo.plate!.revisions.single.summary, contains('기존 100.0 µL'));
    expect(repo.plate!.revisions.single.summary, contains('제거 40.0 µL'));
    expect(
        tester.widget<ChoiceChip>(key('plate-medium-view')).selected, isTrue);
  });

  testWidgets(
      'conflicting source and other vehicles require review, full replacement uses only incoming solution',
      (tester) async {
    final repo = await open(tester);
    await enter(tester, 'initial-volume', '90');
    await incoming(tester);
    expect(find.textContaining('A1의 기존 부피 기록과 입력값이 다릅니다'), findsOneWidget);
    expect(key('apply-medium-change'), findsNothing);
    await enter(tester, 'initial-volume', '100');
    await enter(tester, 'vehicle', 'ethanol');
    await tap(tester, 'calculate-medium-change');
    expect(find.textContaining('기존 용매/비율 기록과 입력값이 다릅니다'), findsOneWidget);
    await tap(tester, 'medium-change-mode-replaceAll');
    expect(key('medium-change-initial-volume'), findsNothing);
    await incoming(tester, volume: '75', concentration: '2', percent: '.2');
    await apply(tester);
    expect(repo.plate!.wells.first.volumeValue, 75);
    expect(repo.plate!.wells.first.concentrationValue, 2);
    expect(repo.plate!.wells.first.assayCondition!.vehicle, 'ethanol');
    expect(repo.plate!.wells.first.assayCondition!.vehiclePercent, .2);
  });

  testWidgets(
      'measured zero and excluded wells require reason; save retry preserves inputs, snapshot and single history',
      (tester) async {
    final before = source(measured: true);
    final repo = await open(tester, plate: before);
    await incoming(tester);
    await apply(tester);
    expect(repo.saveCount, 0);
    await tap(tester, 'confirm-condition-correction');
    expect(find.text('측정 후 조건을 바꾸는 사유를 입력해주세요.'), findsOneWidget);
    await tester.enterText(key('condition-correction-reason'), '기존 배지 추가량 확인');
    repo.failNextSave = true;
    await tap(tester, 'confirm-condition-correction');
    expect(repo.plate!.toJson(), before.toJson());
    await tap(tester, 'retry-save-button');
    expect(repo.plate!.wells.first.volumeValue, 120);
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.wells.first.excluded, true);
    expect(repo.plate!.revisions, hasLength(1));
    expect(repo.plate!.revisions.single.snapshot!.wells.first.volumeValue, 100);
    expect(repo.plate!.revisions.single.summary, contains('기존 배지 추가량 확인'));
    expect(repo.plate!.revisions.single.summary, contains('추가 20.0 µL'));
  });

  testWidgets(
      'dirty close asks before discarding; read-only offers no calculator edits',
      (tester) async {
    final repo = await open(tester);
    await enter(tester, 'incoming-volume', '20');
    await tap(tester, 'close-medium-change');
    expect(find.text('추가·교체 계산 입력을 버릴까요?'), findsOneWidget);
    await tester.tap(find.text('계속 계산'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(key('medium-change-incoming-volume'))
            .controller!
            .text,
        '20');
    await tap(tester, 'close-medium-change');
    await tester.tap(find.text('입력 버리고 닫기'));
    await tester.pumpAndSettle();
    expect(repo.saveCount, 0);
    await tester.pumpWidget(const SizedBox());
    final locked = await open(tester, readOnly: true);
    expect(key('medium-change-action'), findsNothing);
    expect(locked.saveCount, 0);
  });

  testWidgets(
      'missing source stays blank; small-screen keyboard errors and large-text review remain visible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final p = source();
    await open(tester,
        plate: p.copyWith(wells: [
          p.wells.first.copyWith(
              volumeValue: null,
              concentrationValue: null,
              concentrationUnit: null,
              assayCondition: null),
          ...p.wells.skip(1)
        ]));
    for (final field in [
      'initial-volume',
      'initial-concentration',
      'initial-percent',
      'unit'
    ]) {
      expect(
          tester
              .widget<TextField>(key('medium-change-$field'))
              .controller!
              .text,
          isEmpty);
    }
    await enter(tester, 'incoming-volume', '20');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tap(tester, 'calculate-medium-change');
    expect(find.textContaining('미기록 값은 0으로 추정하지 않습니다'), findsOneWidget);
    final errorRect = tester.getRect(key('medium-change-error'));
    expect(errorRect.top, greaterThanOrEqualTo(0));
    expect(errorRect.bottom, lessThanOrEqualTo(460));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tap(tester, 'medium-change-mode-replaceAll');
    await enter(tester, 'unit', 'µM');
    await enter(tester, 'medium', 'DMEM');
    await incoming(tester, percent: '101');
    expect(find.textContaining('용매 비율은 0~100% v/v'), findsOneWidget);
    await incoming(tester, percent: '0');
    expect(key('medium-change-final-percent'), findsOneWidget);
    await apply(tester);
    expect(tester.takeException(), isNull);
  });
}
