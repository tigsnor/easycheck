import 'dart:io';

import '../../../shared/data/local_data_directory.dart';
import '../../../shared/data/safe_json_file_store.dart';
import '../../plates/domain/plate.dart';
import '../domain/experiment.dart';

class DeletedExperiment {
  const DeletedExperiment(
      {required this.experiment, required this.plate, required this.deletedAt});
  final Experiment experiment;
  final Plate? plate;
  final DateTime deletedAt;

  Map<String, Object?> toJson() => {
        'experiment': experiment.toJson(),
        'plate': plate?.toJson(),
        'deletedAt': deletedAt.toUtc().toIso8601String(),
      };
  factory DeletedExperiment.fromJson(Map<String, Object?> json) =>
      DeletedExperiment(
        experiment: Experiment.fromJson(
            Map<String, Object?>.from(json['experiment'] as Map)),
        plate: json['plate'] == null
            ? null
            : Plate.fromJson(Map<String, Object?>.from(json['plate'] as Map)),
        deletedAt: DateTime.parse(json['deletedAt'] as String),
      );
}

abstract class DeletedExperimentRepository {
  Future<List<DeletedExperiment>> load();
  Future<void> save(DeletedExperiment entry);
  Future<void> remove(String experimentId);
}

/// Deletion snapshots are saved before removing live data and survive restart.
/// Attachment blobs remain in the existing attachment store.
class FileDeletedExperimentRepository implements DeletedExperimentRepository {
  const FileDeletedExperimentRepository({this.rootDirectory});
  final String? rootDirectory;
  static const _store = SafeJsonFileStore();

  List<DeletedExperiment> _decode(Object? value) {
    if (value == null) return [];
    final json = Map<String, Object?>.from(value as Map);
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported deleted records version');
    }
    return (json['data'] as List)
        .map((e) =>
            DeletedExperiment.fromJson(Map<String, Object?>.from(e as Map)))
        .toList();
  }

  bool _valid(Object? value) {
    try {
      _decode(value);
      return value != null;
    } on Object {
      return false;
    }
  }

  Future<T> _withFile<T>(Future<T> Function(File) action) =>
      LocalDataDirectory.access(
          rootDirectory,
          (directory) =>
              action(File('${directory.path}/deleted_experiments.json')));
  @override
  Future<List<DeletedExperiment>> load() => _withFile(
      (file) async => _decode(await _store.read(file, validator: _valid)));
  Future<void> _update(void Function(List<DeletedExperiment>) mutate) =>
      _withFile((file) => _store.update(file, (current) {
            final entries = _decode(current);
            mutate(entries);
            return {
              'schemaVersion': 1,
              'data': entries.map((e) => e.toJson()).toList()
            };
          }, validator: _valid));
  @override
  Future<void> save(DeletedExperiment entry) => _update((entries) {
        entries.removeWhere((e) => e.experiment.id == entry.experiment.id);
        entries.insert(0, entry);
      });
  @override
  Future<void> remove(String experimentId) => _update(
      (entries) => entries.removeWhere((e) => e.experiment.id == experimentId));
}
