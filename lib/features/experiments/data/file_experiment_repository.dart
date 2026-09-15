import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../shared/data/safe_json_file_store.dart';
import '../domain/experiment.dart';
import 'experiment_repository.dart';

class FileExperimentRepository implements ExperimentRepository {
  const FileExperimentRepository({
    this.fileName = 'experiments.json',
    this.rootDirectory,
    this.fileStore = const SafeJsonFileStore(),
  });

  static const schemaVersion = 1;

  final String fileName;
  final String? rootDirectory;
  final SafeJsonFileStore fileStore;

  @override
  Future<List<Experiment>> loadExperiments() async {
    final decoded = await fileStore.read(
      await _file,
      validator: _isSupportedFile,
    );
    if (decoded == null) {
      return [];
    }

    final records = _recordsFromJson(decoded);
    final experiments = records
        .map(
          (record) => Experiment.fromJson(Map<String, Object?>.from(record)),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return experiments;
  }

  @override
  Future<void> saveExperiment(Experiment experiment) async {
    final experiments = await loadExperiments();
    final index = experiments.indexWhere((item) => item.id == experiment.id);

    if (index == -1) {
      experiments.insert(0, experiment);
    } else {
      experiments[index] = experiment;
    }

    await _writeExperiments(experiments);
  }

  @override
  Future<void> deleteExperiment(String id) async {
    final experiments = await loadExperiments();
    experiments.removeWhere((experiment) => experiment.id == id);
    await _writeExperiments(experiments);
  }

  Future<File> get _file async {
    final directory = rootDirectory == null
        ? await getApplicationDocumentsDirectory()
        : Directory(rootDirectory!);
    return File('${directory.path}/$fileName');
  }

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

  Future<void> _writeExperiments(List<Experiment> experiments) async {
    await fileStore.write(
        await _file,
        {
          'schemaVersion': schemaVersion,
          'data': experiments.map((experiment) => experiment.toJson()).toList(),
        },
        validator: _isSupportedFile);
  }
}
