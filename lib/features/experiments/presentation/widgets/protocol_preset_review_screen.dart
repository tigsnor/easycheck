import 'package:flutter/material.dart';

import '../../domain/experiment.dart';
import '../../domain/protocol_editing.dart';
import '../../domain/protocol_presets.dart';

class ProtocolPresetDraft {
  const ProtocolPresetDraft(this.type, this.tasks);
  final String type;
  final List<ExperimentTask> tasks;
}

class ProtocolPresetReviewScreen extends StatefulWidget {
  const ProtocolPresetReviewScreen(
      {required this.experiment, required this.targetType, super.key});
  final Experiment experiment;
  final String targetType;
  @override
  State<ProtocolPresetReviewScreen> createState() =>
      _ProtocolPresetReviewScreenState();
}

class _ProtocolPresetReviewScreenState
    extends State<ProtocolPresetReviewScreen> {
  ProtocolPresetMode _mode = ProtocolPresetMode.keep;
  late final _idPrefix = 'preset-${DateTime.now().microsecondsSinceEpoch}';
  List<ExperimentTask> get _after => ProtocolPresets.apply(
      widget.experiment, widget.targetType, _mode, _idPrefix);

  @override
  Widget build(BuildContext context) {
    final editable = ProtocolEditing.canEdit(widget.experiment);
    final after = editable ? _after : widget.experiment.tasks;
    final beforeIds = widget.experiment.tasks.map((t) => t.id).toSet();
    final afterIds = after.map((t) => t.id).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('유형·단계 비교'), actions: [
        TextButton(
            key: const ValueKey('apply-protocol-preset'),
            onPressed: !editable || after.isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    widget.targetType == widget.experiment.experimentType &&
                            !ProtocolEditing.changesSavedDefinition(
                                widget.experiment.tasks, after,
                                includeAdditions: true)
                        ? null
                        : ProtocolPresetDraft(widget.targetType, after)),
            child: const Text('노트에 적용'))
      ]),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        '${widget.experiment.experimentType} → ${widget.targetType}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text(
                        '추천 목록은 편집 가능한 체크리스트 초안입니다. 사용하는 키트·실험실 SOP와 대조하고 단계·시간을 확인해주세요. 농도·반응 시간·알림을 자동 지정하지 않습니다.'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final mode in ProtocolPresetMode.values)
                        ChoiceChip(
                            key: ValueKey('protocol-preset-${mode.name}'),
                            label: Text(switch (mode) {
                              ProtocolPresetMode.keep => '기존 단계 유지',
                              ProtocolPresetMode.replace => '추천 단계로 교체',
                              ProtocolPresetMode.append => '빠진 추천 단계 추가',
                            }),
                            selected: _mode == mode,
                            onSelected: !editable ||
                                    (mode == ProtocolPresetMode.replace &&
                                        !ProtocolPresets.canReplace(
                                            widget.experiment))
                                ? null
                                : (_) => setState(() => _mode = mode)),
                    ]),
                    if (!ProtocolPresets.canReplace(widget.experiment))
                      const Text(
                          '수행 후에는 전체 교체를 사용할 수 없습니다. 기존 단계를 유지하거나 추천 단계를 추가하세요.'),
                    const Text(
                        '같은 이름의 기존 단계는 ID·시간·알림·수행 기록을 유지합니다. 같은 이름이 여럿이면 첫 단계 설정을 유지합니다. 실제로 같은 작업인지 확인해주세요.'),
                    if (_mode == ProtocolPresetMode.replace)
                      const Text(
                          '교체 시 추천 목록에 없는 기존 단계는 삭제됩니다. 아래 삭제 목록을 확인하세요.'),
                    if (after.isEmpty)
                      const Text(
                          '단계는 최소 1개 필요합니다. 추천 단계를 추가하거나 돌아가서 단계를 구성해주세요.'),
                    Text(
                        '추가 ${afterIds.difference(beforeIds).length}개 · 삭제 ${beforeIds.difference(afterIds).length}개',
                        key: const ValueKey('protocol-preset-change-count')),
                    for (final line in ProtocolEditing.describe(
                        widget.experiment.tasks, after))
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(line)),
                    const Divider(),
                    Text('${widget.targetType} 추천 체크리스트'),
                    for (var i = 0;
                        i < ProtocolPresets.titles(widget.targetType).length;
                        i++)
                      Text(
                          '${i + 1}. ${ProtocolPresets.titles(widget.targetType)[i]}'),
                    const SizedBox(height: 12),
                    const Text(
                        '노트에 적용한 뒤 상단에서 저장해주세요. 수행 후 변경은 저장 시 사유를 남깁니다.'),
                  ]))),
    );
  }
}
