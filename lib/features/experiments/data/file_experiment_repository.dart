import 'dart:io';

import '../../../shared/data/local_data_directory.dart';

import '../../../shared/data/safe_json_file_store.dart';
import '../domain/experiment.dart';
import 'experiment_repository.dart';

class FileExperimentRepository implements ExperimentRepository {
  const FileExperimentRepository({
    this.fileName = 'experiments.json',
    this.rootDirectory,
    this.fileStore = const SafeJsonFileStore(),
  });

  static const schemaVersion = 2;

  final String fileName;
  final String? rootDirectory;
  final SafeJsonFileStore fileStore;

  @override
  Future<List<Experiment>> loadExperiments() => _withFile((file) async {
        final decoded = await fileStore.read(
          file,
          validator: _isSupportedFile,
        );
        if (decoded == null) {
          return [];
        }

        final records = _recordsFromJson(decoded);
        final experiments = records
            .map(
              (record) =>
                  Experiment.fromJson(Map<String, Object?>.from(record)),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return experiments;
      });

  @override
  Future<void> saveExperiment(Experiment experiment) async {
    await _updateExperiments((experiments) {
      final index = experiments.indexWhere((item) => item.id == experiment.id);
      if (index == -1) {
        experiments.insert(0, experiment);
      } else {
        experiments[index] = experiment;
      }
    });
  }

  @override
  Future<void> deleteExperiment(String id) async {
    await _updateExperiments(
      (experiments) =>
          experiments.removeWhere((experiment) => experiment.id == id),
    );
  }

  Future<T> _withFile<T>(Future<T> Function(File file) action) =>
      LocalDataDirectory.access(rootDirectory,
          (directory) => action(File('${directory.path}/$fileName')));

  bool _isSupportedFile(Object? decoded) {
    try {
      final records = _recordsFromJson(decoded);
      for (final record in records) {
        Experiment.fromJson(record);
      }
      return true;
    } on Object {
      return false;
    }
  }

  List<Map<String, Object?>> _recordsFromJson(Object? decoded) {
    if (decoded is List) {
      return _mapRecords(decoded);
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Experiments file must contain a JSON list or versioned object.',
      );
    }

    final envelope = Map<String, Object?>.from(decoded);
    final version = envelope['schemaVersion'];
    if (version is! int || version < 1 || version > schemaVersion) {
      throw FormatException('Unsupported experiments schema version: $version');
    }
    final data = envelope['data'];
    if (data is! List) {
      throw const FormatException('Experiments data must be a JSON list.');
    }
    return _mapRecords(data);
  }

  List<Map<String, Object?>> _mapRecords(List<Object?> records) {
    return records.map((record) {
      if (record is! Map) {
        throw const FormatException(
          'Every experiment record must be a JSON object.',
        );
      }
      return Map<String, Object?>.from(record);
    }).toList();
  }

  Future<void> _updateExperiments(
    void Function(List<Experiment>) mutate,
  ) =>
      _withFile((file) async {
        await fileStore.update(
          file,
          (current) {
            final experiments = current == null
                ? <Experiment>[]
                : _recordsFromJson(current).map(Experiment.fromJson).toList();
            mutate(experiments);
            return {
              'schemaVersion': schemaVersion,
              'data':
                  experiments.map((experiment) => experiment.toJson()).toList(),
            };
          },
          validator: _isSupportedFile,
        );
      });
}
