import 'dart:convert';

import 'plate.dart';
import 'well.dart';
import 'well_group.dart';
import 'well_role.dart';

class ConditionFieldChange {
  const ConditionFieldChange(this.label, this.before, this.after);
  final String label;
  final String before;
  final String after;
}

class MeasuredWellChange {
  const MeasuredWellChange(this.before, this.after, this.fields,
      {required this.beforeGroup, required this.afterGroup});
  final Well before;
  final Well? after;
  final WellGroup? beforeGroup;
  final WellGroup? afterGroup;
  final List<ConditionFieldChange> fields;

  String get resultBefore => _result(before);
  String get resultAfter => after == null ? 'well 없음' : _result(after!);

  static String _result(Well well) => well.resultValue == null
      ? '측정값 없음'
      : '${well.resultValue} ${_unit(well.resultUnit)}${well.excluded ? ' · 분석 제외' : ''}';
}

/// Compares saved measurements against a proposed Plate before any write.
/// Pure result edits and exclusion changes retain their existing workflows.
class MeasuredConditionReview {
  const MeasuredConditionReview(this.changes, this.otherChangedWellCount);
  final List<MeasuredWellChange> changes;
  final int otherChangedWellCount;

  factory MeasuredConditionReview.compare(Plate before, Plate after) {
    final oldGroups = {for (final group in before.groups) group.id: group};
    final newGroups = {for (final group in after.groups) group.id: group};
    final newWells = {for (final well in after.wells) well.position: well};
    final changes = <MeasuredWellChange>[];
    var otherChanged = 0;
    for (final old in before.wells) {
      final next = newWells[old.position];
      final oldGroup = oldGroups[old.groupId];
      final newGroup = newGroups[next?.groupId];
      final fields = <ConditionFieldChange>[];
      if (old.resultValue != null) {
        if (next == null) {
          fields.add(const ConditionFieldChange('well', '기존 well', '삭제'));
        } else {
          if (old.groupId != next.groupId ||
              oldGroup?.name != newGroup?.name ||
              oldGroup?.compoundName != newGroup?.compoundName) {
            final from = _group(oldGroup);
            final to = _group(newGroup);
            fields.add(ConditionFieldChange(
                '그룹',
                from,
                from == to && old.groupId != next.groupId
                    ? '$to (다른 그룹)'
                    : to));
          }
          if (old.cellCondition != next.cellCondition) {
            fields.add(ConditionFieldChange(
                '세포 조건',
                old.cellCondition?.label ?? '미지정',
                next.cellCondition?.label ?? '미지정'));
          }
          if (old.role != next.role) {
            fields.add(
                ConditionFieldChange('역할', _role(old.role), _role(next.role)));
          }
          if (old.concentrationValue != next.concentrationValue ||
              old.concentrationUnit != next.concentrationUnit ||
              (old.concentrationUnit ?? oldGroup?.concentrationUnit) !=
                  (next.concentrationUnit ?? newGroup?.concentrationUnit)) {
            fields.add(ConditionFieldChange('농도', _concentration(old, oldGroup),
                _concentration(next, newGroup)));
          }
          if (old.volumeValue != next.volumeValue ||
              old.volumeUnit != next.volumeUnit) {
            fields.add(ConditionFieldChange(
                '부피',
                '${old.volumeValue ?? '미기록'} ${old.volumeUnit}',
                '${next.volumeValue ?? '미기록'} ${next.volumeUnit}'));
          }
          if (old.replicateIndex != next.replicateIndex) {
            fields.add(ConditionFieldChange(
                '반복 번호',
                '${old.replicateIndex ?? '미지정'}',
                '${next.replicateIndex ?? '미지정'}'));
          }
          // Clearing a measurement clears its unit through the existing explicit
          // result-edit flow. Relabelling a retained measurement is a correction.
          if (next.resultValue != null && old.resultUnit != next.resultUnit) {
            fields.add(ConditionFieldChange(
                '결과 단위', _unit(old.resultUnit), _unit(next.resultUnit)));
          }
        }
      }
      if (fields.isNotEmpty) {
        changes.add(MeasuredWellChange(old, next, fields,
            beforeGroup: oldGroup, afterGroup: newGroup));
      } else if (next == null ||
          jsonEncode(old.toJson()) != jsonEncode(next.toJson())) {
        otherChanged++;
      }
    }
    final oldPositions = before.wells.map((well) => well.position).toSet();
    otherChanged += after.wells
        .where((well) => !oldPositions.contains(well.position))
        .length;
    return MeasuredConditionReview(changes, otherChanged);
  }

  /// Stored in the existing revision summary together with its before snapshot.
  /// Explicit before/after text remains readable without a schema migration.
  String record(String reason) {
    if (reason.trim().isEmpty) throw ArgumentError('정정 사유가 필요합니다.');
    return [
      '측정 후 조건 정정: ${changes.length}개 well',
      '정정 사유: ${reason.trim()}',
      if (otherChangedWellCount > 0) '함께 변경한 기타 well: $otherChangedWellCount개',
      for (final change in changes) ...[
        '${change.before.label} · 결과: ${change.resultBefore} → ${change.resultAfter}',
        for (final field in change.fields)
          '${field.label}: ${field.before} → ${field.after}',
        if (change.before.groupId != change.after?.groupId)
          '그룹 연결 ID: ${change.before.groupId ?? '없음'} → ${change.after?.groupId ?? '없음'}',
      ],
    ].join('\n');
  }
}

String _unit(String? value) =>
    value == null || value.trim().isEmpty ? '단위 미지정' : value;
String _group(WellGroup? group) => group == null
    ? '그룹 없음'
    : '${group.name}${group.compoundName == null ? '' : ' · ${group.compoundName}'}';
String _concentration(Well well, WellGroup? group) =>
    '${well.concentrationValue ?? '미기록'} ${well.concentrationUnit == null && group != null ? '${_unit(group.concentrationUnit)} (그룹 기준)' : _unit(well.concentrationUnit)}';
String _role(WellRole role) => switch (role) {
      WellRole.empty => '미지정',
      WellRole.treatment => '처리군',
      WellRole.sample => '시료',
      WellRole.blank => 'Blank',
      WellRole.negativeControl => 'Negative control',
      WellRole.positiveControl => 'Positive control',
      WellRole.vehicleControl => 'Vehicle control',
      WellRole.untreatedControl => 'Untreated control',
      WellRole.standard => 'Standard',
    };
