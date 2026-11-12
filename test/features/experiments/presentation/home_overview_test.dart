import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/domain/experiment_home_overview.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/reminder_fixture.dart';
import 'experiments_home_screen_test.dart'
    show
        FakeExperimentRepository,
        FakePlateRepository,
        FakePlateTemplateRepository;

void main() {
  final now = DateTime.utc(2026, 11, 10, 12);
  Experiment experiment(String id,
          {String? project,
          ExperimentStatus status = ExperimentStatus.inProgress,
          List<ExperimentTask> tasks = const []}) =>
      Experiment(
          id: id,
          title: 'Assay $id',
          createdAt: now,
          updatedAt: now,
          projectName: project,
          status: status,
          tasks: tasks);
  ExperimentTask task(String id, Duration until) => ExperimentTask(
      id: id,
      title: 'Step $id',
      plannedMinutes: 60,
      startedAt: now.add(until).subtract(const Duration(minutes: 60)));
  Finder key(String key) => find.byKey(ValueKey(key));
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, FakeExperimentRepository repo,
      {DateTime Function()? clock}) async {
    await tester.pumpWidget(MaterialApp(
        home: ExperimentsHomeScreen(
            repository: repo,
            plateRepository: FakePlateRepository(),
            plateTemplateRepository: FakePlateTemplateRepository(),
            reminderService: FakeReminderService(),
            now: clock ?? () => now)));
    await tester.pumpAndSettle();
  }

  test('search, status and exact project compose without changing records', () {
    final entries = [
      experiment('One', project: 'Alpha'),
      experiment('Two', project: 'Alpha', status: ExperimentStatus.completed),
      experiment('Three', project: 'Beta'),
      experiment('Four')
    ];
    final saved = entries.map((e) => e.toJson()).toList();
    expect(
        ExperimentHomeOverview.filter(entries,
                query: 'assay',
                status: ExperimentStatus.inProgress,
                project: 'Alpha')
            .map((e) => e.id),
        ['One']);
    expect(
        ExperimentHomeOverview.filter(entries, project: '').single.id, 'Four');
    expect(
        ExperimentHomeOverview.filter(entries,
            query: 'three', project: 'Alpha'),
        isEmpty);
    expect(entries.map((e) => e.toJson()), saved);
  });

  test(
      'urgency uses recorded deadlines and excludes finished or historical tasks',
      () {
    final tasks = [
      task('later', const Duration(minutes: 30, seconds: 1)),
      task('boundary', const Duration(minutes: 30)),
      task('past', const Duration(minutes: -5)),
      task('done', const Duration(minutes: -10))
          .copyWith(isCompleted: true, completedAt: now),
      const ExperimentTask(
          id: 'unstarted', title: 'Unstarted', plannedMinutes: 10),
      ExperimentTask(
          id: 'skipped',
          title: 'Skipped',
          plannedMinutes: 10,
          executionMetadata:
              TaskExecutionMetadata(skippedAt: now, skipReason: 'skip'))
    ];
    final entries = [
      experiment('active', tasks: tasks),
      for (final state in [
        ExperimentStatus.completed,
        ExperimentStatus.archived,
        ExperimentStatus.correcting
      ])
        experiment(state.name,
            status: state, tasks: [task('historical', Duration.zero)])
    ];
    expect(
        ExperimentHomeOverview.urgentTasks(entries, now)
            .map((item) => item.task.id),
        ['past', 'boundary']);
  });

  testWidgets(
      'status/project/search compose, reset and stale project reload remain usable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeExperimentRepository([
      experiment('One', project: 'Alpha'),
      experiment('Two', project: 'Alpha', status: ExperimentStatus.completed),
      experiment('Three', project: 'Beta'),
      experiment('Four')
    ]);
    await open(tester, repo);
    await tap(tester, key('home-status-all'));
    await tap(tester, find.text('진행 중').last);
    await tap(tester, key('home-project-all'));
    await tap(tester, find.text('Alpha').last);
    expect(find.text('Assay One'), findsOneWidget);
    expect(find.text('Assay Two'), findsNothing);
    expect(find.text('Assay Three'), findsNothing);
    await tester.enterText(find.byType(SearchBar), 'Three');
    await tester.pumpAndSettle();
    expect(find.text('검색·필터에 맞는 실험이 없습니다.'), findsOneWidget);
    expect(find.text('첫 실험 만들기'), findsNothing);
    await tap(tester, key('reset-home-filters'));
    expect(find.text('Assay One'), findsOneWidget);
    await tap(tester, key('home-project-all'));
    await tap(tester, find.text('프로젝트 미지정').last);
    expect(find.text('Assay Four'), findsOneWidget);
    expect(find.text('Assay One'), findsNothing);
    repo.experiments.removeWhere((e) => e.projectName == null);
    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pumpAndSettle();
    await refresh;
    expect(key('home-project-all'), findsOneWidget);
    expect(find.text('Assay One'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'deadline updates with time/resume and opens the chosen task without writing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var clock = now;
    final record = experiment('active',
        tasks: [task('target', const Duration(minutes: 31))]);
    final repo = FakeExperimentRepository([record]);
    await open(tester, repo, clock: () => clock);
    expect(key('home-deadline-active-target'), findsNothing);
    clock = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Step target · 29분 후 예정 종료'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = now.add(const Duration(minutes: 32));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Step target · 1분 초과'), findsOneWidget);
    await tap(tester, key('home-deadline-active-target'));
    final screen = tester
        .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen));
    expect(screen.initialTaskId, 'target');
    expect(screen.reminderTarget, isNull);
    expect(find.text('홈에서 선택한 단계'), findsOneWidget);
    expect(key('reminder-open-context'), findsNothing);
    expect(repo.experiments.single.toJson(), record.toJson());
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '320px large text filters and long overdue task remain accessible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: ExperimentsHomeScreen(
            repository: FakeExperimentRepository([
              experiment('long project and experiment title',
                  project: 'A very long project name',
                  tasks: [
                    task('long overdue experimental step title',
                        const Duration(minutes: -5))
                  ])
            ]),
            plateRepository: FakePlateRepository(),
            plateTemplateRepository: FakePlateTemplateRepository(),
            reminderService: FakeReminderService(),
            now: () => now)));
    await tester.pumpAndSettle();
    await tap(tester, key('home-status-all'));
    await tap(tester, find.text('진행 중').last);
    await tap(tester, key('home-project-all'));
    await tap(tester, find.text('A very long project name').last);
    final deadline = key(
        'home-deadline-long project and experiment title-long overdue experimental step title');
    await tester.scrollUntilVisible(deadline, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
