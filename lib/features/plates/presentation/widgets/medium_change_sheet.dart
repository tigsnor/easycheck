import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../dilution/domain/medium_change_plan.dart';
import '../../domain/assay_condition.dart';
import '../../domain/plate_medium_change_service.dart';
import '../../domain/well.dart';

class MediumChangeDraft {
  const MediumChangeDraft(this.plan, this.finalMedium);
  final MediumChangePlan plan;
  final String finalMedium;
}

class MediumChangeSheet extends StatefulWidget {
  const MediumChangeSheet({required this.wells, super.key});
  final List<Well> wells;
  @override
  State<MediumChangeSheet> createState() => _MediumChangeSheetState();
}

class _MediumChangeSheetState extends State<MediumChangeSheet> {
  final _fields = {
    for (final key in [
      'initial-volume',
      'initial-concentration',
      'initial-percent',
      'removed-volume',
      'incoming-volume',
      'incoming-concentration',
      'incoming-percent',
      'unit',
      'vehicle',
      'medium',
    ])
      key: TextEditingController()
  };
  MediumChangeMode _mode = MediumChangeMode.add;
  MediumChangePlan? _plan;
  String? _error;
  bool _confirmed = false, _closing = false, _allowPop = false;
  final _feedbackKey = GlobalKey();
  late final String _initial;
  String get _fingerprint =>
      jsonEncode([_mode.name, for (final c in _fields.values) c.text]);

  @override
  void initState() {
    super.initState();
    String common(Object? Function(Well) value) {
      final values = widget.wells.map(value).toSet();
      return values.length == 1 ? values.single?.toString() ?? '' : '';
    }

    _fields['initial-volume']!.text =
        common((w) => w.volumeUnit == 'µL' ? w.volumeValue : null);
    _fields['initial-concentration']!.text =
        common((w) => w.concentrationValue);
    _fields['initial-percent']!.text =
        common((w) => w.assayCondition?.vehiclePercent);
    _fields['unit']!.text = common((w) => w.concentrationUnit);
    _fields['vehicle']!.text = common((w) => w.assayCondition?.vehicle);
    _fields['medium']!.text = common((w) => w.assayCondition?.medium);
    _initial = _fingerprint;
    for (final field in _fields.values) {
      field.addListener(_invalidate);
    }
  }

  void _invalidate() => setState(() {
        _plan = null;
        _error = null;
        _confirmed = false;
      });
  String _text(String key) => _fields[key]!.text.trim();
  double _number(String key, String name) {
    final value = double.tryParse(_text(key));
    if (value == null || !value.isFinite) {
      throw FormatException('$name 값을 숫자로 입력해주세요. 미기록 값은 0으로 추정하지 않습니다.');
    }
    return value;
  }

