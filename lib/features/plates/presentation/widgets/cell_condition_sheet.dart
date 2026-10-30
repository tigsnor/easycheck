import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/cell_condition.dart';
import '../../domain/well.dart';

class CellConditionDraft {
  const CellConditionDraft(this.condition);
  final CellCondition? condition;
}

class CellConditionSheet extends StatefulWidget {
  const CellConditionSheet(
      {required this.wells, required this.available, super.key});
  final List<Well> wells;
  final List<CellCondition> available;

  @override
  State<CellConditionSheet> createState() => _CellConditionSheetState();
}

class _CellConditionSheetState extends State<CellConditionSheet> {
  final _name = TextEditingController();
  final _density = TextEditingController();
  final _nameFocus = FocusNode();
  final _densityFocus = FocusNode();
  final _scroll = ScrollController();
  final _nameField = GlobalKey();
  final _densityField = GlobalKey();
  String _unit = CellCondition.units.first;
  late final String _initial;
  String? _nameError;
  String? _densityError;
  bool _allowPop = false;
  bool _closing = false;

  String get _fingerprint => jsonEncode([_name.text, _density.text, _unit]);
  bool get _mixed =>
      widget.wells.map((w) => w.cellCondition).toSet().length > 1;

  @override
  void initState() {
    super.initState();
    if (!_mixed) _fill(widget.wells.first.cellCondition);
    _initial = _fingerprint;
  }

  void _fill(CellCondition? condition) {
    _name.text = condition?.name ?? '';
    _density.text = condition?.density?.toString() ?? '';
    _unit = condition?.unit ?? CellCondition.units.first;
    _nameError = _densityError = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _density.dispose();
    _nameFocus.dispose();
    _densityFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pop([CellConditionDraft? draft]) async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, draft);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (_fingerprint != _initial) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('세포 조건 입력을 버릴까요?'),
                content: const Text('선택한 well에는 아직 적용되지 않았습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 편집')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('입력 버리고 닫기')),
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

  Future<void> _clear() async {
    if (_closing) return;
    _closing = true;
    final clear = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('선택한 well의 세포 조건을 해제할까요?'),
              content: Text(
                  '${widget.wells.length}개 well의 세포 종류·세포 농도만 지웁니다. 처리 농도와 결과는 유지됩니다.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('세포 조건 해제')),
              ],
            ));
    if (!mounted) return;
    if (clear == true) {
      await _pop(const CellConditionDraft(null));
    } else {
      _closing = false;
    }
  }

  Future<void> _apply() async {
    if (_closing) return;
    final name = _name.text.trim();
    final text = _density.text.trim();
    final density = double.tryParse(text);
    setState(() {
      _nameError = name.isEmpty ? '세포 종류를 입력해주세요.' : null;
      _densityError = text.isNotEmpty &&
              (density == null || !density.isFinite || density < 0)
          ? '0 이상의 숫자를 입력해주세요. 예: 5000 또는 1e5'
          : null;
    });
    if (_nameError != null || _densityError != null) {
      (_nameError != null ? _nameFocus : _densityFocus).requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final field =
            (_nameError != null ? _nameField : _densityField).currentContext;
        if (field != null) {
          Scrollable.ensureVisible(field,
              alignment: 0.1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
      return;
    }
    _closing = true;
    await _pop(CellConditionDraft(CellCondition(
        name: name, density: density, unit: density == null ? null : _unit)));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('세포 조건 · ${widget.wells.length}개 well',
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            key: const ValueKey('close-cell-condition'),
                            tooltip: '닫기',
                            onPressed: _close,
                            icon: const Icon(Icons.close)),
                      ]),
                      Text(widget.wells.map((w) => w.label).join(', '),
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Container(
                          key: _nameField,
                          child: TextField(
                              key: const ValueKey('cell-name-input'),
                              controller: _name,
                              focusNode: _nameFocus,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                  labelText: '세포 종류',
                                  hintText: '예: HEK293, HeLa',
                                  helperText: '필수 입력',
                                  errorText: _nameError,
                                  errorMaxLines: 2))),
                      const SizedBox(height: 12),
                      Container(
                          key: _densityField,
                          child: TextField(
                              key: const ValueKey('cell-density-input'),
                              controller: _density,
                              focusNode: _densityFocus,
                              keyboardType: TextInputType.text,
                              decoration: InputDecoration(
                                  labelText: '세포 농도 / 파종 수 (선택)',
                                  hintText: '예: 5000 또는 1e5',
                                  errorText: _densityError,
                                  errorMaxLines: 3))),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          key: ValueKey('cell-unit-$_unit'),
                          initialValue: _unit,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '세포 단위'),
                          items: [
                            for (final unit in CellCondition.units)
                              DropdownMenuItem(value: unit, child: Text(unit))
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _unit = value);
                          }),
                      const SizedBox(height: 12),
                      const Text(
                          'cells/mL는 현탁액 농도, cells/well은 well당 파종 수입니다. 부피에 따른 자동 환산은 하지 않습니다. 약물 처리 농도는 별도로 유지됩니다.'),
                      if (_mixed)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                '서로 다른 세포 조건이 선택되었습니다. 적용하면 선택한 모든 well이 위 조건으로 바뀝니다.')),
                      if (widget.available.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('이 Plate의 조건 불러오기'),
                        Wrap(spacing: 8, children: [
                          for (final condition in widget.available)
                            ActionChip(
                                label: Text(condition.label),
                                onPressed: () =>
                                    setState(() => _fill(condition)))
                        ]),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                          key: const ValueKey('apply-cell-condition'),
                          onPressed: _apply,
                          child: const Text('선택 well에 적용')),
                      if (widget.wells.any((w) => w.cellCondition != null))
                        TextButton(
                            key: const ValueKey('clear-cell-condition'),
                            onPressed: _clear,
                            child: const Text('세포 조건 해제')),
                    ]),
              ),
            )),
      );
}
