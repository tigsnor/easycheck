import 'dart:convert';
import 'package:flutter/material.dart';
import '../../experiments/domain/experiment.dart';
import '../application/task_reminder_coordinator.dart';
import '../data/task_reminder_service.dart';
import '../domain/task_reminder.dart';

/// Draft state and OS synchronization are independent; a saved record alone
/// never establishes notification delivery.
class TaskRecordStatus extends StatelessWidget {
  const TaskRecordStatus(
      {super.key,
      required this.task,
      required this.experiment,
      this.coordinator,
      this.saving = false,
      this.failed = false});
  final ExperimentTask task;
  final Experiment experiment;
  final TaskReminderCoordinator? coordinator;
  final bool saving;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final reminders = coordinator;
    return reminders == null
        ? _build(context)
        : ListenableBuilder(
            listenable: reminders, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final stored =
        experiment.tasks.where((item) => item.id == task.id).firstOrNull;
    final dirty = stored == null ||
        jsonEncode(stored.toJson()) != jsonEncode(task.toJson());
    final record = saving
        ? '단계 기록 저장 중…'
        : failed
            ? '단계 기록 저장 실패'
            : dirty
                ? '단계 변경 미저장'
                : '단계 기록 저장됨';
    return Text(
        '$record · ${_reminderLabel(stored)}${dirty && !saving ? '\n알림은 저장된 단계 기록을 기준으로 표시합니다.' : ''}',
        key: ValueKey('task-record-status-${task.id}'),
        style: TextStyle(
            color: failed ? Theme.of(context).colorScheme.error : null));
  }

  String _reminderLabel(ExperimentTask? stored) {
    final reminders = coordinator;
    if (reminders == null) return '알림 상태 확인 불가';
    if (reminders.busy) return '알림 동기화 중…';
    if (reminders.error != null) return '알림 예약·취소 확인 실패';
    if (reminders.permission == null) return '알림 상태 미확인';
    if (stored == null) return '저장된 단계 없음';
    if (experiment.isReadOnly ||
        experiment.status == ExperimentStatus.correcting) {
      return '이 노트 상태에서는 알림을 예약하지 않습니다';
    }
    if (stored.isCompleted) return '완료 단계 · 알림 예약 없음';
    if (!stored.reminderEnabled) return '알림 꺼짐';
    if (stored.dueAt == null) return '시작·예정 시간 저장 후 예약';
    if (reminders.permission == ReminderPermission.denied) return '알림 권한 꺼짐';
    if (reminders.permission == ReminderPermission.unsupported) {
      return '이 기기는 종료 알림 미지원';
    }
    final key = taskReminderKey(experiment.id, stored.id);
    if (!stored.dueAt!.isAfter(DateTime.now())) return '예정 시각 지남 · 수신 여부 확인 불가';
    if (reminders.deferredKeys.contains(key)) return '예약 한도로 대기 중';
    if (reminders.scheduledKeys.contains(key)) return '알림 예약 확인됨 · 수신 보장 아님';
    return '예약 확인 필요 · 알림 동기화';
  }
}
