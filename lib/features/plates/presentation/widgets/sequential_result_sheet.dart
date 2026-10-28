import 'package:flutter/material.dart';

import '../../../../shared/models/well_position.dart';
import '../../domain/plate.dart';
import '../../domain/well.dart';

/// Saves one result at a time; persistence must succeed before advancing.
class SequentialResultSheet extends StatefulWidget {
  const SequentialResultSheet({
    required this.plate,
    required this.start,
    required this.onSave,
    required this.onPositionChanged,
    super.key,
  });

  final Plate plate;
  final WellPosition start;
  final Future<bool> Function(Well) onSave;
  final ValueChanged<WellPosition> onPositionChanged;

  @override
  State<SequentialResultSheet> createState() => _SequentialResultSheetState();
}

class _SequentialResultSheetState extends State<SequentialResultSheet> {
  final _value = TextEditingController();
  final _unit = TextEditingController();
  final _focus = FocusNode();
  final Map<WellPosition, Well> _savedWells = {};
  late Well _well;
  late String _initialValue;
  late String _initialUnit;
  bool _byColumn = false;
  bool _saving = false;
  bool _failed = false;
  bool _allowPop = false;
  bool _confirming = false;
  String? _error;
  String? _savedLabel;

  bool get _dirty =>
      _failed || _value.text != _initialValue || _unit.text != _initialUnit;

  WellPosition? get _next {
    final rows = widget.plate.rowCount;
    final columns = widget.plate.columnCount;
    final p = _well.position;
    final index = _byColumn
        ? p.columnIndex * rows + p.rowIndex
        : p.rowIndex * columns + p.columnIndex;
    if (index + 1 == rows * columns) return null;
    return _byColumn
        ? WellPosition(
            rowIndex: (index + 1) % rows, columnIndex: (index + 1) ~/ rows)
        : WellPosition(
            rowIndex: (index + 1) ~/ columns,
            columnIndex: (index + 1) % columns);
  }

  @override
  void initState() {
    super.initState();
    _load(widget.start);
    _value.addListener(_changed);
    _unit.addListener(_changed);
  }

  void _changed() => setState(() {});

  void _load(WellPosition position, {String fallbackUnit = 'OD450'}) {
    _well = _savedWells[position] ?? widget.plate.wellAt(position);
    _initialValue = _well.resultValue?.toString() ?? '';
    // An existing measurement with no unit must remain visibly unitless.
    _initialUnit =
        _well.resultUnit ?? (_well.resultValue == null ? fallbackUnit : '');
    _value.text = _initialValue;
    _unit.text = _initialUnit;
    _error = null;
    _failed = false;
  }

  @override
  void dispose() {
    _value.dispose();
    _unit.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_saving || _confirming) return;
    if (_dirty) {
      _confirming = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('현재 well의 입력을 버릴까요?'),
          content: const Text('현재 입력은 저장되지 않았습니다. 앞서 저장한 well은 유지됩니다.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속 입력')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('입력 버리고 닫기')),
          ],
        ),
      );
      _confirming = false;
      if (discard != true || !mounted) return;
    }
    await _pop();
  }

  Future<void> _pop() async {
    setState(() => _allowPop = true);
    // Update PopScope before popping; it must still block back while saving.
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save({required bool advance}) async {
    if (_saving) return;
    final value = double.tryParse(_value.text.trim());
    if (value == null || !value.isFinite) {
      setState(() => _error = '유한한 숫자를 입력해주세요. 0도 결과값으로 저장됩니다.');
      return;
    }
    final unit = _unit.text.trim();
    final updated = _well.copyWith(
        resultValue: value, resultUnit: unit.isEmpty ? null : unit);
    final next = _next;
    setState(() {
      _saving = true;
      _error = null;
      _failed = false;
    });
    bool saved;
    try {
      saved = await widget.onSave(updated);
    } on Object {
      saved = false;
    }
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }
    _saving = false;
    _savedWells[updated.position] = updated;
    if (!advance || next == null) {
      await _pop();
      return;
    }
    setState(() {
      _savedLabel = updated.label;
      _load(next, fallbackUnit: unit);
    });
    widget.onPositionChanged(next);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    return PopScope(
      canPop: _allowPop || (!_saving && !_dirty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Semantics(
                        liveRegion: true,
                        child: Text(
                          '${_well.label} · 결과 연속 입력',
                          key: const ValueKey('sequential-coordinate'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ))),
                IconButton(
                    key: const ValueKey('close-sequential-results'),
                    tooltip: '연속 입력 닫기',
                    onPressed: _saving ? null : _close,
                    icon: const Icon(Icons.close)),
              ]),
              const Text(
                  '현재 well부터 Plate 끝까지 순서대로 입력합니다. 빈 well과 분석 제외 well도 포함됩니다.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                key: const ValueKey('sequential-direction'),
                initialValue: _byColumn,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '이동 방향'),
                items: const [
                  DropdownMenuItem(value: false, child: Text('행 방향 · A1 → A2')),
                  DropdownMenuItem(value: true, child: Text('열 방향 · A1 → B1')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _byColumn = value!),
              ),
              const SizedBox(height: 12),
              Text(
                  next == null
                      ? '마지막 well입니다. 저장하면 입력을 마칩니다.'
                      : '저장 후 ${next.label}로 이동',
                  key: const ValueKey('sequential-next')),
              if (_savedLabel != null)
                Semantics(liveRegion: true, child: Text('$_savedLabel 저장 완료')),
              if (_well.resultValue != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '기존 결과: ${_well.resultValue} ${_well.resultUnit ?? '(단위 없음)'}\n저장하면 현재 입력값으로 바뀝니다.'),
                ),
              if (_well.excluded)
                const Text('분석 제외 well입니다. 결과를 저장해도 제외 상태는 유지됩니다.'),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('sequential-value'),
                controller: _value,
                focusNode: _focus,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                    labelText: '${_well.label} 결과값',
                    errorText: _error,
                    errorMaxLines: 3),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sequential-unit'),
                controller: _unit,
                enabled: !_saving,
                decoration: const InputDecoration(
                    labelText: '결과 단위',
                    helperMaxLines: 3,
                    helperText: '미입력 well로 이동할 때 이 단위를 이어 씁니다.'),
              ),
              if (_failed)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('저장되지 않았습니다. 입력을 유지했습니다. 다시 확인하고 저장해주세요.',
                      key: ValueKey('sequential-save-error')),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('sequential-save-next'),
                onPressed: _saving ? null : () => _save(advance: true),
                icon: const Icon(Icons.navigate_next),
                label: Text(_saving
                    ? '저장 중…'
                    : next == null
                        ? '저장 후 마치기'
                        : '저장 후 다음 well'),
              ),
              TextButton(
                key: const ValueKey('sequential-save-close'),
                onPressed: _saving ? null : () => _save(advance: false),
                child: const Text('현재 well 저장 후 닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
