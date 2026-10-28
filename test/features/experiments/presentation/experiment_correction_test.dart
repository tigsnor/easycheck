import 'dart:async';

import 'package:easycheck/features/attachments/presentation/experiment_attachments_screen.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/plates/presentation/plate_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../plates/presentation/plate_editor_screen_test.dart'
    show FakePlateRepository;

void main() {
  late List<Experiment> saved;
  late Experiment original;
  late FakePlateRepository plates;
  setUp(() {
    saved = [];
    plates = FakePlateRepository();
    original = Experiment(
        id: 'e',
        title: 'Original assay',
        notes: 'Original observation',
        status: ExperimentStatus.completed,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 10),
        completedAt: DateTime.utc(2026, 10),
        tasks: const []);
  });
  Future<void> open(WidgetTester tester,
      {Experiment? value,
      Future<void> Function(Experiment)? save,
      bool narrow = false}) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!)
            : null,
        home: ExperimentDetailScreen(
            experiment: value ?? original,
            plateRepository: plates,
            onChanged: save ??
                (e) async {
                  saved.add(e);
                })));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 250,
          scrollable: find.byType(Scrollable).last);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> section(WidgetTester tester, String name) =>
      tap(tester, find.byKey(ValueKey('experiment-section-$name')));
  Future<void> start(WidgetTester tester,
      {String reason = '원자료 대조 후 정정'}) async {
    await tap(tester, find.text('수정 잠금 해제'));
    await tester.enterText(
        find.byKey(const ValueKey('completion-edit-reason-field')), reason);
    tester.testTextInput.hide();
    await tap(tester, find.widgetWithText(FilledButton, '수정 시작'));
  }

  Future<void> review(WidgetTester tester) async {
    await section(tester, 'results');
    await tap(tester, find.byKey(const ValueKey('complete-experiment')));
  }

  Future<void> confirm(WidgetTester tester) async {
    await tap(tester, find.byKey(const ValueKey('completion-review-note')));
    await tester.enterText(find.byKey(const ValueKey('completion-review-note')),
        'Plate 미사용, 원본 재확인');
    tester.testTextInput.hide();
    await tap(tester, find.byKey(const ValueKey('confirm-completion-review')));
  }

  testWidgets(
      'reason persists before editing; save and reopen keep correction and editable Plate/attachments',
      (tester) async {
    await open(tester);
    await start(tester);
    expect(saved.single.status, ExperimentStatus.correcting);
    expect(saved.single.revisions.single.before!.toJson(), original.toJson());
    expect(saved.single.tasks, isEmpty);
    await section(tester, 'design');
    await tester.enterText(
        find.widgetWithText(TextField, 'Original assay'), 'Corrected assay');
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(saved.last.status, ExperimentStatus.correcting);
    expect(saved.last.revisions.last.before!.title, 'Original assay');
    await open(tester, value: saved.last);
    await tap(tester, find.byKey(const ValueKey('open-result-plate')));
    expect(
        tester
            .widget<PlateEditorScreen>(find.byType(PlateEditorScreen))
            .readOnly,
        isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(
        tester, find.byKey(const ValueKey('open-experiment-attachments')));
    expect(
        tester
            .widget<ExperimentAttachmentsScreen>(
                find.byType(ExperimentAttachmentsScreen))
            .readOnly,
        isFalse);
    expect(saved.length,
        2); // Navigation without edits creates no duplicate history.
  });

  testWidgets('failed start stays locked, retains reason and retries once',
      (tester) async {
    var fail = true;
    await open(tester, save: (e) async {
      if (fail) throw StateError('disk');
      saved.add(e);
    });
    await start(tester);
    expect(saved, isEmpty);
    expect(find.text('완료된 실험 노트입니다'), findsOneWidget);
    await tap(tester, find.text('수정 잠금 해제'));
    expect(find.text('원자료 대조 후 정정'), findsOneWidget);
    fail = false;
    await tap(tester, find.widgetWithText(FilledButton, '수정 시작'));
    expect(saved.single.revisions.length, 1);
    expect(saved.single.status, ExperimentStatus.correcting);
  });

  testWidgets('cancel or blank reason never unlocks or writes', (tester) async {
    await open(tester);
    await tap(tester, find.text('수정 잠금 해제'));
    await tap(tester, find.widgetWithText(FilledButton, '수정 시작'));
    expect(find.text('수정 사유를 입력해주세요.'), findsOneWidget);
    await tap(tester, find.text('취소'));
    expect(saved, isEmpty);
    expect(find.text('완료된 실험 노트입니다'), findsOneWidget);
  });

  testWidgets('in-flight start blocks back and duplicate actions',
      (tester) async {
    final gate = Completer<void>();
    await open(tester, save: (e) async {
      saved.add(e);
      await gate.future;
    });
    await start(tester);
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
    expect(find.text('정정 중 · 재검토 필요'), findsOneWidget);
  });

  testWidgets(
      'review cancel keeps correction; successful review preserves first completion',
      (tester) async {
    await open(tester);
    await start(tester);
    await review(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(saved.length, 1);
    expect(saved.last.status, ExperimentStatus.correcting);
    expect(find.text('정정 내용 재검토 후 완료'), findsOneWidget);
    await review(tester);
    await confirm(tester);
    expect(saved.last.status, ExperimentStatus.completed);
    expect(saved.last.completedAt, original.completedAt);
    expect(saved.last.revisions.last.summary, '정정 후 재검토 완료');
    expect(saved.last.revisions.last.reason, contains('Plate 미사용'));
    expect(find.text('수정 잠금 해제'), findsOneWidget);
    await tap(
        tester, find.byKey(const ValueKey('open-experiment-attachments')));
    expect(
        tester
            .widget<ExperimentAttachmentsScreen>(
                find.byType(ExperimentAttachmentsScreen))
            .readOnly,
        isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await start(tester, reason: '두 번째 정정');
    await review(tester);
    final note = find.byKey(const ValueKey('completion-review-note'));
    await tap(tester, note);
    expect(tester.widget<TextField>(note).controller!.text, isEmpty);
  });

  testWidgets(
      'legacy missing first completion remains unknown after correction review',
      (tester) async {
    await open(tester, value: original.copyWith(completedAt: null));
    await start(tester);
    await review(tester);
    await confirm(tester);
    expect(saved.last.status, ExperimentStatus.completed);
    expect(saved.last.completedAt, isNull);
    expect(saved.last.revisions.last.summary, '정정 후 재검토 완료');
  });

  testWidgets('unreadable Plate blocks correction completion until retry',
      (tester) async {
    await open(tester);
    await start(tester);
    plates.failNextLoad = true;
    await review(tester);
    expect(find.textContaining('Plate를 읽지 못해'), findsOneWidget);
    expect(saved.length, 1);
    await tap(tester, find.text('다시 점검'));
    await confirm(tester);
    expect(saved.last.status, ExperimentStatus.completed);
  });

  testWidgets(
      'failed final review save retains review memo and does not duplicate revisions on retry',
      (tester) async {
    var fail = false;
    await open(tester, save: (e) async {
      if (fail) throw StateError('disk');
      saved.add(e);
    });
    await start(tester);
    fail = true;
    await review(tester);
    await confirm(tester);
    expect(saved.single.status, ExperimentStatus.correcting);
    fail = false;
    await tap(tester, find.widgetWithText(TextButton, '저장'));
    expect(find.text('Plate 미사용, 원본 재확인'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('confirm-completion-review')));
    expect(saved.last.revisions.length, 2);
    expect(saved.last.completedAt, original.completedAt);
  });

  testWidgets('correction status cannot bypass review through dropdown',
      (tester) async {
    await open(tester,
        value: original.beginCorrection('정정', DateTime.utc(2026, 11)));
    await section(tester, 'design');
    final field = tester.widget<DropdownButtonFormField<ExperimentStatus>>(
        find.byType(DropdownButtonFormField<ExperimentStatus>));
    expect(field.onChanged, isNull);
  });

  testWidgets(
      'archived note, results and attachments stay read-only; restore completed remains locked',
      (tester) async {
    await open(tester,
        value: original.copyWith(status: ExperimentStatus.archived));
    expect(find.text('수정 잠금 해제'), findsNothing);
    await tap(tester, find.byKey(const ValueKey('open-result-plate')));
    expect(
        tester
            .widget<PlateEditorScreen>(find.byType(PlateEditorScreen))
            .readOnly,
        isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(
        tester, find.byKey(const ValueKey('open-experiment-attachments')));
    expect(
        tester
            .widget<ExperimentAttachmentsScreen>(
                find.byType(ExperimentAttachmentsScreen))
            .readOnly,
        isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(TextButton, '보관 해제'));
    await tap(tester, find.widgetWithText(FilledButton, '보관 해제'));
    expect(saved.single.status, ExperimentStatus.completed);
    expect(find.text('완료된 실험 노트입니다'), findsOneWidget);
  });

  testWidgets(
      'archive from completed without legacy timestamp restores completed',
      (tester) async {
    await open(tester, value: original.copyWith(completedAt: null));
    await tap(tester, find.text('노트 보관'));
    await tap(tester, find.widgetWithText(FilledButton, '보관'));
    expect(saved.single.status, ExperimentStatus.archived);
    await tap(tester, find.widgetWithText(TextButton, '보관 해제'));
    await tap(tester, find.widgetWithText(FilledButton, '보관 해제'));
    expect(saved.last.status, ExperimentStatus.completed);
    expect(saved.last.completedAt, isNull);
  });

  testWidgets(
      'legacy archive without completion restores draft; failure never unlocks',
      (tester) async {
    var fail = true;
    await open(tester,
        value: original.copyWith(
            status: ExperimentStatus.archived,
            completedAt: null), save: (e) async {
      if (fail) throw StateError('disk');
      saved.add(e);
    });
    await tap(tester, find.widgetWithText(TextButton, '보관 해제'));
    expect(find.text('최초 완료 기록이 없어 초안 상태로 돌아갑니다.'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, '보관 해제'));
    expect(saved, isEmpty);
    expect(find.text('보관된 실험 노트입니다'), findsOneWidget);
    fail = false;
    await tap(tester, find.widgetWithText(TextButton, '보관 해제'));
    await tap(tester, find.widgetWithText(FilledButton, '보관 해제'));
    expect(saved.single.status, ExperimentStatus.draft);
  });

  testWidgets('correction and history fit narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, narrow: true);
    await start(tester);
    await tap(tester, find.text('완료 후 정정 시작'));
    expect(find.textContaining('Original observation'), findsOneWidget);
    expect(find.textContaining('변경 전 노트'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
