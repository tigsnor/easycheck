import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/assay_condition.dart';
import '../../domain/well.dart';
import 'condition_edit_action.dart';

class AssayConditionDraft {
  const AssayConditionDraft(this.condition)
      : mediumAction = null,
        vehicleAction = null;
  const AssayConditionDraft.patch(this.condition,
      {required this.mediumAction, required this.vehicleAction});
  final AssayCondition? condition;
  final ConditionEditAction? mediumAction, vehicleAction;
  AssayCondition? applyTo(AssayCondition? existing) {
    if (mediumAction == null) return condition;
    if (mediumAction == ConditionEditAction.keep &&
        vehicleAction == ConditionEditAction.keep) {
      return existing;
    }
    final medium = mediumAction == ConditionEditAction.keep
        ? existing?.medium
        : condition?.medium;
    if (medium == null || medium.isEmpty) {
      throw const FormatException('배지가 없는 well이 있습니다. 배지도 변경해주세요.');
    }
    if (vehicleAction == ConditionEditAction.keep && existing == null) {
      throw const FormatException(
          '용매 조건이 미지정인 well이 있습니다. 용매 조건을 변경하거나 용매 없음을 선택해주세요.');
    }
    final percent = vehicleAction == ConditionEditAction.keep
        ? existing!.vehiclePercent
        : vehicleAction == ConditionEditAction.clear
            ? 0.0
            : condition!.vehiclePercent;
    final vehicle = vehicleAction == ConditionEditAction.keep
        ? existing!.vehicle
        : vehicleAction == ConditionEditAction.clear
            ? null
            : condition!.vehicle;
    return AssayCondition(
        medium: medium, vehicle: vehicle, vehiclePercent: percent);
  }

  String get description => mediumAction == null
      ? condition?.label ?? '해제'
      : '배지 ${mediumAction == ConditionEditAction.keep ? '유지' : '변경'} · 용매 ${vehicleAction == ConditionEditAction.keep ? '유지' : vehicleAction == ConditionEditAction.clear ? '없음(0%)' : '변경'}';
}

class AssayConditionSheet extends StatefulWidget {
  const AssayConditionSheet(
      {required this.wells, required this.available, super.key});
  final List<Well> wells;
  final List<AssayCondition> available;

  @override
  State<AssayConditionSheet> createState() => _AssayConditionSheetState();
}

class _AssayConditionSheetState extends State<AssayConditionSheet> {
  final _medium = TextEditingController();
  final _percent = TextEditingController();
  final _mediumFocus = FocusNode();
  final _percentFocus = FocusNode();
  final _scroll = ScrollController();
  final _mediumField = GlobalKey();
  final _percentField = GlobalKey();
  final _vehicle = TextEditingController();
  late final String _initial;
  String? _mediumError;
  String? _percentError;
  ConditionEditAction _mediumAction = ConditionEditAction.change;
  ConditionEditAction _vehicleAction = ConditionEditAction.change;
  String? _mergeError;
  final _mergeErrorField = GlobalKey();
  bool _allowPop = false;
  bool _closing = false;

  String get _fingerprint => jsonEncode([
        _medium.text,
        _percent.text,
        _vehicle.text,
        _mediumAction.name,
        _vehicleAction.name
      ]);
  bool get _mixed =>
      widget.wells.map((w) => w.assayCondition).toSet().length > 1;

  @override
  void initState() {
    super.initState();
    if (!_mixed) {
      _fill(widget.wells.first.assayCondition);
    } else {
      _mediumAction = _vehicleAction = ConditionEditAction.keep;
    }
    _initial = _fingerprint;
  }

  void _fill(AssayCondition? condition) {
    _mediumAction = _vehicleAction = ConditionEditAction.change;
    _mergeError = null;
    _medium.text = condition?.medium ?? '';
    _percent.text = condition?.vehiclePercent.toString() ?? '';
    _vehicle.text = condition?.vehicle ?? '';
    _mediumError = _percentError = null;
  }

