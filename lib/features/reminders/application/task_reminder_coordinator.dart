import 'package:flutter/foundation.dart';
import '../../experiments/domain/experiment.dart';
import '../data/task_reminder_service.dart';
import '../domain/task_reminder.dart';

/// Reconciles only persisted records. Serial execution prevents an older refresh
/// from re-registering a reminder after a completion/delete/restore.
class TaskReminderCoordinator extends ChangeNotifier {
  TaskReminderCoordinator(
      {required this.loadExperiments,
      required this.service,
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final Future<List<Experiment>> Function() loadExperiments;
  final TaskReminderService service;
  final DateTime Function() _now;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  bool busy = false;
  Object? error;
  ReminderPermission? permission;
  Set<String> scheduledKeys = {};
  int deferredCount = 0;

  Future<void> refresh({bool requestPermission = false}) {
    _queue = _queue.then((_) => _refresh(requestPermission));
    return _queue;
  }

  Future<void> _refresh(bool request) async {
    if (_disposed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      // Never cancel valid OS reminders merely because the data file is unreadable.
      final experiments = await loadExperiments();
      final all = buildTaskReminders(experiments, _now(), includePast: true);
      permission = await service.permission(request: request);
      final pending = await service.pending();
      // Keep an existing inexact notification while Android is delaying delivery.
      // An overdue record restored to a new device never creates a new alert.
      final desired = all
          .where((item) =>
              item.dueAt.isAfter(_now()) || pending[item.id] == item.payload)
          .toList();
      final foreign = pending.entries
          .where((e) => !(e.value?.startsWith(taskReminderPrefix) ?? false))
          .map((e) => e.key)
          .toSet();
      final limit = (60 - foreign.length).clamp(0, 60);
      final selected = permission == ReminderPermission.granted
          ? desired.take(limit).toList()
          : <TaskReminder>[];
      deferredCount = permission == ReminderPermission.granted
          ? desired.length - selected.length
          : 0;
      final wanted = {for (final item in selected) item.id: item};
      scheduledKeys = {};
      for (final entry in pending.entries) {
        if (!(entry.value?.startsWith(taskReminderPrefix) ?? false)) continue;
        if (wanted[entry.key]?.payload != entry.value) {
          await service.cancel(entry.key);
        }
      }
      for (final item in selected) {
        if (foreign.contains(item.id)) {
          throw StateError('다른 알림과 ID가 겹칩니다. 예약 상태를 확인해주세요.');
        }
        // Do not re-fire past deadlines on resume/restore, even if time elapsed during permission prompts.
        if (!item.dueAt.isAfter(_now()) && pending[item.id] != item.payload) {
          await service.cancel(item.id);
          continue;
        }
        if (pending[item.id] != item.payload) await service.schedule(item);
        scheduledKeys.add(item.key);
      }
    } on Object catch (cause) {
      error = cause;
      scheduledKeys = {};
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
