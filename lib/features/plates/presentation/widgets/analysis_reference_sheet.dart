import 'package:flutter/material.dart';

import '../../domain/plate.dart';
import '../../domain/plate_analysis_reference.dart';
import '../../domain/well.dart';
import '../../domain/well_role.dart';

class AnalysisReferenceSheet extends StatefulWidget {
  const AnalysisReferenceSheet({
    required this.plate,
    required this.groupId,
    required this.groupLabel,
    required this.resultUnit,
    required this.onSave,
    super.key,
  });
  final Plate plate;
  final String? groupId;
  final String groupLabel;
  final String resultUnit;
  final Future<bool> Function(PlateAnalysisReferenceSelection?) onSave;

  @override
  State<AnalysisReferenceSheet> createState() => _AnalysisReferenceSheetState();
}

class _AnalysisReferenceSheetState extends State<AnalysisReferenceSheet> {
  late bool _automatic;
  late final bool _initialAutomatic;
  late final Set<String> _initialBlanks;
  late final Set<String> _initialControls;
  late final Set<String> _blanks;
  late final Set<String> _controls;
  bool _saving = false;
  bool _failed = false;
  bool _allowPop = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final selected = widget.plate.analysisReferences
        .where((s) =>
            s.groupId == widget.groupId && s.resultUnit == widget.resultUnit)
        .firstOrNull;
    _automatic = _initialAutomatic = selected == null;
    _blanks = {...?selected?.blankWellLabels};
    _controls = {...?selected?.controlWellLabels};
    _initialBlanks = {..._blanks};
    _initialControls = {..._controls};
  }

  bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
  bool get _dirty =>
      _failed ||
      _automatic != _initialAutomatic ||
      (!_automatic &&
          (!_same(_blanks, _initialBlanks) ||
              !_same(_controls, _initialControls)));

  Future<void> _pop() async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _close() async {
    if (_saving || _confirming) return;
    if (_dirty) {
      _confirming = true;
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('기준 변경을 버릴까요?'),
                content: const Text('저장하지 않은 선택은 적용되지 않습니다.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('계속 편집')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('변경 버리고 닫기')),
                ],
              ));
      _confirming = false;
      if (discard != true || !mounted) return;
    }
    await _pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    bool saved;
    try {
      saved = await widget.onSave(_automatic
          ? null
          : PlateAnalysisReferenceSelection(
              groupId: widget.groupId,
              resultUnit: widget.resultUnit,
              blankWellLabels: _ordered(_blanks),
              controlWellLabels: _ordered(_controls),
            ));
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
    await _pop();
  }

  List<String> _ordered(Set<String> labels) => [
        for (final w in widget.plate.wells)
          if (labels.contains(w.label)) w.label,
        ...labels
            .where((label) => !widget.plate.wells.any((w) => w.label == label)),
      ];

  bool _eligible(Well w, bool blank) =>
      !w.excluded &&
      w.resultValue != null &&
      analysisResultUnit(w) == widget.resultUnit &&
      (blank
          ? w.role == WellRole.blank
          : analysisControlRoles.contains(w.role));

  Widget _choices(bool blank) {
    final selected = blank ? _blanks : _controls;
    final title = blank ? 'Blank' : 'Control';
    final wells = widget.plate.wells.where((w) => _eligible(w, blank)).toList();
    final unavailable =
        selected.where((label) => !wells.any((w) => w.label == label));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$title 기준 · ${selected.length}개 선택',
          style: Theme.of(context).textTheme.titleSmall),
      if (wells.isEmpty) Text('같은 결과 단위의 사용 가능한 $title well이 없습니다.'),
      for (final w in wells)
        CheckboxListTile(
          key: ValueKey('reference-${blank ? 'blank' : 'control'}-${w.label}'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: selected.contains(w.label),
          onChanged: _saving
              ? null
              : (value) => setState(() {
                    value! ? selected.add(w.label) : selected.remove(w.label);
                  }),
          title: Text('${w.label} · ${w.resultValue} ${widget.resultUnit}'),
          subtitle: Text('${switch (w.role) {
            WellRole.blank => 'Blank',
            WellRole.vehicleControl => 'Vehicle control',
            WellRole.untreatedControl => 'Untreated control',
            _ => 'Negative control'
          }} · ${widget.plate.groups.where((g) => g.id == w.groupId).firstOrNull?.name ?? '그룹 없음'}'),
        ),
      for (final label in unavailable)
        CheckboxListTile(
          key: ValueKey(
              'reference-unavailable-${blank ? 'blank' : 'control'}-$label'),
          contentPadding: EdgeInsets.zero,
          value: true,
          onChanged:
              _saving ? null : (_) => setState(() => selected.remove(label)),
          title: Text('$label · 사용 불가'),
          subtitle:
              const Text('미입력·제외·단위/역할 변경 또는 없는 좌표. 선택을 해제하고 기준을 다시 지정해주세요.'),
        ),
      const SizedBox(height: 12),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop || (!_saving && !_dirty),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _close();
        },
        child: SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text('분석 기준 설정',
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  key: const ValueKey('close-reference-editor'),
                  tooltip: '닫기',
                  onPressed: _saving ? null : _close,
                  icon: const Icon(Icons.close)),
            ]),
            Text(
                '${widget.groupLabel} · ${widget.resultUnit}\n이 그룹·결과 단위의 모든 농도와 역할에 적용합니다.'),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('automatic-references'),
              contentPadding: EdgeInsets.zero,
              title: const Text('자동 기준 사용'),
              value: _automatic,
              subtitle: const Text(
                  '같은 단위의 Blank 전체와 Vehicle → Untreated → Negative 순의 첫 control 역할 전체를 사용합니다.'),
              onChanged: _saving ? null : (v) => setState(() => _automatic = v),
            ),
            if (!_automatic) ...[
              const Text(
                  '수동 기준: 선택한 well의 평균을 사용합니다. Blank를 선택하지 않으면 원값을 사용하고, Control을 선택하지 않으면 정규화하지 않습니다.'),
              const SizedBox(height: 16),
              _choices(true),
              _choices(false),
              const Text(
                  '정규화 = (처리군 평균 − Blank 평균) / (Control 평균 − 동일한 Blank 평균) × 100. Control 평균이 Blank 평균과 같으면 계산하지 않습니다.'),
            ],
            if (_failed)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('저장하지 못했습니다. 선택은 유지됩니다. 다시 시도해주세요.',
                      semanticsLabel: '분석 기준 저장 실패')),
            const SizedBox(height: 16),
            FilledButton.icon(
                key: const ValueKey('save-analysis-references'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '저장 중…' : '기준 저장')),
          ]),
        )),
      );
}
