import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../shared/models/cell_number.dart';
import '../../../../shared/presentation/scientific_cell_input.dart';
import '../../domain/cell_condition.dart';
import '../../domain/well.dart';
import 'condition_edit_action.dart';

class CellConditionDraft {
  const CellConditionDraft(this.condition)
      : nameAction = null,
        quantityAction = null;
  const CellConditionDraft.patch(this.condition,
      {required this.nameAction, required this.quantityAction});
  final CellCondition? condition;
  final ConditionEditAction? nameAction, quantityAction;
  CellCondition? applyTo(CellCondition? existing) {
    if (nameAction == null) return condition;
    if (nameAction == ConditionEditAction.keep &&
        quantityAction == ConditionEditAction.keep) {
      return existing;
    }
    if (existing == null &&
        nameAction == ConditionEditAction.keep &&
        quantityAction == ConditionEditAction.clear) {
      return null;
    }
    final name = nameAction == ConditionEditAction.keep
        ? existing?.name
        : condition?.name;
    if (name == null || name.isEmpty) {
      throw const FormatException('세포 종류가 없는 well이 있습니다. 세포 종류도 변경해주세요.');
    }
    final density = switch (quantityAction!) {
      ConditionEditAction.keep => existing?.density,
      ConditionEditAction.change => condition?.density,
      ConditionEditAction.clear => null,
    };
    final unit = quantityAction == ConditionEditAction.keep
        ? existing?.unit
        : condition?.unit;
    return CellCondition(
        name: name, density: density, unit: density == null ? null : unit);
  }

  String get description => nameAction == null
      ? condition?.label ?? '해제'
      : '세포 종류 ${nameAction == ConditionEditAction.keep ? '유지' : '변경'} · 수치 ${quantityAction == ConditionEditAction.keep ? '유지' : quantityAction == ConditionEditAction.clear ? '해제' : '변경'}';
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
  final _exponent = TextEditingController();
  final _nameFocus = FocusNode();
  final _densityFocus = FocusNode();
  final _scroll = ScrollController();
  final _nameField = GlobalKey();
  final _densityField = GlobalKey();
  String _unit = CellCondition.units.first;
  late final String _initial;
  String? _nameError;
  String? _densityError;
  ConditionEditAction _nameAction = ConditionEditAction.change;
  ConditionEditAction _quantityAction = ConditionEditAction.change;
  String? _mergeError;
  final _mergeErrorField = GlobalKey();
  bool _allowPop = false;
  bool _closing = false;

  String get _fingerprint => jsonEncode([
        _name.text,
        _density.text,
        _exponent.text,
        _unit,
        _nameAction.name,
        _quantityAction.name
      ]);
  bool get _mixed =>
      widget.wells.map((w) => w.cellCondition).toSet().length > 1;

  @override
  void initState() {
    super.initState();
    if (!_mixed) {
      _fill(widget.wells.first.cellCondition);
    } else {
      _nameAction = _quantityAction = ConditionEditAction.keep;
    }
    _initial = _fingerprint;
  }

  void _fill(CellCondition? condition) {
    _nameAction = _quantityAction = ConditionEditAction.change;
    _mergeError = null;
    _name.text = condition?.name ?? '';
    _density.text = condition?.density?.toString() ?? '';
    _exponent.clear();
    _unit = condition?.unit ?? CellCondition.units.first;
    _nameError = _densityError = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _density.dispose();
    _exponent.dispose();
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
    double? density;
    String? error;
    try {
      if (_quantityAction == ConditionEditAction.change) {
        density = CellNumber.parse(_density.text, _exponent.text);
      }
    } on FormatException {
      error = '0 이상의 숫자와 정수 지수를 확인해주세요. 일반 숫자는 지수를 비워둡니다.';
    }
    setState(() {
      _nameError = _nameAction == ConditionEditAction.change && name.isEmpty
          ? '세포 종류를 입력해주세요.'
          : null;
      _mergeError = null;
      _densityError = error;
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
    final draft = CellConditionDraft.patch(
        CellCondition(
            name: name, density: density, unit: density == null ? null : _unit),
        nameAction: _nameAction,
        quantityAction: _quantityAction);
    try {
      for (final well in widget.wells) {
        draft.applyTo(well.cellCondition);
      }
    } on FormatException catch (e) {
      setState(() => _mergeError = e.message);
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mergeErrorField.currentContext != null) {
          Scrollable.ensureVisible(_mergeErrorField.currentContext!,
              alignment: .1, duration: const Duration(milliseconds: 200));
        }
      });
      return;
    }
    _closing = true;
    await _pop(draft);
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
                      conditionEditAction(
                          field: '세포 종류 적용',
                          keyName: 'cell-name-action',
                          value: _nameAction,
                          onChanged: (v) => setState(() => _nameAction = v)),
                      const SizedBox(height: 8),
                      Container(
                          key: _nameField,
                          child: TextField(
                              key: const ValueKey('cell-name-input'),
                              enabled:
                                  _nameAction == ConditionEditAction.change,
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
                      conditionEditAction(
                          field: '세포 수치·단위 적용',
                          keyName: 'cell-quantity-action',
                          value: _quantityAction,
                          clearLabel: '수치·단위 해제',
                          onChanged: (v) =>
                              setState(() => _quantityAction = v)),
                      const SizedBox(height: 8),
                      if (_quantityAction == ConditionEditAction.change) ...[
                        Container(
                            key: _densityField,
                            child: ScientificCellInput(
                                coefficientController: _density,
                                exponentController: _exponent,
                                unit: _unit,
                                coefficientKey:
                                    const ValueKey('cell-density-input'),
                                exponentKey:
                                    const ValueKey('cell-exponent-input'),
                                coefficientFocusNode: _densityFocus,
                                errorText: _densityError)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                            key: ValueKey('cell-unit-$_unit'),
                            initialValue: _unit,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: '세포 단위'),
                            items: [
                              for (final unit in CellCondition.units)
                                DropdownMenuItem(value: unit, child: Text(unit))
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _unit = value);
                              }
                            }),
                      ] else
                        Text(_quantityAction == ConditionEditAction.keep
                            ? '각 well의 기존 세포 수치·단위를 유지합니다.'
                            : '세포 수치·단위를 해제합니다. 세포 종류는 위에서 선택한 방식대로 적용합니다.'),
                      const SizedBox(height: 12),
                      const Text(
                          'cells/mL는 현탁액 농도, cells/well은 well당 파종 수입니다. 부피에 따른 자동 환산은 하지 않습니다. 약물 처리 농도는 별도로 유지됩니다.'),
                      if (_mixed)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                '서로 다른 세포 조건이 선택되었습니다. 기본은 기존 값 유지이며 변경할 항목만 선택하세요.')),
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
                      if (_mergeError != null)
                        Container(
                            key: _mergeErrorField,
                            child: Text(_mergeError!,
                                key: const ValueKey('cell-partial-error'))),
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
