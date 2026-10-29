import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/experiments/presentation/experiment_detail_screen.dart';
import 'package:easycheck/features/experiments/presentation/experiments_home_screen.dart';
import 'package:easycheck/features/reminders/data/task_reminder_service.dart';
import 'package:easycheck/features/reminders/domain/task_reminder.dart';
import '../../support/reminder_fixture.dart';
import '../experiments/presentation/experiments_home_screen_test.dart'
    show
        FakeExperimentRepository,
        FakePlateRepository,
        FakePlateTemplateRepository;

class _OpenService extends FakeReminderService
    implements TaskReminderOpenSource {
  void Function(String?)? onOpen;
  String? launch;
  bool failListen = false;
  int stops = 0;
  @override
  Future<void> listenForOpens(void Function(String?) callback) async {
    if (failListen) throw StateError('initialization');
    onOpen = callback;
    if (launch != null) {
      callback(launch);
      callback(launch);
      launch = null;
    }
  }

  @override
  void stopListeningForOpens() {
    onOpen = null;
    stops++;
  }

  void tap(String? payload) => onOpen?.call(payload);
}

class _Repository extends FakeExperimentRepository {
  _Repository(super.experiments);
  bool fail = false;
  int saves = 0;
  Completer<void>? gate;
  @override
  Future<List<Experiment>> loadExperiments() async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('read failed');
    return super.loadExperiments();
  }

  @override
  Future<void> saveExperiment(Experiment e) async {
    saves++;
    await super.saveExperiment(e);
  }
}

