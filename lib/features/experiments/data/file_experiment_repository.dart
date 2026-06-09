import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/experiment.dart';
import 'experiment_repository.dart';

class FileExperimentRepository implements ExperimentRepository {
  const FileExperimentRepository({this.fileName = 'experiments.json'});

  final String fileName;

  @override
  Future<List<Experiment>> loadExperiments() async {
    final file = await _file;
    if (!await file.exists()) {
      return [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Experiments file must contain a JSON list.');
    }

    final experiments = decoded
        .whereType<Map<String, Object?>>()
        .map(Experiment.fromJson)
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
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$fileName');
  }

  Future<void> _writeExperiments(List<Experiment> experiments) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final encoded = jsonEncode(
      experiments.map((experiment) => experiment.toJson()).toList(),
    );
    await file.writeAsString(encoded, flush: true);
  }
}
