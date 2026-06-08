import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/data/experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/plates/data/plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
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

class FakePlateRepository implements PlateRepository {
  Plate? plate;

  @override
  Future<void> deletePlate(String experimentId) async {
    plate = null;
  }

  @override
  Future<Plate?> loadPlate(String experimentId) async => plate;

  @override
  Future<void> savePlate(Plate plate) async {
    this.plate = plate;
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

  testWidgets('confirms experiment deletion and restores it with undo', (
    tester,
  ) async {
    final experiment = Experiment(
      id: 'experiment-1',
      title: 'Delete safety test',
      experimentType: 'CCK-8',
      createdAt: DateTime.utc(2026, 6, 8),
      updatedAt: DateTime.utc(2026, 6, 8),
    );
    final repository = FakeExperimentRepository([experiment]);
    final plateRepository = FakePlateRepository()
      ..plate = Plate(
        id: 'plate-1',
        experimentId: experiment.id,
        name: '96-well Plate',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentsHomeScreen(
          repository: repository,
          plateRepository: plateRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('실험을 삭제할까요?'), findsOneWidget);
    expect(repository.experiments, hasLength(1));
    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-experiment-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.experiments, isEmpty);
    expect(plateRepository.plate, isNull);
    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();

    expect(repository.experiments.single.id, experiment.id);
    expect(plateRepository.plate?.experimentId, experiment.id);
    expect(find.text('Delete safety test'), findsOneWidget);
  });

  testWidgets('exports and merges a full backup with connected plates', (
    tester,
  ) async {
    final original = Experiment(
      id: 'experiment-1',
      title: 'Original experiment',
      experimentType: 'CCK-8',
      createdAt: DateTime.utc(2026, 6, 8),
      updatedAt: DateTime.utc(2026, 6, 8),
    );
    final restored = Experiment(
      id: 'experiment-2',
      title: 'Restored experiment',
      experimentType: 'ELISA',
      createdAt: DateTime.utc(2026, 6, 8),
      updatedAt: DateTime.utc(2026, 6, 8),
    );
    final restoredPlate = Plate(
      id: 'plate-2',
      experimentId: restored.id,
      name: 'Restored Plate',
    );
    final repository = FakeExperimentRepository([original]);
    final plateRepository = FakePlateRepository();
    final backupText = const EasyCheckBackupService().encode(
      experiments: [restored],
      plates: [restoredPlate],
      exportedAt: DateTime.utc(2026, 6, 8, 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExperimentsHomeScreen(
          repository: repository,
          plateRepository: plateRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('전체 데이터 백업 및 복원'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('backup-export-text')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('backup-restore-field')),
      backupText,
    );
    await tester.pumpAndSettle();
    expect(find.text('실험 1 · Plate 1'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('restore-backup-button')),
    );
    await tester.tap(find.byKey(const ValueKey('restore-backup-button')));
    await tester.pumpAndSettle();

    expect(find.text('백업을 복원할까요?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('confirm-restore-backup-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.experiments, hasLength(2));
    expect(find.text('Original experiment'), findsOneWidget);
    expect(find.text('Restored experiment'), findsOneWidget);
    expect(plateRepository.plate?.name, 'Restored Plate');
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