void main() {
  late _Repository repo;
  late _OpenService os;
  late Experiment first;
  String payload(Experiment e) => TaskReminder(
          id: 1,
          key: taskReminderKey(e.id, 'target'),
          dueAt: e.tasks.last.dueAt!,
          title: e.title,
          body: '${e.tasks.last.title} 예정 시간이 되었습니다.')
      .payload;
  setUp(() {
    final now = DateTime.now();
    first = Experiment(
        id: 'a',
        title: 'Assay A',
        status: ExperimentStatus.inProgress,
        createdAt: now,
        updatedAt: now,
        notes: 'Saved notes',
        tasks: [
          for (var i = 0; i < 25; i++)
            ExperimentTask(id: 't-$i', title: '준비 $i'),
          ExperimentTask(
              id: 'target',
              title: '마지막 반응',
              startedAt: now.subtract(const Duration(minutes: 1)),
              plannedMinutes: 30,
              reminderEnabled: true),
        ]);
    repo = _Repository([first, first.copyWith(id: 'b', title: 'Assay B')]);
    os = _OpenService();
  });
  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    await tester.pumpWidget(MaterialApp(
        builder: narrow
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!)
            : null,
        home: ExperimentsHomeScreen(
            repository: repo,
            reminderService: os,
            plateRepository: FakePlateRepository(),
            plateTemplateRepository: FakePlateTemplateRepository())));
    if (repo.gate == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, String? value) async {
    os.tap(value);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'cold launch waits for initial load, collapses duplicates and focuses final step without writes',
      (tester) async {
    os.launch = payload(first);
    repo.gate = Completer<void>();
    await open(tester);
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ExperimentDetailScreen, skipOffstage: false),
        findsOneWidget);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1);
    expect(find.byKey(const ValueKey('reminder-target-task-target')),
        findsOneWidget);
    expect(find.text('마지막 반응'), findsOneWidget);
    expect(repo.saves, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    expect(repo.experiments.first.toJson(), first.toJson());
  });

  testWidgets(
      'warm tap reads current data instead of home cache and marks changed deadline',
      (tester) async {
    await open(tester);
    repo.experiments[0] = first.copyWith(title: 'Current title', tasks: [
      ...first.tasks.take(25),
      first.tasks.last.copyWith(plannedMinutes: 60)
    ]);
    await emit(tester, payload(first));
    final detail = tester
        .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen));
    expect(detail.experiment.title, 'Current title');
    expect(detail.experiment.tasks.last.plannedMinutes, 60);
    expect(find.textContaining('알림 이후 단계나 예정 시간이 변경'), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets(
      'an open editor keeps unsaved text; notification waits for normal exit guard',
      (tester) async {
    await open(tester);
    await tap(tester, find.text('Assay B'));
    final field = find.widgetWithText(TextField, '실행·관찰 메모');
    await tap(tester, field);
    await tester.enterText(field, 'Keep my draft');
    tester.testTextInput.hide();
    await emit(tester, payload(first));
    expect(find.byType(ExperimentDetailScreen, skipOffstage: false),
        findsOneWidget);
    expect(find.text('Keep my draft'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('저장하지 않은 변경이 있습니다'), findsOneWidget);
    await tap(tester, find.text('계속 편집'));
    expect(find.text('Keep my draft'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, find.text('저장 후 나가기'));
    expect(repo.experiments.last.notes, 'Keep my draft');
    expect(find.byType(ExperimentDetailScreen, skipOffstage: false),
        findsOneWidget);
    expect(
        tester
            .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen))
            .experiment
            .id,
        'a');
  });

  testWidgets(
      'repeated active taps do not push routes; different targets wait in order',
      (tester) async {
    await open(tester);
    await emit(tester, payload(first));
    await emit(tester, payload(first));
    await emit(tester, payload(repo.experiments.last));
    await emit(tester, payload(repo.experiments.last));
    expect(find.byType(ExperimentDetailScreen, skipOffstage: false),
        findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen))
            .experiment
            .id,
        'b');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    expect(repo.saves, 0);
  });

  testWidgets(
      'deleted experiment and malformed payload stay on home with a clear notice',
      (tester) async {
    await open(tester);
    repo.experiments.removeAt(0);
    await emit(tester, payload(first));
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    expect(find.textContaining('실험이 삭제되었거나'), findsOneWidget);
    await emit(tester, 'not-a-task');
    expect(find.textContaining('알림의 실험·단계 정보를 확인할 수 없습니다'), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets(
      'missing step does not create default tasks or select another step as the target',
      (tester) async {
    await open(tester);
    repo.experiments[0] = first.copyWith(tasks: []);
    await emit(tester, payload(first));
    expect(find.textContaining('알림의 단계가 현재 노트에 없습니다'), findsOneWidget);
    expect(find.text('등록된 단계가 없습니다.'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-target-task-target')),
        findsNothing);
    expect(repo.saves, 0);
  });

  testWidgets(
      'completed task is highlighted without restarting or completing anything',
      (tester) async {
    await open(tester);
    repo.experiments[0] = first.copyWith(tasks: [
      first.tasks.last.copyWith(isCompleted: true, completedAt: DateTime.now())
    ]);
    await emit(tester, payload(first));
    expect(find.textContaining('이미 완료된 단계의 알림'), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-target-task-target')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('focused-task-target')), findsNothing);
    expect(repo.saves, 0);
  });

  testWidgets(
      'completed and archived notes remain locked when opened from old notification',
      (tester) async {
    for (final status in [
      ExperimentStatus.completed,
      ExperimentStatus.archived
    ]) {
      repo.experiments[0] = first.copyWith(status: status);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await emit(tester, payload(first));
      await tap(
          tester, find.byKey(const ValueKey('experiment-section-execution')));
      expect(find.textContaining('읽기 전용으로 표시합니다'), findsOneWidget);
      final button = find.byKey(const ValueKey('focused-task-target'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    }
    expect(repo.saves, 0);
  });

  testWidgets(
      'read failure keeps target for explicit retry against latest records',
      (tester) async {
    await open(tester);
    repo.fail = true;
    await emit(tester, payload(first));
    expect(find.textContaining('알림 대상 기록을 읽지 못했습니다'), findsOneWidget);
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    repo.fail = false;
    repo.experiments[0] = first.copyWith(title: 'Recovered');
    await tap(tester, find.byKey(const ValueKey('retry-reminder-target')));
    expect(
        tester
            .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen))
            .experiment
            .title,
        'Recovered');
    expect(repo.saves, 0);
  });

  testWidgets(
      'listener initialization retries cold launch; disposal detaches callbacks',
      (tester) async {
    os.failListen = true;
    os.launch = payload(first);
    await open(tester);
    expect(find.text('알림 이동을 준비하지 못했습니다.'), findsOneWidget);
    os.failListen = false;
    await tap(tester, find.byKey(const ValueKey('retry-reminder-listener')));
    expect(find.byType(ExperimentDetailScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    os.tap(payload(first));
    await tester.pump();
    expect(os.stops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'backup sheet keeps navigation pending and target uses records after it closes',
      (tester) async {
    await open(tester);
    await tap(tester, find.byTooltip('전체 데이터 백업 및 복원'));
    await emit(tester, payload(first));
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    repo.experiments[0] = first.copyWith(title: 'Restored title');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen))
            .experiment
            .title,
        'Restored title');
    expect(repo.saves, 0);
  });

  testWidgets(
      'opening an editor while target read is in flight postpones notification instead of stacking editors',
      (tester) async {
    await open(tester);
    repo.gate = Completer<void>();
    await emit(tester, payload(first));
    await tap(tester, find.text('Assay B'));
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ExperimentDetailScreen, skipOffstage: false),
        findsOneWidget);
    expect(
        tester
            .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen))
            .experiment
            .id,
        'b');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ExperimentDetailScreen>(find.byType(ExperimentDetailScreen))
            .experiment
            .id,
        'a');
    expect(repo.saves, 0);
  });

  testWidgets('background delivery waits for resume', (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await emit(tester, payload(first));
    expect(find.byType(ExperimentDetailScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(ExperimentDetailScreen), findsOneWidget);
  });

  testWidgets(
      'narrow large text exposes the target and actions without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    os.launch = payload(first);
    await open(tester, narrow: true);
    await tap(tester, find.byKey(const ValueKey('focused-task-time-target')));
    expect(find.byKey(const ValueKey('task-planned-minutes')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(repo.saves, 0);
  });
}
