import 'package:flutter/material.dart';
import '../../domain/experiment.dart';

String actualTimeInput(DateTime? value) {
  if (value == null) return '';
  final date = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

/// Strict local input; unchanged fields preserve their original subsecond value.
DateTime? parseActualTime(String text, DateTime? original) {
  if (text.trim().isEmpty) return null;
  if (text.trim() == actualTimeInput(original)) return original;
  final match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})(?::(\d{2}))?$')
          .firstMatch(text.trim());
  if (match == null) {
    throw const FormatException('날짜와 시간을 YYYY-MM-DD HH:mm 형식으로 입력해주세요.');
  }
  final v = [for (var i = 1; i <= 6; i++) int.parse(match.group(i) ?? '0')];
  final date = DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  if (date.year != v[0] ||
      date.month != v[1] ||
      date.day != v[2] ||
      date.hour != v[3] ||
      date.minute != v[4] ||
      date.second != v[5]) {
    throw const FormatException('존재하는 날짜와 시간을 입력해주세요.');
  }
  return date;
}

class TaskActualTimesDialog extends StatefulWidget {
  const TaskActualTimesDialog({super.key, required this.task});
  final ExperimentTask task;
  @override
  State<TaskActualTimesDialog> createState() => _TaskActualTimesDialogState();
}

class _TaskActualTimesDialogState extends State<TaskActualTimesDialog> {
  late final TextEditingController _start;
  late final TextEditingController _completion;
  final _reason = TextEditingController();
  final _errorKey = GlobalKey();
  bool _leaving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _start =
        TextEditingController(text: actualTimeInput(widget.task.startedAt));
    _completion =
        TextEditingController(text: actualTimeInput(widget.task.completedAt));
  }

  @override
  void dispose() {
    _start.dispose();
    _completion.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _start.text != actualTimeInput(widget.task.startedAt) ||
      _completion.text != actualTimeInput(widget.task.completedAt) ||
      _reason.text.trim().isNotEmpty;

  Future<void> _cancel() async {
    if (_leaving) return;
    _leaving = true;
    if (_dirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: const Text('입력한 시각과 사유를 버릴까요?'), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('계속 입력')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('버리기')),
              ]));
      if (!mounted) return;
      if (discard != true) {
        _leaving = false;
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pick(
      TextEditingController controller, DateTime? original) async {
    DateTime? current;
    try {
      current = parseActualTime(controller.text, original);
    } on FormatException {/* Pick a valid date instead. */}
    final now = DateTime.now();
    final seed =
        current != null && !current.isAfter(now) && current.year >= 1970
            ? current
            : now;
    final date = await showDatePicker(
        context: context,
        initialDate: seed,
        firstDate: DateTime(1970),
        lastDate: now);
    if (!mounted || date == null) return;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(seed),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (!mounted || time == null) return;
    setState(() => controller.text = actualTimeInput(
        DateTime(date.year, date.month, date.day, time.hour, time.minute)));
  }

  void _apply() {
    if (_leaving) return;
    try {
      final updated = widget.task.recordActualTimes(
          start: parseActualTime(_start.text, widget.task.startedAt),
          completion:
              parseActualTime(_completion.text, widget.task.completedAt),
          reason: _reason.text,
          now: DateTime.now());
      _leaving = true;
      Navigator.pop(context, identical(updated, widget.task) ? null : updated);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _errorKey.currentContext != null) {
          Scrollable.ensureVisible(_errorKey.currentContext!, alignment: 1);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        scrollable: true,
        title: const Text('실제 시각 사후 입력'),
        content:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.task.title),
          const Text(
              '기기 현지 시간으로 입력하세요. 실제 실행 시각과 지금 기록한 시각·사유를 구분해 보존합니다. 완료 시각을 입력하면 단계가 완료됩니다. 모르는 시각은 비워 두세요.'),
          TextField(
              key: const ValueKey('task-actual-start'),
              controller: _start,
              decoration: InputDecoration(
                  labelText: '실제 시작 시각',
                  hintText: 'YYYY-MM-DD HH:mm',
                  suffixIcon: IconButton(
                      key: const ValueKey('pick-task-start'),
                      tooltip: '시작 날짜·시간 선택',
                      onPressed: () => _pick(_start, widget.task.startedAt),
                      icon: const Icon(Icons.calendar_month)))),
          TextField(
              key: const ValueKey('task-actual-completion'),
              controller: _completion,
              decoration: InputDecoration(
                  labelText: '실제 완료 시각',
                  hintText: 'YYYY-MM-DD HH:mm',
                  suffixIcon: IconButton(
                      key: const ValueKey('pick-task-completion'),
                      tooltip: '완료 날짜·시간 선택',
                      onPressed: () =>
                          _pick(_completion, widget.task.completedAt),
                      icon: const Icon(Icons.calendar_month)))),
          TextField(
              key: const ValueKey('task-actual-reason'),
              controller: _reason,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: '사후 입력·수정 사유',
                  hintText: '예: 작업 중 기록을 놓쳐 실험 메모로 확인')),
          if (_error != null)
            Padding(
                key: _errorKey,
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    key: const ValueKey('task-actual-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          const Text(
              '기존 시각 삭제는 시작 취소·완료 해제를 사용하세요. 저장 후 알림을 새 예정 시각에 맞추며, 이미 지난 예정 시각은 다시 알리지 않습니다.'),
        ]),
        actions: [
          TextButton(onPressed: _cancel, child: const Text('취소')),
          FilledButton(
              key: const ValueKey('save-task-actual-times'),
              onPressed: _apply,
              child: const Text('기록하고 저장'))
        ],
      ));
}
