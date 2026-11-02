import 'package:flutter/material.dart';

import '../../domain/exclusion_comparison.dart';
import '../../domain/plate.dart';
import '../../domain/plate_analysis_service.dart';
import '../../domain/plate_exclusion_event.dart';

class ExclusionReviewScreen extends StatefulWidget {
  const ExclusionReviewScreen(
      {required this.plate, this.initialWellLabel, super.key});
  final Plate plate;
  final String? initialWellLabel;
  @override
  State<ExclusionReviewScreen> createState() => _ExclusionReviewScreenState();
}

class _ExclusionReviewScreenState extends State<ExclusionReviewScreen> {
  late String _well = widget.initialWellLabel ?? '';
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final labels = {
      for (final w in widget.plate.wells) w.label,
      for (final e in widget.plate.exclusionEvents) e.wellLabel
    };
    final events = widget.plate.exclusionEvents.reversed
        .where((e) => _well.isEmpty || e.wellLabel == _well)
        .toList();
    final comparison = ExclusionComparison(widget.plate,
        wellLabel: _well.isEmpty ? null : _well);
    return Scaffold(
      appBar: AppBar(title: const Text('제외 이력·분석 비교')),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              DropdownButtonFormField<String>(
                  key: const ValueKey('exclusion-well-filter'),
                  initialValue: _well,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '조회 / 가상 포함 범위'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('전체 well')),
                    for (final label in labels)
                      DropdownMenuItem(value: label, child: Text(label))
                  ],
                  onChanged: (value) => setState(() => _well = value ?? '')),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                    key: const ValueKey('exclusion-comparison-tab'),
                    label: const Text('분석 비교'),
                    selected: !_history,
                    onSelected: (_) => setState(() => _history = false)),
                ChoiceChip(
                    key: const ValueKey('exclusion-history-tab'),
                    label: const Text('제외 이력'),
                    selected: _history,
                    onSelected: (_) => setState(() => _history = true)),
              ]),
            ])),
        Expanded(
          child: _history
              ? ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length + 1,
                  itemBuilder: (context, index) => index == 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Text('제외·해제 이력 ${events.length}건'),
                              const Text(
                                  '전용 이력은 20건 제한 없이 저장·백업합니다. 도입 전 기록은 전체 변경 이력에서 확인하세요. 삭제·과거 백업 복원으로 사라진 기록을 복구하는 기능은 아닙니다.'),
                              if (events.isEmpty)
                                const Text(
                                    '이 범위에 저장된 전용 제외 이력이 없습니다. 과거 사유나 시각을 추정하지 않습니다.'),
                              const SizedBox(height: 12),
                            ])
                      : _EventCard(event: events[index - 1]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: comparison.rows.length + 1,
                  itemBuilder: (context, index) => index == 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              const Text(
                                  '현재 측정값·조건·수동 기준을 그대로 두고, 선택 범위의 제외 상태만 가상으로 해제합니다. 과거 시점의 분석 재현이 아니며 실제 기록은 바뀌지 않습니다.'),
                              Text(comparison.reinstatedLabels.isEmpty
                                  ? '선택 범위에 현재 제외된 well이 없습니다.'
                                  : '가상 포함: ${comparison.reinstatedLabels.join(', ')}'),
                              Text(
                                  '측정값 있는 well 사용 수: 현재 ${comparison.current.includedWellCount}개 → 가상 ${comparison.hypothetical.includedWellCount}개'),
                              const Text(
                                  'Blank/Control 제외의 영향도 전체 series에 다시 계산합니다. —는 계산할 값/기준이 없음을 뜻하며 0이 아닙니다. 표시값은 반올림됩니다.'),
                              if (comparison.rows.isEmpty)
                                const Text('비교할 측정값이 없습니다.'),
                              const SizedBox(height: 12),
                            ])
                      : _ComparisonCard(
                          current: comparison.rows[index - 1].current,
                          hypothetical:
                              comparison.rows[index - 1].hypothetical)),
        ),
      ])),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final PlateExclusionEvent event;
  String _result(double? value, String? unit) => value == null
      ? '미입력'
      : '$value ${unit?.isNotEmpty == true ? unit : '단위 미지정'}';
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${event.wellLabel} · ${event.beforeExcluded ? '제외' : '포함'} → ${event.afterExcluded ? '제외' : '포함'}',
                  style: Theme.of(context).textTheme.titleMedium),
              Text(
                  '${event.changedAt.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first} · 기기 현지 시각 · ${event.source.label}'),
              SelectableText('사유 / 변경 경로: ${event.reason}'),
              Text(
                  '변경 당시 측정값: ${_result(event.beforeResult, event.beforeUnit)} → ${_result(event.afterResult, event.afterUnit)}'),
            ],
          )));
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.current, required this.hypothetical});
  final PlateAnalysisSeries? current, hypothetical;
  String _number(double? n) => n == null
      ? '—'
      : n == 0
          ? '0'
          : n.toStringAsPrecision(5);
  @override
  Widget build(BuildContext context) {
    final s = current ?? hypothetical!;
    final metrics = <(String, String, String)>[
      (
        '사용 well 수',
        '${current?.replicateCount ?? 0}',
        '${hypothetical?.replicateCount ?? 0}'
      ),
      ('평균', _number(current?.rawMean), _number(hypothetical?.rawMean)),
      (
        '표본 SD',
        _number(current?.standardDeviation),
        _number(hypothetical?.standardDeviation)
      ),
      (
        'CV (%)',
        _number(current?.coefficientOfVariation),
        _number(hypothetical?.coefficientOfVariation)
      ),
      (
        'Blank 보정',
        _number(current?.blankCorrectedMean),
        _number(hypothetical?.blankCorrectedMean)
      ),
      (
        'Control 대비 (%)',
        _number(current?.normalizedPercent),
        _number(hypothetical?.normalizedPercent)
      ),
    ];
    Widget references(String title, PlateAnalysisSeries? value) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '$title 기준: ${value == null ? '사용한 측정값 없음' : 'Blank ${value.reference?.blankWellLabels.join(', ') ?? ''} / Control ${value.reference?.controlWellLabels.join(', ') ?? ''}'}'),
          for (final warning in value?.reference?.warnings ?? <String>[])
            Text('$title: $warning'),
        ]);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.label} · ${s.role.analysisLabel}',
                  style: Theme.of(context).textTheme.titleMedium),
              Text(
                  '처리 농도 ${s.concentrationValue ?? '미지정'} ${s.concentrationUnit ?? ''} · 결과 단위 ${s.resultUnit}'),
              Text(
                  '${s.cellCondition?.label ?? '세포 미지정'}\n${s.assayCondition?.label ?? '배지·용매 미지정'}'),
              const SizedBox(height: 8),
              Table(columnWidths: const {
                0: FlexColumnWidth(1.3),
                1: FlexColumnWidth(),
                2: FlexColumnWidth()
              }, children: [
                const TableRow(
                    children: [Text('지표'), Text('현재'), Text('가상 포함')]),
                for (final row in metrics)
                  TableRow(
                      children: [Text(row.$1), Text(row.$2), Text(row.$3)]),
              ]),
              const SizedBox(height: 8),
              references('현재', current),
              references('가상', hypothetical),
            ])));
  }
}
