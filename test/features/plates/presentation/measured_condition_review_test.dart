import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/measured_condition_review.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/measured_condition_review_screen.dart';
import '../../../support/condition_review_fixture.dart';
import 'plate_editor_screen_test.dart'
    show FakePlateRepository, FakePlateTemplateRepository;

void main() {
  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<FakePlateRepository> open(WidgetTester tester,
      {Plate? plate, bool readOnly = false}) async {
    final repo = FakePlateRepository()..plate = plate ?? measuredPlate();
    await tester.pumpWidget(MaterialApp(
        home: PlateEditorScreen(
      experimentId: 'e',
      repository: repo,
      readOnly: readOnly,
      templateRepository: FakePlateTemplateRepository(),
    )));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> editConcentration(WidgetTester tester) async {
    await tap(tester, key('well-A1'));
    await tap(tester, key('edit-selected-well-action'));
    await tester.enterText(key('well-concentration-value-field'), '4');
    await tap(tester, key('save-well-record-button'));
  }

  Future<void> approve(WidgetTester tester, String reason) async {
    await tester.enterText(key('condition-correction-reason'), reason);
    await tap(tester, key('confirm-condition-correction'));
  }

  Future<void> history(WidgetTester tester) async {
    await tap(tester, key('plate-more-menu'));
    await tap(tester, find.text('전체 변경 이력'));
  }

  testWidgets(
      'well changes require a reason, failed save retries once and history exposes the record',
      (tester) async {
    final repo = await open(tester);
    final original = repo.plate!;
    await editConcentration(tester);
    expect(repo.saveCount, 0);
    expect(find.text('측정된 1개 well의 조건이 바뀝니다.'), findsOneWidget);
    expect(find.textContaining('변경 전: 2.0 µM'), findsOneWidget);
    expect(find.textContaining('변경 후: 4.0 µM'), findsOneWidget);
    await tap(tester, key('confirm-condition-correction'));
    expect(find.text('측정 후 조건을 바꾸는 사유를 입력해주세요.'), findsOneWidget);
    repo.failNextSave = true;
    await approve(tester, '실제 분주 기록 확인');
    expect(repo.plate!.toJson(), original.toJson());
    await tap(tester, key('retry-save-button'));
    expect(repo.saveCount, 2);
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.wells.first.concentrationValue, 4);
    final revision = repo.plate!.revisions.single;
    expect(revision.summary.split('정정 사유:').length, 2);
    expect(
        revision.snapshot!.wells.first.toJson(), original.wells.first.toJson());
    await history(tester);
    await tap(tester, find.text('well 수정: A1'));
    expect(find.textContaining('실제 분주 기록 확인'), findsOneWidget);
    expect(find.textContaining('농도: 2.0 µM → 4.0 µM'), findsOneWidget);
  });

  testWidgets(
      'cancelling a group reassignment leaves every well and group unchanged',
      (tester) async {
    final repo = await open(tester);
    final original = repo.plate!;
    await tap(tester, key('row-header-A'));
    await tap(tester, key('assign-selected-group-action'));
    await tester.enterText(find.widgetWithText(TextField, '그룹명'), 'Drug B');
    await tap(tester, find.widgetWithText(FilledButton, '적용'));
    expect(find.text('측정된 1개 well의 조건이 바뀝니다.'), findsOneWidget);
    expect(find.text('이외 11개 well의 변경도 함께 저장됩니다.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(repo.saveCount, 0);
    expect(repo.plate!.toJson(), original.toJson());
    await tap(tester, key('assign-selected-group-action'));
    await tester.enterText(find.widgetWithText(TextField, '그룹명'), 'Drug B');
    await tap(tester, find.widgetWithText(FilledButton, '적용'));
    await approve(tester, '그룹 배치 오기 확인');
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.groups.last.name, 'Drug B');
    expect(repo.plate!.revisions.single.summary, contains('그룹 연결 ID: g →'));
  });

  testWidgets('dilution reapplication preserves measurements only after review',
      (tester) async {
    final repo = await open(tester);
    await tap(tester, key('apply-dilution-action'));
    await tester.enterText(find.widgetWithText(TextField, '시작 농도'), '90');
    await tester.enterText(find.widgetWithText(TextField, '단계 수'), '2');
    await tester.enterText(find.widgetWithText(TextField, '반복 well 수'), '1');
    await tap(tester, find.byType(SwitchListTile));
    await tap(tester, key('confirm-dilution-apply'));
    expect(repo.saveCount, 0);
    expect(find.textContaining('변경 후: 90.0'), findsOneWidget);
    await approve(tester, '희석 배치 기록 대조');
    expect(repo.plate!.wells.first.concentrationValue, 90);
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.revisions.single.summary, contains('희석 배치 기록 대조'));
  });

  testWidgets('templates cannot wipe existing zero or excluded measurements',
      (tester) async {
    final original =
        replaceWell(measuredPlate(), 'A1', (w) => w.copyWith(excluded: true));
    final repo = await open(tester, plate: original);
    await tap(tester, key('plate-more-menu'));
    await tap(tester, find.text('저장된 템플릿 적용'));
    expect(find.text('측정값이 있는 Plate입니다'), findsOneWidget);
    await tap(tester, find.text('확인'));
    expect(repo.saveCount, 0);
    expect(repo.plate!.toJson(), original.toJson());
  });

  testWidgets('history restoration reviews changed measured conditions',
      (tester) async {
    final repo = await open(tester);
    await editConcentration(tester);
    await approve(tester, '조건 정정');
    await history(tester);
    await tap(tester, find.text('이 시점으로 복원').first);
    await tap(tester, key('confirm-restore-plate-revision'));
    expect(find.textContaining('변경 전: 4.0 µM'), findsOneWidget);
    expect(repo.saveCount, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(repo.plate!.wells.first.concentrationValue, 4);
    await history(tester);
    await tap(tester, find.text('이 시점으로 복원').first);
    await tap(tester, key('confirm-restore-plate-revision'));
    await approve(tester, '원기록 재확인 후 복원');
    expect(repo.plate!.wells.first.concentrationValue, 2);
    expect(repo.plate!.wells.first.resultValue, 0);
    expect(repo.plate!.revisions.length, 2);
    expect(repo.plate!.revisions.last.summary, contains('원기록 재확인 후 복원'));
  });

  testWidgets(
      'immediate undo reverses the reviewed change and retains its reason',
      (tester) async {
    final repo = await open(tester);
    final original = repo.plate!;
    await editConcentration(tester);
    await approve(tester, '기록 확인');
    await tap(tester, find.byTooltip('마지막 Plate 변경 실행 취소'));
    expect(repo.plate!.wells.first.toJson(), original.wells.first.toJson());
    expect(repo.plate!.revisions.first.summary, contains('정정 사유: 기록 확인'));
    expect(repo.plate!.revisions.last.summary, '마지막 Plate 변경 실행 취소');
    expect(find.text('측정 후 조건 정정'), findsNothing);
  });

  testWidgets(
      'continuous entry keeps review reason across a failed unit correction',
      (tester) async {
    final repo = await open(tester);
    await tap(tester, key('well-A1'));
    await tap(tester, key('sequential-results-action'));
    await tester.enterText(key('sequential-unit'), 'RFU');
    await tap(tester, key('sequential-save-close'));
    repo.failNextSave = true;
    await approve(tester, '측정 단위 정정');
    expect(repo.plate!.wells.first.resultUnit, 'OD450');
    expect(key('sequential-save-error'), findsOneWidget);
    await tap(tester, key('sequential-save-close'));
    expect(find.text('측정 후 조건 정정'), findsNothing);
    expect(repo.plate!.wells.first.resultUnit, 'RFU');
    expect(repo.plate!.revisions.single.summary.split('정정 사유:').length, 2);
    expect(repo.plate!.revisions.single.summary, contains('측정 단위 정정'));
  });

  testWidgets('discarded continuous-entry corrections must be reviewed again',
      (tester) async {
    final repo = await open(tester);
    await tap(tester, key('well-A1'));
    await tap(tester, key('sequential-results-action'));
    await tester.enterText(key('sequential-unit'), 'RFU');
    await tap(tester, key('sequential-save-close'));
    repo.failNextSave = true;
    await approve(tester, '처음 정정 사유');
    await tap(tester, key('close-sequential-results'));
    await tap(tester, find.text('입력 버리고 닫기'));
    await tap(tester, key('sequential-results-action'));
    await tester.enterText(key('sequential-unit'), 'RFU');
    await tap(tester, key('sequential-save-close'));
    expect(find.text('측정 후 조건 정정'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(key('condition-correction-reason'))
            .controller!
            .text,
        '');
    await approve(tester, '다시 검토한 정정 사유');
    expect(repo.plate!.revisions.single.summary, contains('다시 검토한 정정 사유'));
    expect(repo.plate!.revisions.single.summary, isNot(contains('처음 정정 사유')));
  });

  testWidgets('read-only Plate still prevents editing and template application',
      (tester) async {
    final repo = await open(tester, readOnly: true);
    await tap(tester, key('well-A1'));
    expect(key('edit-selected-well-action'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, key('plate-more-menu'));
    expect(find.text('전체 변경 이력'), findsOneWidget);
    expect(find.text('저장된 템플릿 적용'), findsNothing);
    expect(find.text('결과 연속 입력'), findsNothing);
    expect(repo.saveCount, 0);
  });

  testWidgets(
      'all 96 comparisons, cancellation and keyboard remain usable at 320px',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final before = measuredPlate().copyWith(wells: [
      for (final w in measuredPlate().wells) w.copyWith(resultValue: 0)
    ]);
    final after = before.copyWith(wells: [
      for (final w in before.wells) w.copyWith(concentrationValue: 4)
    ]);
    String? record;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
                viewInsets: const EdgeInsets.only(bottom: 250)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      record = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MeasuredConditionReviewScreen(
                                  review: MeasuredConditionReview.compare(
                                      before, after))));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(key('condition-correction-reason'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(key('condition-correction-reason'), '전체 배치 확인');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, find.text('계속 검토'));
    expect(
        tester
            .widget<TextField>(key('condition-correction-reason'))
            .controller!
            .text,
        '전체 배치 확인');
    await tester.scrollUntilVisible(key('condition-change-H12'), 600,
        maxScrolls: 100, scrollable: find.byType(Scrollable).first);
    await tap(tester, key('confirm-condition-correction'));
    expect(record, contains('H12 · 결과:'));
    expect(record, contains('정정 사유: 전체 배치 확인'));
    expect(tester.takeException(), isNull);
  });
}
