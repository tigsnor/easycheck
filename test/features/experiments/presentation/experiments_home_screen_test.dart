import 'package:easycheck/features/experiments/data/experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeExperimentRepository implements ExperimentRepository {
  FakeExperimentRepository(this.experiments);

  final List<Experiment> experiments;

  @override
  Future<void> deleteExperiment(String id) async {
    experiments.removeWhere((experiment) => experiment.id == id);
  }

  @override
  Future<List<Experiment>> loadExperiments() async => [...experiments];

  @override
  Future<void> saveExperiment(Experiment experiment) async {
    final index = experiments.indexWhere((item) => item.id == experiment.id);
    if (index == -1) {
      experiments.add(experiment);
    } else {
      experiments[index] = experiment;
    }
  }
}

void main() {
  testWidgets('renders saved experiments and filters by search query', (
    tester,
  ) async {
    final repository = FakeExperimentRepository([
      Experiment(
        id: 'experiment-1',
        title: 'Drug A CCK-8',
        experimentType: 'CCK-8',
        createdAt: DateTime.utc(2026, 6, 4),
        updatedAt: DateTime.utc(2026, 6, 4),
        tags: const ['CCK8'],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: ExperimentsHomeScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('실험 노트'), findsOneWidget);
    expect(find.text('Drug A CCK-8'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('Drug A CCK-8'), findsNothing);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
  });

  testWidgets('creates a new experiment through the bottom sheet', (
    tester,
  ) async {
    final repository = FakeExperimentRepository([]);

    await tester.pumpWidget(
      MaterialApp(home: ExperimentsHomeScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('첫 실험 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '실험 제목'), 'MTT test');
    await tester.tap(find.text('생성'));
    await tester.pumpAndSettle();

    expect(repository.experiments.single.title, 'MTT test');
    expect(find.text('MTT test'), findsOneWidget);
  });
}
