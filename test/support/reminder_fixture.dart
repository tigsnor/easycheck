import 'package:easycheck/features/reminders/data/task_reminder_service.dart';
import 'package:easycheck/features/reminders/domain/task_reminder.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';

final reminderNow = DateTime.utc(2026, 10, 28, 3);
Experiment timedExperiment(
        {String id = 'e',
        int minutes = 30,
        ExperimentStatus status = ExperimentStatus.inProgress}) =>
    Experiment(
      id: id,
      title: 'Assay',
      createdAt: reminderNow,
      updatedAt: reminderNow,
      status: status,
      tasks: [
        ExperimentTask(
            id: 't',
            title: '반응',
            plannedMinutes: minutes,
            reminderEnabled: true,
            startedAt: reminderNow)
      ],
    );

class FakeReminderService implements TaskReminderService {
  ReminderPermission allowed = ReminderPermission.granted;
  final entries = <int, String?>{};
  final scheduled = <TaskReminder>[];
  final cancelled = <int>[];
  bool failSchedule = false;
  bool failCancel = false;
  int requests = 0;
  Future<void> Function()? gate;
  @override
  Future<ReminderPermission> permission({bool request = false}) async {
    if (request) requests++;
    if (gate != null) await gate!();
    return allowed;
  }

  @override
  Future<Map<int, String?>> pending() async => {...entries};
  @override
  Future<void> schedule(TaskReminder item) async {
    if (failSchedule) throw StateError('OS scheduling failure');
    entries[item.id] = item.payload;
    scheduled.add(item);
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('OS cancellation failure');
    cancelled.add(id);
    entries.remove(id);
  }
}
