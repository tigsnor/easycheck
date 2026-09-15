import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tracks and saves experiment execution tasks', (tester) async {
    Experiment? saved;
    final experiment = Experiment(
      id: 'experiment-1',
      title: 'CCK-8 test',
      experimentType: 'CCK-8',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentDetailScreen(
          experiment: experiment,
          onChanged: (experiment) async => saved = experiment,
        ),
      ),
    );

    expect(find.text('실험 실행 체크리스트'), findsOneWidget);
    expect(find.text('0/7 완료'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('experiment-task-default-0')));
    await tester.pump();
    expect(find.text('1/7 완료'), findsOneWidget);

    await tester.ensureVisible(find.text('단계 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('단계 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-experiment-task-field')),
      '현미경 사진 촬영',
    );
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pumpAndSettle();
    expect(find.text('현미경 사진 촬영'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.tasks, hasLength(8));
    expect(saved!.tasks.first.isCompleted, isTrue);
    expect(saved!.tasks.first.completedAt, isNotNull);
    expect(saved!.tasks.last.title, '현미경 사진 촬영');
  });

  testWidgets('records task start, elapsed time, and completion', (
    tester,
  ) async {
    Experiment? saved;
    final experiment = Experiment(
      id: 'experiment-2',
      title: 'Timed CCK-8 test',
      experimentType: 'CCK-8',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentDetailScreen(
          experiment: experiment,
          onChanged: (experiment) async => saved = experiment,
        ),
      ),
    );

    final timerButton = find.byKey(
      const ValueKey('experiment-task-timer-default-0'),
    );
    await tester.ensureVisible(timerButton);
    await tester.tap(timerButton);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('경과'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '완료'), findsOneWidget);

    await tester.ensureVisible(timerButton);
    await tester.tap(timerButton);
    await tester.pump();
    expect(find.textContaining('완료 ·'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pump();
    expect(saved!.tasks.first.startedAt, isNotNull);
    expect(saved!.tasks.first.completedAt, isNotNull);
    expect(
      saved!.tasks.first.completedAt!.isBefore(saved!.tasks.first.startedAt!),
      isFalse,
    );
  });

  testWidgets('records researcher and reagent lot information', (tester) async {
    Experiment? saved;
    final experiment = Experiment(
      id: 'experiment-3',
      title: 'Resource tracking test',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentDetailScreen(
          experiment: experiment,
          onChanged: (experiment) async => saved = experiment,
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '담당자'), '홍길동');
    await tester.scrollUntilVisible(
      find.text('시약·장비 추가'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('시약·장비 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('시약·장비 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('resource-name-field')),
      'CCK-8',
    );
    await tester.enterText(
      find.byKey(const ValueKey('resource-lot-field')),
      'LOT-123',
    );
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pumpAndSettle();

    expect(find.text('CCK-8'), findsWidgets);
    expect(find.textContaining('Lot LOT-123'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pump();
    expect(saved!.researcher, '홍길동');
    expect(saved!.resources.single.name, 'CCK-8');
    expect(saved!.resources.single.lotOrSerial, 'LOT-123');
  });

  testWidgets('locks completed notes and records the reason after editing', (
    tester,
  ) async {
    Experiment? saved;
    final experiment = Experiment(
      id: 'experiment-4',
      title: 'Completed test',
      status: ExperimentStatus.completed,
      completedAt: DateTime.utc(2026, 9, 15, 10),
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentDetailScreen(
          experiment: experiment,
          onChanged: (experiment) async => saved = experiment,
        ),
      ),
    );

    expect(find.text('완료된 실험 노트입니다'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '저장'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Completed test'))
          .enabled,
      isFalse,
    );

    await tester.tap(find.text('수정 잠금 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '수정 시작'));
    await tester.pump();
    expect(find.text('수정 사유를 입력해주세요.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('completion-edit-reason-field')),
      'Lot 번호 정정',
    );
    await tester.tap(find.widgetWithText(FilledButton, '수정 시작'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Completed test'),
      'Corrected test',
    );
    await tester.tap(find.widgetWithText(TextButton, '저장'));
    await tester.pump();

    expect(saved!.title, 'Corrected test');
    expect(saved!.revisions.single.summary, '완료 후 수정');
    expect(saved!.revisions.single.reason, 'Lot 번호 정정');
    expect(find.text('완료된 실험 노트입니다'), findsOneWidget);
  });
}
