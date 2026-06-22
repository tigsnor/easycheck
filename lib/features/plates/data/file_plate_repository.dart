import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../shared/data/safe_json_file_store.dart';
import '../domain/plate.dart';
import 'plate_repository.dart';

class FilePlateRepository implements PlateRepository {
  const FilePlateRepository({
    this.rootDirectory,
    this.fileStore = const SafeJsonFileStore(),
  });

  static const schemaVersion = 1;

  final String? rootDirectory;
  final SafeJsonFileStore fileStore;

  @override
  Future<void> deletePlate(String experimentId) async {
    await fileStore.delete(await _file(experimentId));
  }

  @override
  Future<Plate?> loadPlate(String experimentId) async {
    final decoded = await fileStore.read(
      await _file(experimentId),
      validator: _isSupportedFile,
    );
    if (decoded == null) {
      return null;
    }

    return Plate.fromJson(_plateFromJson(decoded));
  }

  @override
  Future<void> savePlate(Plate plate) async {
    await fileStore.write(
        await _file(plate.experimentId),
        {
          'schemaVersion': schemaVersion,
          'data': plate.toJson(),
        },
        validator: _isSupportedFile);
  }

  Future<File> _file(String experimentId) async {
    final directory = rootDirectory == null
        ? await getApplicationDocumentsDirectory()
        : Directory(rootDirectory!);
    final safeId = experimentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${directory.path}/plates/$safeId.json');
  }

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
