import 'dart:convert';

import 'package:easycheck/app/theme.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/plate_exclusion_event.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:easycheck/features/plates/presentation/widgets/exclusion_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/assay_condition_fixture.dart';
import '../../../support/exclusion_event_fixture.dart';
import 'plate_editor_screen_test.dart'
    show FakePlateRepository, FakePlateTemplateRepository;

class _AttemptRepository extends FakePlateRepository {
  final attempts = <Plate>[];
  @override
  Future<void> savePlate(Plate plate) async {
    attempts.add(plate);
    await super.savePlate(plate);
  }
}

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

  Future<_AttemptRepository> open(WidgetTester tester,
      {Plate? plate, bool readOnly = false}) async {
    final repo = _AttemptRepository()..plate = plate ?? assayPlate();
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(),
        home: PlateEditorScreen(
            experimentId: 'e',
            repository: repo,
            readOnly: readOnly,
            templateRepository: FakePlateTemplateRepository())));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> exclude(WidgetTester tester, String reason) async {
    await tap(tester, key('well-A1'));
    await tap(tester, key('edit-selected-well-action'));
    await tap(tester, key('well-excluded-switch'));
    await tester.enterText(key('well-exclusion-reason-field'), reason);
    await tap(tester, key('save-well-record-button'));
  }

  testWidgets(
      'failed exclusion retry preserves event ID/time once; undo appends a new event without erasing old history',
      (tester) async {
    final repo = await open(tester);
    repo.failNextSave = true;
    await exclude(tester, '기포 원자료 확인');
    expect(repo.plate!.exclusionEvents, isEmpty);
    final failed = repo.attempts.single.exclusionEvents.single;
    expect(failed.source, ExclusionChangeSource.wellEdit);
    expect(failed.reason, '기포 원자료 확인');
    await tap(tester, key('retry-save-button'));
    expect(repo.plate!.exclusionEvents.single.toJson(), failed.toJson());
    expect(repo.plate!.wells.first.resultValue, .6);
    await tap(tester, find.text('실행 취소'));
    expect(repo.plate!.exclusionEvents, hasLength(2));
    expect(repo.plate!.exclusionEvents.first.toJson(), failed.toJson());
    expect(repo.plate!.exclusionEvents.last.source, ExclusionChangeSource.undo);
    expect(repo.plate!.exclusionEvents.last.afterExcluded, false);
    expect(repo.plate!.wells.first.excluded, false);
  });

  testWidgets(
      'ordinary edits trim snapshots but retain every exclusion event; restoring snapshots also retains and appends events',
      (tester) async {
    final base = assayPlate();
    final old = base.copyWith(wells: [
      base.wells.first.copyWith(excluded: true),
      ...base.wells.skip(1)
    ]);
    final source = base.copyWith(exclusionEvents: [
      for (var i = 0; i < 30; i++) exclusionEvent(i)
    ], revisions: [
      for (var i = 0; i < 20; i++)
        PlateRevision(
            id: 'rev-$i',
            changedAt: DateTime.utc(2026, 11, 1, 10, i),
            summary: 'Snapshot $i',
            snapshot: PlateSnapshot.fromPlate(old)),
    ]);
    final repo = await open(tester, plate: source);
    await tap(tester, key('well-A1'));
    await tap(tester, key('edit-selected-well-action'));
    await tester.enterText(key('well-note-field'), '관찰 메모');
    await tap(tester, key('save-well-record-button'));
    expect(repo.plate!.revisions, hasLength(20));
    expect(repo.plate!.exclusionEvents, hasLength(30));
    await tap(tester, key('plate-more-menu'));
    await tap(tester, find.text('전체 변경 이력'));
    final restoreButton = find.widgetWithText(TextButton, '이 시점으로 복원');
    await tap(tester, restoreButton.at(1));
    await tap(tester, key('confirm-restore-plate-revision'));
    expect(repo.plate!.exclusionEvents, hasLength(31));
    expect(
        repo.plate!.exclusionEvents.last.source, ExclusionChangeSource.restore);
    expect(repo.plate!.exclusionEvents.last.afterExcluded, true);
    expect(repo.plate!.wells.first.resultValue, .6);
  });

  testWidgets(
      'read-only editor opens filtered history/comparison without writing or changing exclusion',
      (tester) async {
    final base = assayPlate();
    final plate = base.copyWith(wells: [
      base.wells.first.copyWith(excluded: true),
      ...base.wells.skip(1)
    ], exclusionEvents: [
      exclusionEvent(0)
    ]);
    final repo = await open(tester, plate: plate, readOnly: true);
    final before = jsonEncode(plate.toJson());
    await tap(tester, key('well-A1'));
    await tap(tester, key('well-exclusion-review'));
    expect(find.byType(ExclusionReviewScreen), findsOneWidget);
    expect(find.text('가상 포함: A1'), findsOneWidget);
    expect(find.textContaining('과거 시점의 분석 재현이 아니며'), findsOneWidget);
    await tap(tester, key('exclusion-history-tab'));
    expect(find.text('A1 · 포함 → 제외'), findsOneWidget);
    expect(find.text('사유 / 변경 경로: 기포 확인 0'), findsOneWidget);
    expect(find.textContaining('0.0 OD450 → 0.0 OD450'), findsOneWidget);
    expect(repo.saveCount, 0);
    expect(jsonEncode(repo.plate!.toJson()), before);
  });

  testWidgets(
      'narrow large-text comparison and well filtering remain usable, including absent history',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final base = assayPlate();
    final p = base.copyWith(wells: [
      base.wells.first.copyWith(excluded: true),
      ...base.wells.skip(1)
    ]);
    await tester.pumpWidget(MaterialApp(
        theme: buildEasyCheckTheme(), home: ExclusionReviewScreen(plate: p)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tap(tester, key('exclusion-well-filter'));
    await tester.tap(find.text('A2').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pumpAndSettle();
    expect(find.text('선택 범위에 현재 제외된 well이 없습니다.'), findsOneWidget);
    await tap(tester, key('exclusion-history-tab'));
    expect(find.textContaining('전용 제외 이력이 없습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