  @override
  void dispose() {
    _medium.dispose();
    _percent.dispose();
    _vehicle.dispose();
    _mediumFocus.dispose();
    _percentFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pop([AssayConditionDraft? draft]) async {
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
                title: const Text('배지·용매 조건 입력을 버릴까요?'),
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
              title: const Text('선택한 well의 배지·용매 조건을 해제할까요?'),
              content: Text(
                  '${widget.wells.length}개 well의 배지·용매만 지웁니다. 처리 농도와 결과는 유지됩니다.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('배지·용매 조건 해제')),
              ],
            ));
    if (!mounted) return;
    if (clear == true) {
      await _pop(const AssayConditionDraft(null));
    } else {
      _closing = false;
    }
  }

  Future<void> _apply() async {
    if (_closing) return;
    final medium = _medium.text.trim();
    final text = _percent.text.trim();
    final percent = double.tryParse(text);
    setState(() {
      _mediumError =
          _mediumAction == ConditionEditAction.change && medium.isEmpty
              ? '배지/버퍼를 입력해주세요.'
              : null;
      _mergeError = null;
      _percentError = _vehicleAction != ConditionEditAction.change
          ? null
          : percent == null || !percent.isFinite || percent < 0 || percent > 100
              ? '최종 용매 비율을 0~100 사이 숫자로 입력해주세요.'
              : _vehicle.text.trim().isEmpty && percent != 0
                  ? '용매 이름이 없으면 비율은 0이어야 합니다. 용매 이름도 확인해주세요.'
                  : null;
    });
    if (_mediumError != null || _percentError != null) {
      (_mediumError != null ? _mediumFocus : _percentFocus).requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final field = (_mediumError != null ? _mediumField : _percentField)
            .currentContext;
        if (field != null) {
          Scrollable.ensureVisible(field,
              alignment: 0.1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
      return;
    }
    final draft = AssayConditionDraft.patch(
        AssayCondition(
            medium: medium,
            vehiclePercent: percent ?? 0,
            vehicle:
                _vehicle.text.trim().isEmpty ? null : _vehicle.text.trim()),
        mediumAction: _mediumAction,
        vehicleAction: _vehicleAction);
    try {
      for (final well in widget.wells) {
        draft.applyTo(well.assayCondition);
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
                            child: Text(
                                '배지·용매 조건 · ${widget.wells.length}개 well',
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            key: const ValueKey('close-assay-condition'),
                            tooltip: '닫기',
                            onPressed: _close,
                            icon: const Icon(Icons.close)),
                      ]),
                      Text(widget.wells.map((w) => w.label).join(', '),
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      conditionEditAction(
                          field: '배지 적용',
                          keyName: 'assay-medium-action',
                          value: _mediumAction,
                          onChanged: (v) => setState(() => _mediumAction = v)),
                      const SizedBox(height: 8),
                      Container(
                          key: _mediumField,
                          child: TextField(
                              key: const ValueKey('assay-medium-input'),
                              enabled:
                                  _mediumAction == ConditionEditAction.change,
                              controller: _medium,
                              focusNode: _mediumFocus,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                  labelText: '배지/버퍼',
                                  hintText: '예: DMEM + 10% FBS, PBS',
                                  helperText: '필수 입력',
                                  errorText: _mediumError,
                                  errorMaxLines: 2))),
                      const SizedBox(height: 12),
                      conditionEditAction(
                          field: '용매·비율 적용',
                          keyName: 'assay-vehicle-action',
                          value: _vehicleAction,
                          clearLabel: '용매 없음 (0%)',
                          onChanged: (v) => setState(() => _vehicleAction = v)),
                      const SizedBox(height: 8),
                      if (_vehicleAction == ConditionEditAction.change) ...[
                        Container(
                            key: _percentField,
                            child: TextField(
                                key: const ValueKey('assay-percent-input'),
                                controller: _percent,
                                focusNode: _percentFocus,
                                keyboardType: TextInputType.text,
                                decoration: InputDecoration(
                                    labelText: '최종 용매 비율 (% v/v)',
                                    hintText: '예: 0, 0.1',
                                    errorText: _percentError,
                                    errorMaxLines: 3))),
                        const SizedBox(height: 12),
                        TextField(
                            key: const ValueKey('assay-vehicle-input'),
                            controller: _vehicle,
                            decoration: const InputDecoration(
                                labelText: '용매 이름 (없으면 빈칸)',
                                hintText: '예: DMSO, ethanol')),
                      ] else
                        Text(_vehicleAction == ConditionEditAction.keep
                            ? '각 well의 기존 용매 이름·비율을 유지합니다.'
                            : '용매 없음 (0%)으로 기록합니다.'),
                      const SizedBox(height: 12),
                      const Text(
                          'well의 최종 배지/버퍼와 용매 비율(% v/v)을 직접 기록합니다. 용매가 없으면 위에서 용매 없음 (0%)을 선택하세요. 농도·부피에서 자동 계산하거나 배지 성분을 추정하지 않습니다.'),
                      const Text(
                          '이름·비율이 정확히 같은 조건끼리 분석합니다. 조건 미지정은 용매 없음과 다릅니다.'),
                      if (_mixed)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                '서로 다른 배지·용매 조건이 선택되었습니다. 기본은 기존 값 유지이며 변경할 항목만 선택하세요.')),
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
                                key: const ValueKey('assay-partial-error'))),
                      FilledButton(
                          key: const ValueKey('apply-assay-condition'),
                          onPressed: _apply,
                          child: const Text('선택 well에 적용')),
                      if (widget.wells.any((w) => w.assayCondition != null))
                        TextButton(
                            key: const ValueKey('clear-assay-condition'),
                            onPressed: _clear,
                            child: const Text('배지·용매 조건 해제')),
                    ]),
              ),
            )),
      );
}
