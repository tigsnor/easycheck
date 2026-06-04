import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/plate.dart';
import 'plate_repository.dart';

class FilePlateRepository implements PlateRepository {
  const FilePlateRepository();

  @override
  Future<Plate?> loadPlate(String experimentId) async {
    final file = await _file(experimentId);
    if (!await file.exists()) {
      return null;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Plate file must contain a JSON object.');
    }

    return Plate.fromJson(decoded);
  }

  @override
  Future<void> savePlate(Plate plate) async {
    final file = await _file(plate.experimentId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(plate.toJson()), flush: true);
  }

  Future<File> _file(String experimentId) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeId = experimentId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${directory.path}/plates/$safeId.json');
  }
}
