import 'dart:convert';

import '../../../shared/data/json_validation.dart';
import '../../experiments/domain/experiment.dart';
import '../../plates/domain/plate.dart';
import '../../plates/templates/domain/plate_template.dart';

class EasyCheckBackup {
  const EasyCheckBackup({
    required this.schemaVersion,
    required this.exportedAt,
    required this.experiments,
    required this.plates,
    this.templates = const [],
  });

  final int schemaVersion;
  final DateTime exportedAt;
  final List<Experiment> experiments;
  final List<Plate> plates;
  final List<PlateTemplate> templates;

  bool get includesTemplates => schemaVersion >= 2;
}

class EasyCheckBackupService {
  const EasyCheckBackupService();

  static const backupFormat = 'platenote-backup';
  static const legacyBackupFormat = 'easycheck-backup';
  static const currentSchemaVersion = 3;

  String encode({
    required List<Experiment> experiments,
    required List<Plate> plates,
    List<PlateTemplate> templates = const [],
    DateTime? exportedAt,
  }) {
    final backup = EasyCheckBackup(
      schemaVersion: currentSchemaVersion,
      exportedAt: exportedAt ?? DateTime.now(),
      experiments: experiments,
      plates: plates,
      templates: templates,
    );
    validate(backup);
    return const JsonEncoder.withIndent('  ').convert({
      'format': backupFormat,
      'schemaVersion': backup.schemaVersion,
      'exportedAt': backup.exportedAt.toUtc().toIso8601String(),
      'experiments': experiments.map((item) => item.toJson()).toList(),
      'plates': plates.map((item) => item.toJson()).toList(),
      'templates': templates.map((item) => item.toJson()).toList(),
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
    if (decoded['format'] != backupFormat &&
        decoded['format'] != legacyBackupFormat) {
      throw const FormatException('PlateNote 백업 파일이 아닙니다.');
    }
    final version = decoded['schemaVersion'];
    if (version is! int || version < 1 || version > currentSchemaVersion) {
      throw const FormatException('지원하지 않는 백업 버전입니다. 앱 버전을 확인해주세요.');
    }
    try {
      final backup = EasyCheckBackup(
        schemaVersion: version,
        exportedAt: DateTime.parse(decoded['exportedAt'] as String),
        experiments: jsonObjectList(decoded['experiments'], 'experiments',
                required: true)
            .map(Experiment.fromJson)
            .toList(),
        plates: jsonObjectList(decoded['plates'], 'plates', required: true)
            .map(Plate.fromJson)
            .toList(),
        templates: version >= 2
            ? jsonObjectList(decoded['templates'], 'templates', required: true)
                .map(PlateTemplate.fromJson)
                .toList()
            : const [],
      );
      validate(backup);
      return backup;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('백업 데이터 구조가 올바르지 않습니다: $error');
    }
  }

  /// Also validates programmatically constructed backups before any writes.
  void validate(EasyCheckBackup backup) {
    if (backup.schemaVersion < 1 ||
        backup.schemaVersion > currentSchemaVersion ||
        (!backup.includesTemplates && backup.templates.isNotEmpty)) {
      throw const FormatException('백업 버전과 데이터 구성이 일치하지 않습니다.');
    }
    void uniqueIds(Iterable<String> ids, String label) {
      final seen = <String>{};
      for (final id in ids) {
        if (id.trim().isEmpty || !seen.add(id)) {
          throw FormatException('$label ID가 비어 있거나 중복되었습니다.');
        }
      }
    }

    uniqueIds(backup.experiments.map((e) => e.id), '실험');
    uniqueIds(backup.plates.map((p) => p.id), 'Plate');
    uniqueIds(backup.plates.map((p) => p.experimentId), 'Plate 연결 실험');
    uniqueIds(backup.templates.map((t) => t.id), '템플릿');
    final ids = backup.experiments.map((e) => e.id).toSet();
    // Plate filenames currently use these normalized IDs. Reject collisions
    // before either merge or replacement can overwrite another experiment.
    final filenames =
        ids.map((id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')).toSet();
    if (filenames.length != ids.length) {
      throw const FormatException('파일 이름이 충돌하는 실험 ID가 있습니다.');
    }
    for (final experiment in backup.experiments) {
      Experiment.fromJson(experiment.toJson());
    }
    for (final plate in backup.plates) {
      if (!ids.contains(plate.experimentId)) {
        throw const FormatException('연결된 실험이 없는 Plate가 있습니다.');
      }
      Plate.fromJson(plate.toJson());
    }
    for (final template in backup.templates) {
      PlateTemplate.fromJson(template.toJson());
    }
    // Catches non-JSON values in optional nested model fields as well.
    jsonEncode([
      ...backup.experiments.map((e) => e.toJson()),
      ...backup.plates.map((p) => p.toJson()),
      ...backup.templates.map((t) => t.toJson()),
    ]);
  }
}
