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
}
