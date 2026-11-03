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
    this.selectedPositions = const {},
    this.recentUnits = const [],
    this.onUnitSaved,
    super.key,
  });

  final Set<WellPosition> selectedPositions;
  final List<String> recentUnits;
  final ValueChanged<String>? onUnitSaved;
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
  final _valueKey = GlobalKey();
  late final Set<WellPosition> _selection;
  final _visited = <WellPosition>{};
  final _skipped = <WellPosition>{};
  late final List<String> _recentUnits;
  late String _lastUnit;
  late bool _selectionOnly;
  String? _skippedLabel;

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

  List<WellPosition> _ordered(Iterable<WellPosition> positions) =>
      positions.toList()
        ..sort((a, b) {
          final first = _byColumn
              ? a.columnIndex.compareTo(b.columnIndex)
              : a.rowIndex.compareTo(b.rowIndex);
          return first != 0
              ? first
              : _byColumn
                  ? a.rowIndex.compareTo(b.rowIndex)
                  : a.columnIndex.compareTo(b.columnIndex);
        });

  WellPosition? get _next {
    final ordered = _ordered(_selectionOnly
        ? _selection
        : widget.plate.wells.map((w) => w.position));
    final candidates = _selectionOnly
        ? ordered
        : ordered.skip(ordered.indexOf(_well.position) + 1);
    return candidates
        .where((p) =>
            p != _well.position && (!_selectionOnly || !_visited.contains(p)))
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    final valid = widget.plate.wells.map((w) => w.position).toSet();
    _selection =
        Set.unmodifiable(widget.selectedPositions.where(valid.contains));
    _selectionOnly = _selection.length > 1;
    _recentUnits =
        widget.recentUnits.where((u) => u.trim().isNotEmpty).toSet().toList();
    _lastUnit = _recentUnits.firstOrNull ?? 'OD450';
    final start = _selectionOnly ? _ordered(_selection).first : widget.start;
    _load(start, fallbackUnit: _lastUnit);
    _value.addListener(_changed);
    _unit.addListener(_changed);
    if (start != widget.start) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onPositionChanged(start);
      });
    }
  }

  Future<bool> _discardForMove(String title, String action) async {
    _confirming = true;
    final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: const Text(
                    '현재 입력만 버립니다. 기존 측정값·분석 제외 상태와 앞서 저장한 well은 유지됩니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 입력')),
                  TextButton(
                      key: const ValueKey('confirm-sequential-discard-move'),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(action)),
                ]));
    _confirming = false;
    return mounted && discard == true;
  }

  Future<void> _selectScope(bool selectionOnly) async {
    if (_saving || _confirming || selectionOnly == _selectionOnly) return;
    WellPosition? target = _well.position;
    if (selectionOnly && !_selection.contains(target)) {
      target =
          _ordered(_selection).where((p) => !_visited.contains(p)).firstOrNull;
    }
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선택한 well은 이번 입력에서 모두 처리했습니다.')));
      return;
    }
    if (target != _well.position &&
        _dirty &&
        !await _discardForMove('입력을 버리고 선택한 범위로 이동할까요?', '입력 버리고 이동')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectionOnly = selectionOnly;
      if (target != _well.position) _load(target!, fallbackUnit: _lastUnit);
    });
    widget.onPositionChanged(target);
  }

  Future<void> _skip() async {
    if (_saving || _confirming) return;
    if (_dirty &&
        !await _discardForMove('현재 well의 입력을 버리고 건너뛸까요?', '입력 버리고 건너뛰기')) {
      return;
    }
    if (!mounted) return;
    final next = _next;
    final previous = _well;
    _visited.add(previous.position);
    _skipped.add(previous.position);
    if (next == null) {
      await _pop();
      return;
    }
    setState(() {
      _savedLabel = null;
      _skippedLabel = previous.label;
      _load(next, fallbackUnit: _lastUnit);
    });
    widget.onPositionChanged(next);
    _focus.requestFocus();
  }

  void _insertNumberText(String text) {
    if (_saving || _confirming) return;
    final selection = _value.selection;
    final start = selection.isValid ? selection.start : _value.text.length;
    final end = selection.isValid ? selection.end : start;
    _value.value = TextEditingValue(
        text: _value.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length));
    _focus.requestFocus();
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
    if (_saving || _confirming) return;
    final value = double.tryParse(_value.text.trim());
    if (value == null || !value.isFinite) {
      setState(() => _error = '유한한 숫자를 입력해주세요. 0도 결과값으로 저장됩니다.');
      _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(_valueKey.currentContext!, alignment: .1);
        }
      });
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
    _visited.add(updated.position);
    _lastUnit = unit;
    if (unit.isNotEmpty) {
      _recentUnits.remove(unit);
      _recentUnits.insert(0, unit);
      widget.onUnitSaved?.call(unit);
    }
    if (!advance || next == null) {
      await _pop();
      return;
    }
    setState(() {
      _savedLabel = updated.label;
      _skippedLabel = null;
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
              Text(_selectionOnly
                  ? '선택한 ${_selection.length}개 well만 입력합니다. 선택하지 않은 well은 이동·저장 대상에 포함되지 않습니다.'
                  : '현재 well부터 Plate 끝까지 순서대로 입력합니다. 빈 well과 분석 제외 well도 포함됩니다.'),
              if (_selection.isNotEmpty)
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      key: const ValueKey('sequential-scope-all'),
                      label: const Text('현재부터 끝까지'),
                      selected: !_selectionOnly,
                      onSelected: _saving ? null : (_) => _selectScope(false)),
                  ChoiceChip(
                      key: const ValueKey('sequential-scope-selection'),
                      label: Text('선택한 ${_selection.length}개만'),
                      selected: _selectionOnly,
                      onSelected: _saving ? null : (_) => _selectScope(true)),
                ]),
              if (_selectionOnly)
                Text(_ordered(_selection).map((p) => p.label).join(', '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              Text('이번 입력: 저장 ${_savedWells.length}개 · 건너뜀 ${_skipped.length}개',
                  key: const ValueKey('sequential-progress')),
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
              if (_skippedLabel != null) Text('$_skippedLabel 저장 없이 건너뜀'),
              if (_well.resultValue != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '기존 결과: ${_well.resultValue} ${_well.resultUnit ?? '(단위 없음)'}\n저장하면 현재 입력값으로 바뀝니다.'),
                ),
              if (_well.excluded)
                const Text('분석 제외 well입니다. 결과를 저장해도 제외 상태는 유지됩니다.'),
              const SizedBox(height: 16),
              Container(
                  key: _valueKey,
                  child: TextField(
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
                  )),
              Wrap(spacing: 8, children: [
                for (final entry
                    in {'minus': '-', 'decimal': '.', 'exponent': 'e'}.entries)
                  TextButton(
                      key: ValueKey('sequential-insert-${entry.key}'),
                      onPressed:
                          _saving ? null : () => _insertNumberText(entry.value),
                      child: Text(entry.value == 'e' ? '지수 e' : entry.value)),
              ]),
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
              if ([
                ..._recentUnits,
                ...widget.plate.wells.map((w) => w.resultUnit).nonNulls
              ].any((u) => u.trim().isNotEmpty)) ...[
                const Text('단위 다시 쓰기 · 선택하면 현재 입력칸에만 적용합니다.'),
                Wrap(spacing: 6, children: [
                  for (final unit in {
                    ..._recentUnits,
                    ...widget.plate.wells.map((w) => w.resultUnit).nonNulls
                  }.where((u) => u.trim().isNotEmpty).take(8))
                    ActionChip(
                        key: ValueKey('sequential-unit-$unit'),
                        label: Text(unit),
                        onPressed: _saving ? null : () => _unit.text = unit),
                ]),
              ],
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
                  key: const ValueKey('sequential-skip'),
                  onPressed: _saving ? null : _skip,
                  child: Text(next == null ? '저장 없이 마치기' : '저장 없이 건너뛰기')),
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
