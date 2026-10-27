import 'dart:async';

import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/plates/data/plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/features/plates/domain/well_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Plates implements PlateRepository {
  Plate? plate;
  bool fail = false;
  int saves = 0;
  @override
  Future<Plate?> loadPlate(String id) async {
    if (fail) throw StateError('unreadable');
    return plate;
  }

  @override
  Future<void> savePlate(Plate value) async {
    plate = value;
    saves++;
  }

  @override
  Future<void> deletePlate(String id) async {
    plate = null;
  }
}

void main() {
  late _Plates repository;
  late List<Experiment> saved;
  setUp(() {
    repository = _Plates();
    saved = [];
  });
  Future<void> open(WidgetTester tester,
      {Future<void> Function(Experiment)? save, bool narrow = false}) async {
    await tester.pumpWidget(MaterialApp(
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!)
            : null,
        home: ExperimentDetailScreen(
            experiment: Experiment(
                id: 'e',
                title: 'Assay',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                tasks: const [
                  ExperimentTask(id: 't', title: '측정', isCompleted: true)
                ]),
            plateRepository: repository,
            onChanged: save ??
                (value) async {
                  saved.add(value);
                })));
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<ExperimentStatus>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, {String? note}) async {
    if (note != null) {
      final field = find.byKey(const ValueKey('completion-review-note'));
      await tester.scrollUntilVisible(field, 250,
          scrollable: find.byType(Scrollable).last);
      await tester.enterText(field, note);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
    }
    final button = find.byKey(const ValueKey('confirm-completion-review'));
    await tester.scrollUntilVisible(button, 250,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('completion is deferred until review; exceptions require note',
      (tester) async {
    await open(tester);
    expect(find.text('완료 전 점검'), findsOneWidget);
    expect(saved, isEmpty);
    await confirm(tester);
    expect(saved, isEmpty);
    expect(find.text('미측정·제외 등 확인 항목의 사유를 적어 주세요.'), findsOneWidget);
    await confirm(tester, note: 'Plate 없이 관찰만 수행');
    expect(saved.single.status, ExperimentStatus.completed);
    expect(saved.single.completedAt, isNotNull);
    expect(saved.single.revisions.single.reason, contains('Plate 없이 관찰만 수행'));
    expect(find.text('수정 잠금 해제'), findsOneWidget);
  });

  testWidgets('clean review permits completion without a note', (tester) async {
    final p = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    repository.plate = p.copyWith(wells: [
      for (final w in p.wells)
        if (w.label == 'A1')
          w.copyWith(role: WellRole.blank, resultValue: 0, resultUnit: 'OD450')
        else if (w.label == 'A2')
          w.copyWith(
              role: WellRole.vehicleControl,
              resultValue: 1,
              resultUnit: 'OD450')
        else
          w
    ]);
    await open(tester);
    expect(find.text('확인할 항목이 없습니다'), findsOneWidget);
    await confirm(tester);
    expect(saved.single.revisions.single.reason, '완료 전 점검: 0개 확인 항목');
  });

  testWidgets('cancel keeps form and review note without completing',
      (tester) async {
    await open(tester);
    final field = find.byKey(const ValueKey('completion-review-note'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '검토 중');
    tester.testTextInput.hide();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('수정 잠금 해제'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('검토 중'), findsOneWidget);
  });

  testWidgets('read failure prevents completion and supports retry',
      (tester) async {
    repository.fail = true;
    await open(tester);
    expect(find.textContaining('Plate를 읽지 못해'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('confirm-completion-review')), findsNothing);
    expect(saved, isEmpty);
    repository.fail = false;
    await tester.tap(find.text('다시 점검'));
    await tester.pumpAndSettle();
    await confirm(tester, note: 'Plate 미사용');
    expect(saved.length, 1);
  });

  testWidgets('failed save retains note and retries without duplicate history',
      (tester) async {
    var fail = true;
    await open(tester, save: (value) async {
      if (fail) throw StateError('disk full');
      saved.add(value);
    });
    await confirm(tester, note: 'Plate 미사용');
    expect(saved, isEmpty);
    expect(find.text('수정 잠금 해제'), findsNothing);
    fail = false;
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('Plate 미사용'), findsOneWidget);
    await confirm(tester);
    expect(saved.single.revisions.length, 1);
  });

  testWidgets('save in flight blocks duplicate saves and back navigation',
      (tester) async {
    final gate = Completer<void>();
    await open(tester, save: (value) async {
      saved.add(value);
      await gate.future;
    });
    final field = find.byKey(const ValueKey('completion-review-note'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Plate 미사용');
    tester.testTextInput.hide();
    final button = find.byKey(const ValueKey('confirm-completion-review'));
    await tester.scrollUntilVisible(button, 250,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(button);
    await tester.pump(const Duration(seconds: 1));
    expect(saved.length, 1);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '저장 중…'))
            .onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ExperimentDetailScreen), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(saved.length, 1);
    expect(find.text('수정 잠금 해제'), findsOneWidget);
  });

  testWidgets(
      'well link opens exact H12 editor and refreshes review after save',
      (tester) async {
    final p = Plate(id: 'p', experimentId: 'e', name: 'Plate');
    repository.plate = p.copyWith(wells: [
      for (final w in p.wells)
        w.label == 'H12' ? w.copyWith(role: WellRole.sample) : w
    ]);
    await open(tester);
    expect(find.text('결과 미입력 1개'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'H12').first);
    await tester.pumpAndSettle();
    expect(find.text('H12 well 기록'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('well-result-value-field')), '0');
    tester.testTextInput.hide();
    final saveWell = find.byKey(const ValueKey('save-well-record-button'));
    await tester.ensureVisible(saveWell);
    await tester.tap(saveWell);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('완료 전 점검'), findsOneWidget);
    expect(find.text('결과 미입력 1개'), findsNothing);
    expect(repository.plate!.wells.last.resultValue, 0);
    expect(repository.saves, 1);
    expect(saved, isEmpty);
    await confirm(tester, note: 'Blank 및 Control 미사용');
    expect(saved.single.revisions.single.reason, isNot(contains('결과 미입력')));
  });

  testWidgets('review fits 320px with large text and keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, narrow: true);
    await confirm(tester, note: 'Plate 미사용');
    expect(saved.length, 1);
    expect(tester.takeException(), isNull);
  });
}
