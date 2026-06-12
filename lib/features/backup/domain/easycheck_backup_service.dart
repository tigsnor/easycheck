import 'dart:convert';

import '../../experiments/domain/experiment.dart';
import '../../plates/domain/plate.dart';

class EasyCheckBackup {
  const EasyCheckBackup({
    required this.schemaVersion,
    required this.exportedAt,
    required this.experiments,
    required this.plates,
  });

  final int schemaVersion;
  final DateTime exportedAt;
  final List<Experiment> experiments;
  final List<Plate> plates;
}

class EasyCheckBackupService {
  const EasyCheckBackupService();

  static const currentSchemaVersion = 1;

  String encode({
    required List<Experiment> experiments,
    required List<Plate> plates,
    DateTime? exportedAt,
  }) {
    final experimentIds = experiments.map((item) => item.id).toSet();
    final orphanPlates = plates
        .where((plate) => !experimentIds.contains(plate.experimentId))
        .toList();
    if (orphanPlates.isNotEmpty) {
      final orphanPlate = orphanPlates.first;
      throw ArgumentError(
        'Plate ${orphanPlate.id} has no matching experiment.',
      );
    }

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'easycheck-backup',
      'schemaVersion': currentSchemaVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'experiments': experiments.map((item) => item.toJson()).toList(),
      'plates': plates.map((item) => item.toJson()).toList(),
    });
  }

  EasyCheckBackup decode(String source) {
    if (source.trim().isEmpty) {
      throw const FormatException('백업 JSON이 비어 있습니다.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('올바른 JSON 형식이 아닙니다.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('백업의 최상위 값은 JSON object여야 합니다.');
    }
    if (decoded['format'] != 'easycheck-backup') {
      throw const FormatException('EasyCheck 백업 파일이 아닙니다.');
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int || schemaVersion < 1) {
      throw const FormatException('백업 schemaVersion이 올바르지 않습니다.');
    }
    if (schemaVersion > currentSchemaVersion) {
      throw FormatException(
        '이 앱보다 새로운 백업 버전입니다. 앱을 업데이트한 뒤 다시 시도하세요. ($schemaVersion)',
      );
    }

    try {
      final experiments = _mapList(
        decoded['experiments'],
        'experiments',
      ).map(Experiment.fromJson).toList();
      final plates = _mapList(
        decoded['plates'],
        'plates',
      ).map(Plate.fromJson).toList();
      final exportedAt = DateTime.parse(decoded['exportedAt'] as String);
      _validateUniqueIds(experiments, plates);
      _validatePlateReferences(experiments, plates);
      return EasyCheckBackup(
        schemaVersion: schemaVersion,
        exportedAt: exportedAt,
        experiments: experiments,
        plates: plates,
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('백업 데이터 구조가 올바르지 않습니다: $error');
    }
  }

  List<Map<String, Object?>> _mapList(Object? value, String field) {
    if (value is! List) {
      throw FormatException('$field 항목이 배열이 아닙니다.');
    }
    return value.map((item) {
      if (item is! Map) {
        throw FormatException('$field 배열에 object가 아닌 값이 있습니다.');
      }
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  void _validateUniqueIds(List<Experiment> experiments, List<Plate> plates) {
    if (experiments.map((item) => item.id).toSet().length !=
        experiments.length) {
      throw const FormatException('중복된 실험 ID가 있습니다.');
    }
    if (plates.map((item) => item.id).toSet().length != plates.length) {
      throw const FormatException('중복된 Plate ID가 있습니다.');
    }
    if (plates.map((item) => item.experimentId).toSet().length !=
        plates.length) {
      throw const FormatException('한 실험에 Plate가 두 개 이상 포함되어 있습니다.');
    }
  }

  void _validatePlateReferences(
    List<Experiment> experiments,
    List<Plate> plates,
  ) {
    final experimentIds = experiments.map((item) => item.id).toSet();
    if (plates.any((plate) => !experimentIds.contains(plate.experimentId))) {
      throw const FormatException('연결된 실험이 없는 Plate가 있습니다.');
    }
  }
}
