import 'dart:io';

import '../../../shared/data/local_data_directory.dart';

import '../../../shared/data/safe_json_file_store.dart';
import '../domain/plate.dart';
import 'plate_repository.dart';

class FilePlateRepository implements PlateRepository {
  const FilePlateRepository({
    this.rootDirectory,
    this.fileStore = const SafeJsonFileStore(),
  });

  static const schemaVersion = 2;

  final String? rootDirectory;
  final SafeJsonFileStore fileStore;

  @override
  Future<void> deletePlate(String experimentId) =>
      _withFile(experimentId, fileStore.delete);

  @override
  Future<Plate?> loadPlate(String experimentId) =>
      _withFile(experimentId, (file) async {
        final decoded = await fileStore.read(
          file,
          validator: _isSupportedFile,
        );
        if (decoded == null) {
          return null;
        }

        return Plate.fromJson(_plateFromJson(decoded));
      });

  @override
  Future<void> savePlate(Plate plate) =>
      _withFile(plate.experimentId, (file) async {
        await fileStore.write(
            file,
            {
              'schemaVersion': schemaVersion,
              'data': plate.toJson(),
            },
            validator: _isSupportedFile);
      });

  Future<T> _withFile<T>(
          String experimentId, Future<T> Function(File file) action) =>
      LocalDataDirectory.access(rootDirectory, (directory) {
        final safeId = experimentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
        return action(File('${directory.path}/plates/$safeId.json'));
      });

  bool _isSupportedFile(Object? decoded) {
    try {
      Plate.fromJson(_plateFromJson(decoded));
      return true;
    } on Object {
      return false;
    }
  }

  Map<String, Object?> _plateFromJson(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException('Plate file must contain a JSON object.');
    }
    final object = Map<String, Object?>.from(decoded);
    if (!object.containsKey('schemaVersion')) {
      return object;
    }

    final version = object['schemaVersion'];
    if (version is! int || version < 1 || version > schemaVersion) {
      throw FormatException('Unsupported plate schema version: $version');
    }
    final data = object['data'];
    if (data is! Map) {
      throw const FormatException('Plate data must be a JSON object.');
    }
    return Map<String, Object?>.from(data);
  }
}
