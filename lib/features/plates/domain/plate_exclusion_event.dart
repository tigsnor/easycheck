import '../../../shared/data/json_validation.dart';
import 'well.dart';

enum ExclusionChangeSource { wellEdit, undo, restore, template, other }

extension ExclusionChangeSourceLabel on ExclusionChangeSource {
  String get label => switch (this) {
        ExclusionChangeSource.wellEdit => 'well 편집',
        ExclusionChangeSource.undo => '실행 취소',
        ExclusionChangeSource.restore => '이력 복원',
        ExclusionChangeSource.template => '템플릿 적용',
        ExclusionChangeSource.other => 'Plate 변경',
      };
}

/// Lightweight append-only history, independent of the bounded undo snapshots.
class PlateExclusionEvent {
  const PlateExclusionEvent(
      {required this.id,
      required this.wellLabel,
      required this.changedAt,
      required this.source,
      required this.reason,
      required this.beforeExcluded,
      required this.afterExcluded,
      this.beforeResult,
      this.afterResult,
      this.beforeUnit,
      this.afterUnit});

  final String id, wellLabel, reason;
  final DateTime changedAt;
  final ExclusionChangeSource source;
  final bool beforeExcluded, afterExcluded;
  final double? beforeResult, afterResult;
  final String? beforeUnit, afterUnit;

  factory PlateExclusionEvent.fromJson(Map<String, Object?> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid exclusion event $key.');
      }
      return value;
    }

    double? number(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite) {
        throw FormatException('Invalid exclusion event $key.');
      }
      return value.toDouble();
    }

    String? unit(String key) {
      final value = json[key];
      if (value != null && value is! String) {
        throw FormatException('Invalid exclusion event $key.');
      }
      return value as String?;
    }

    final coordinate = text('wellLabel');
    final rawDate = text('changedAt');
    final date = DateTime.tryParse(rawDate);
    final source = ExclusionChangeSource.values
        .where((v) => v.name == json['source'])
        .firstOrNull;
    if (!RegExp(r'^[A-Z]+[1-9][0-9]*$').hasMatch(coordinate) ||
        date == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$')
            .hasMatch(rawDate) ||
        date.toUtc().toIso8601String().substring(0, 19) !=
            rawDate.substring(0, 19) ||
        source == null ||
        json['beforeExcluded'] is! bool ||
        json['afterExcluded'] is! bool ||
        json['beforeExcluded'] == json['afterExcluded']) {
      throw const FormatException(
          'Invalid exclusion event state, coordinate or timestamp.');
    }
    return PlateExclusionEvent(
        id: text('id'),
        wellLabel: coordinate,
        changedAt: date.toUtc(),
        source: source,
        reason: text('reason'),
        beforeExcluded: json['beforeExcluded'] as bool,
        afterExcluded: json['afterExcluded'] as bool,
        beforeResult: number('beforeResult'),
        afterResult: number('afterResult'),
        beforeUnit: unit('beforeUnit'),
        afterUnit: unit('afterUnit'));
  }

  static List<PlateExclusionEvent> parseList(Object? value) {
    final events = jsonObjectList(value, 'exclusionEvents')
        .map(PlateExclusionEvent.fromJson)
        .toList();
    if (events.map((e) => e.id).toSet().length != events.length) {
      throw const FormatException('Duplicate exclusion event ID.');
    }
    return events;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'wellLabel': wellLabel,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'source': source.name,
        'reason': reason,
        'beforeExcluded': beforeExcluded,
        'afterExcluded': afterExcluded,
        'beforeResult': beforeResult,
        'afterResult': afterResult,
        'beforeUnit': beforeUnit,
        'afterUnit': afterUnit,
      };

  static List<PlateExclusionEvent> changes(
      {required List<Well> before,
      required List<Well> after,
      required DateTime at,
      required String actionId,
      required ExclusionChangeSource source,
      required String reason}) {
    final byPosition = {for (final w in before) w.position: w};
    return [
      for (final next in after)
        if (byPosition[next.position] case final old?)
          if (old.excluded != next.excluded)
            PlateExclusionEvent(
                id: '$actionId-${next.label}',
                wellLabel: next.label,
                changedAt: at,
                source: source,
                reason: reason,
                beforeExcluded: old.excluded,
                afterExcluded: next.excluded,
                beforeResult: old.resultValue,
                afterResult: next.resultValue,
                beforeUnit: old.resultUnit,
                afterUnit: next.resultUnit),
    ];
  }
}