  void _calculate() {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final full = _mode == MediumChangeMode.replaceAll;
      final plan = MediumChangePlan(
        mode: _mode,
        unit: _text('unit'),
        vehicle: _text('vehicle').isEmpty ? null : _text('vehicle'),
        initialVolume: full ? 0 : _number('initial-volume', '기존 부피'),
        initialConcentration:
            full ? 0 : _number('initial-concentration', '기존 농도'),
        initialVehiclePercent:
            full ? 0 : _number('initial-percent', '기존 용매 비율'),
        removedVolume: _mode == MediumChangeMode.replacePart
            ? _number('removed-volume', '제거 부피')
            : 0,
        incomingVolume: _number('incoming-volume', '추가 용액 부피'),
        incomingConcentration: _number('incoming-concentration', '추가 용액 농도'),
        incomingVehiclePercent: _number('incoming-percent', '추가 용액의 용매 비율'),
      );
      if (!(plan.incomingVolume * widget.wells.length).isFinite) {
        throw const FormatException('전체 준비량이 계산 범위를 벗어났습니다. 부피를 확인해주세요.');
      }
      AssayCondition.fromJson({
        'medium': _text('medium'),
        'vehicle': plan.vehicle,
        'vehiclePercent': plan.finalVehiclePercent
      });
      const PlateMediumChangeService().validateSource(widget.wells, plan);
      setState(() {
        _plan = plan;
        _error = null;
        _confirmed = false;
      });
    } on FormatException catch (e) {
      setState(() {
        _plan = null;
        _error = e.message;
        _confirmed = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _feedbackKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target,
            alignment: .1, duration: const Duration(milliseconds: 200));
      }
    });
  }

  Future<void> _pop([MediumChangeDraft? draft]) async {
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
                title: const Text('추가·교체 계산 입력을 버릴까요?'),
                content: const Text('선택한 well에는 아직 기록되지 않았습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 계산')),
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

  Future<void> _apply() async {
    if (_closing || _plan == null || !_confirmed) return;
    _closing = true;
    await _pop(MediumChangeDraft(_plan!, _text('medium')));
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _input(String key, String label, {String? helper}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
            key: ValueKey('medium-change-$key'),
            controller: _fields[key],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
                labelText: label, helperText: helper, helperMaxLines: 3)),
      );

  String _display(double value) {
    if (value == 0) return '0';
    final text = value.toStringAsPrecision(6);
    return text.contains('.') && !text.contains('e')
        ? text.replaceFirst(RegExp(r'\.?0+$'), '')
        : text;
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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('배지 추가·교체 계산',
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            key: const ValueKey('close-medium-change'),
                            tooltip: '닫기',
                            onPressed: _close,
                            icon: const Icon(Icons.close))
                      ]),
                      Text(
                          '${widget.wells.length}개 well · ${widget.wells.map((w) => w.label).join(', ')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                      const Text(
                          '모든 부피는 well당 µL입니다. 같은 시약과 같은 농도 단위, 한 종류의 용매를 계산합니다. 서로 다른 용매 혼합과 단위 환산은 지원하지 않습니다.'),
                      Wrap(spacing: 8, children: [
                        for (final mode in MediumChangeMode.values)
                          ChoiceChip(
                              key: ValueKey('medium-change-mode-${mode.name}'),
                              label: Text(mode.label),
                              selected: _mode == mode,
                              onSelected: (_) => setState(() {
                                    _mode = mode;
                                    _plan = null;
                                    _error = null;
                                    _confirmed = false;
                                  }))
                      ]),
                      _input('unit', '공통 농도 단위',
                          helper: '예: µM. 기존 시약과 추가 용액에 같은 단위를 사용하세요.'),
                      if (_mode != MediumChangeMode.replaceAll) ...[
                        const Text('기존 well의 조건 · 다른 값이나 미기록은 직접 확인'),
                        _input('initial-volume', '기존 배지 부피 (µL)'),
                        _input('initial-concentration', '기존 시약 농도'),
                        _input('initial-percent', '기존 용매 비율 (% v/v)'),
                        if (_mode == MediumChangeMode.replacePart)
                          _input('removed-volume', '먼저 제거할 부피 (µL)'),
                      ] else
                        const Text(
                            '기존 배지를 전량 제거하고 새 용액으로 교체합니다. 잔류액은 0으로 계산하며 기존 시약/용매는 최종 값에 포함하지 않습니다.'),
                      const SizedBox(height: 12),
                      const Text('추가할 용액의 조건'),
                      _input('incoming-volume', '추가 용액 부피 (µL)'),
                      _input('incoming-concentration', '추가 용액의 시약 농도'),
                      _input('incoming-percent', '추가 용액의 용매 비율 (% v/v)'),
                      _input('vehicle', '계산할 용매 이름 (없으면 빈칸)',
                          helper:
                              '용매가 없으면 해당 비율에 0을 명시하세요. 기존 용매와 이름이 같아야 합니다.'),
                      _input('medium', '최종 배지/버퍼 이름',
                          helper: '배지 성분은 계산하지 않습니다. 실제 최종 배지 이름을 확인하세요.'),
                      OutlinedButton(
                          key: const ValueKey('calculate-medium-change'),
                          onPressed: _calculate,
                          child: const Text('최종 조건 계산')),
                      Container(
                          key: _feedbackKey,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_error != null)
                                  Semantics(
                                      liveRegion: true,
                                      child: Text(_error!,
                                          key: const ValueKey(
                                              'medium-change-error'),
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                                if (_plan case final plan?) ...[
                                  Text('계산 결과 · well당',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  Text(
                                      '남는 기존 배지 ${_display(plan.retainedVolume)} µL'),
                                  Text('최종 부피 ${_display(plan.finalVolume)} µL',
                                      key: const ValueKey(
                                          'medium-change-final-volume')),
                                  Text(
                                      '최종 시약 농도 ${_display(plan.finalConcentration)} ${plan.unit}',
                                      key: const ValueKey(
                                          'medium-change-final-concentration')),
                                  Text(
                                      '최종 용매 비율 ${_display(plan.finalVehiclePercent)}% v/v',
                                      key: const ValueKey(
                                          'medium-change-final-percent')),
                                  Text(
                                      '추가 용액 준비량 ${_display(plan.incomingVolume * widget.wells.length)} µL (${widget.wells.length}개 well, 여유분 제외)'),
                                  if (plan.hasLowDispenseVolume)
                                    const Text(
                                        '1 µL 미만 분주/제거가 포함됩니다. 피펫의 검증 범위를 확인하세요.'),
                                  const Text(
                                      '표시값은 반올림되며 기록에는 계산값을 그대로 사용합니다. 부피는 합산되고, 제거한 배지는 균일하게 혼합되었다고 가정합니다. 증발·흡수·분해·세포 손실은 계산하지 않습니다. 세포 조건은 기존 파종 기록으로 유지됩니다.'),
                                  CheckboxListTile(
                                      key: const ValueKey(
                                          'confirm-medium-change'),
                                      contentPadding: EdgeInsets.zero,
                                      value: _confirmed,
                                      title: const Text(
                                          '위 입력·최종 배지·같은 시약/용매 조건이 선택한 모든 well에 해당함을 확인했습니다.'),
                                      onChanged: (v) => setState(
                                          () => _confirmed = v == true)),
                                  const Text(
                                      '기록 시 시약 농도·부피·배지·용매 조건을 갱신합니다. 측정값·실험군·역할은 유지하며 실제 작업 완료를 기록하지는 않습니다.'),
                                  FilledButton(
                                      key:
                                          const ValueKey('apply-medium-change'),
                                      onPressed: _confirmed ? _apply : null,
                                      child: const Text('선택 well에 최종 조건 기록')),
                                ],
                              ])),
                    ],
                  )),
            )),
      );
}
