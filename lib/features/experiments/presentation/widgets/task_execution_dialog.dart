import 'package:flutter/material.dart';
import '../../domain/experiment.dart';

class TaskExecutionDialog extends StatefulWidget {
  const TaskExecutionDialog(
      {super.key, required this.task, required this.action});
  final ExperimentTask task;
  final TaskExecutionAction action;
  @override
  State<TaskExecutionDialog> createState() => _TaskExecutionDialogState();
}

class _TaskExecutionDialogState extends State<TaskExecutionDialog> {
  final _reason = TextEditingController();
  final _focus = FocusNode();
  final _field = GlobalKey();
  bool _leaving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    if (_leaving) return;
    _leaving = true;
    if (_reason.text.trim().isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('입력한 사유를 버릴까요?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속 입력')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('버리기')),
          ],
        ),
      );
      if (!mounted) return;
      if (discard != true) {
        _leaving = false;
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  void _apply() {
    if (_leaving) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = '사유를 입력해주세요.');
      _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _field.currentContext != null) {
          Scrollable.ensureVisible(_field.currentContext!, alignment: 1);
        }
      });
      return;
    }
    _leaving = true;
    Navigator.pop(context, _reason.text.trim());
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _cancel();
        },
        child: AlertDialog(
          scrollable: true,
          title: Text('${widget.action.label}하고 저장'),
          content:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.task.title),
            const SizedBox(height: 12),
            Text(widget.action == TaskExecutionAction.cancelStart
                ? '시작 전 상태로 돌아갑니다. 이전 시작 기록과 사유는 이력에 남고, 저장 후 이 단계의 알림 예약을 취소합니다.'
                : '지금 시각으로 새로 시작합니다. 이전 시작·완료 기록과 사유는 이력에 남고, 저장 후 새 시작 시각을 기준으로 알림 예약을 갱신합니다.'),
            const SizedBox(height: 12),
            const Text(
                '다른 단계·메모는 유지하고 실험 전체 상태를 시작 전으로 되돌리지 않습니다. 알림 예약·취소 결과는 저장 후 단계에서 확인하세요.'),
            const SizedBox(height: 12),
            TextField(
                key: _field,
                controller: _reason,
                focusNode: _focus,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: '변경 사유',
                    errorText: _error,
                    hintText: '예: 실수로 시작을 눌렀음'),
                onSubmitted: (_) => _apply()),
          ]),
          actions: [
            TextButton(onPressed: _cancel, child: const Text('취소')),
            FilledButton(
                key: const ValueKey('confirm-task-reset'),
                onPressed: _apply,
                child: Text('${widget.action.label}하고 저장')),
          ],
        ),
      );
}

class TaskExecutionHistoryScreen extends StatelessWidget {
  const TaskExecutionHistoryScreen(
      {super.key, required this.task, required this.recordStatus});
  final ExperimentTask task;
  final Widget recordStatus;
  String _time(DateTime? value) => value == null
      ? '미기록'
      : value
          .toLocal()
          .toIso8601String()
          .split('.')
          .first
          .replaceFirst('T', ' ');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('단계 실행 이력')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(task.title, style: Theme.of(context).textTheme.titleLarge),
          recordStatus,
          const Text(
              '시각은 기기 현지 시간입니다. 변경 전 기록을 보존하며 과거 실행을 현재 실행으로 복원하지 않습니다.'),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      '현재 상태: ${task.isCompleted ? '완료' : task.startedAt == null ? '시작 전' : '진행 중'}\n시작: ${_time(task.startedAt)}\n완료: ${_time(task.completedAt)}'))),
          for (final record in task.executionHistory.reversed)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.action.label,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            '변경 시각: ${_time(record.recordedAt)}\n사유: ${record.reason}\n변경 전 단계: ${record.title}\n변경 전 상태: ${record.wasCompleted ? '완료' : record.startedAt == null ? '시작 전' : '진행 중'}\n시작: ${_time(record.startedAt)}\n완료: ${_time(record.completedAt)}\n예정 시간: ${record.plannedMinutes == null ? '없음' : '${record.plannedMinutes}분'}\n알림 설정: ${record.reminderEnabled ? '켜짐' : '꺼짐'}'),
                      ],
                    ))),
        ]),
      );
}
