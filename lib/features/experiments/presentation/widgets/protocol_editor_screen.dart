import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/experiment.dart';
import '../../domain/protocol_editing.dart';

class ProtocolEditorScreen extends StatefulWidget {
  const ProtocolEditorScreen({required this.experiment, super.key});
  final Experiment experiment;
  @override
  State<ProtocolEditorScreen> createState() => _ProtocolEditorScreenState();
}

class _ProtocolEditorScreenState extends State<ProtocolEditorScreen> {
  late final List<ExperimentTask> _tasks = [...widget.experiment.tasks];
  final _titles = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  final _keys = <String, GlobalKey>{};
  final _scroll = ScrollController();
  String? _invalidId, _error;
  bool _allowPop = false, _closing = false;
  int _added = 0;
  late final String _initial;
  String get _fingerprint => jsonEncode([
        for (final task in _tasks) [task.id, _titles[task.id]!.text]
      ]);

  @override
  void initState() {
    super.initState();
    for (final task in _tasks) {
      _register(task);
    }
    _initial = _fingerprint;
  }

  void _register(ExperimentTask task) {
    _titles[task.id] = TextEditingController(text: task.title);
    _focus[task.id] = FocusNode();
    _keys[task.id] = GlobalKey();
  }

  @override
  void dispose() {
    for (final c in _titles.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pop([List<ExperimentTask>? tasks]) async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, tasks);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (_fingerprint != _initial) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('단계 구성 변경을 버릴까요?'),
                content: const Text('아직 실험 노트에 적용하지 않았습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 편집')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('변경 버리고 닫기'))
                ],
              ));
      if (!mounted) return;
      if (discard != true) {
        _closing = false;
        return;
      }
    }
    await _pop();
  }

  void _reveal(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _keys[id]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context,
            alignment: .1, duration: const Duration(milliseconds: 200));
      }
    });
  }

  void _move(int index, int offset) {
    FocusManager.instance.primaryFocus?.unfocus();
    final task = _tasks[index];
    setState(() {
      _tasks.removeAt(index);
      _tasks.insert(index + offset, task);
    });
    _reveal(task.id);
  }

  Future<void> _delete(ExperimentTask task) async {
    if (_tasks.length <= 1) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('실행 전 단계를 삭제할까요?'),
              content: Text(_titles[task.id]!.text.trim().isEmpty
                  ? '이름 미입력 단계'
                  : _titles[task.id]!.text),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소')),
                FilledButton(
                    key: const ValueKey('confirm-protocol-delete'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('삭제'))
              ],
            ));
    if (remove != true || !mounted) return;
    // Keep controllers alive until route disposal; a focused TextField can still
    // be mounted during this frame. Deleted tasks never enter the applied draft.
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
      if (_invalidId == task.id) _invalidId = null;
    });
  }

  void _add() {
    final task = ExperimentTask(
        id: 'custom-${DateTime.now().microsecondsSinceEpoch}-${_added++}',
        title: '');
    setState(() {
      _tasks.add(task);
      _register(task);
    });
    _focus[task.id]!.requestFocus();
    _reveal(task.id);
  }

  Future<void> _apply() async {
    if (_closing) return;
    final invalid =
        _tasks.where((t) => _titles[t.id]!.text.trim().isEmpty).firstOrNull;
    setState(() {
      _invalidId = invalid?.id;
      _error = null;
    });
    if (invalid != null) {
      _focus[invalid.id]!.requestFocus();
      _reveal(invalid.id);
      return;
    }
    try {
      final draft = ProtocolEditing.validate(widget.experiment, [
        for (final t in _tasks)
          t.copyWith(
              title: _titles[t.id]!.text == t.title
                  ? t.title
                  : _titles[t.id]!.text.trim())
      ]);
      _closing = true;
      await _pop(jsonEncode(draft.map((t) => t.toJson()).toList()) ==
              jsonEncode(
                  widget.experiment.tasks.map((t) => t.toJson()).toList())
          ? null
          : draft);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = ProtocolEditing.canEdit(widget.experiment);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
            leading: IconButton(
                key: const ValueKey('close-protocol-editor'),
                tooltip: '닫기',
                onPressed: _close,
                icon: const Icon(Icons.close)),
            title: const Text('단계 구성 편집'),
            actions: [
              TextButton(
                  key: const ValueKey('apply-protocol-draft'),
                  onPressed: editable ? _apply : null,
                  child: const Text('노트에 적용'))
            ]),
        body: SafeArea(
            child: !editable
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('수행 기록이 없는 초안·계획 실험에서만 편집할 수 있습니다.'))
                : SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                              '실행 전 단계의 이름·순서를 바꾸거나 추가·삭제합니다. 기존 단계의 예정 시간·알림 설정은 유지합니다. 적용 후 실험 노트에서 저장해주세요.'),
                          const Text(
                              '단계는 최소 1개 유지합니다. 수행 기록이 생기면 이 구성 편집은 잠깁니다.'),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          for (var i = 0; i < _tasks.length; i++)
                            Card(
                                key: ValueKey('protocol-row-${_tasks[i].id}'),
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text('${i + 1}번 단계'),
                                        Container(
                                            key: _keys[_tasks[i].id],
                                            child: TextField(
                                                key: ValueKey(
                                                    'protocol-title-${_tasks[i].id}'),
                                                controller:
                                                    _titles[_tasks[i].id],
                                                focusNode: _focus[_tasks[i].id],
                                                minLines: 1,
                                                maxLines: 3,
                                                decoration: InputDecoration(
                                                    labelText: '단계 이름',
                                                    errorText: _invalidId ==
                                                            _tasks[i].id
                                                        ? '단계 이름을 입력해주세요.'
                                                        : null,
                                                    errorMaxLines: 2))),
                                        Text(
                                            '예정 시간 ${_tasks[i].plannedMinutes == null ? '미지정' : '${_tasks[i].plannedMinutes}분'} · 알림 ${_tasks[i].reminderEnabled ? '켜짐' : '꺼짐'}'),
                                        Wrap(spacing: 8, children: [
                                          IconButton(
                                              key: ValueKey(
                                                  'protocol-up-${_tasks[i].id}'),
                                              tooltip: '위로 이동',
                                              onPressed: i == 0
                                                  ? null
                                                  : () => _move(i, -1),
                                              icon: const Icon(
                                                  Icons.arrow_upward)),
                                          IconButton(
                                              key: ValueKey(
                                                  'protocol-down-${_tasks[i].id}'),
                                              tooltip: '아래로 이동',
                                              onPressed: i == _tasks.length - 1
                                                  ? null
                                                  : () => _move(i, 1),
                                              icon: const Icon(
                                                  Icons.arrow_downward)),
                                          TextButton.icon(
                                              key: ValueKey(
                                                  'protocol-delete-${_tasks[i].id}'),
                                              onPressed: _tasks.length == 1
                                                  ? null
                                                  : () => _delete(_tasks[i]),
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              label: const Text('삭제')),
                                        ]),
                                      ],
                                    ))),
                          OutlinedButton.icon(
                              key: const ValueKey('protocol-add-task'),
                              onPressed: _add,
                              icon: const Icon(Icons.add),
                              label: const Text('단계 추가')),
                        ]))),
      ),
    );
  }
}
