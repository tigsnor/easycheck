import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../shared/data/safe_json_file_store.dart';
import '../domain/plate_template.dart';
import 'plate_template_repository.dart';

class FilePlateTemplateRepository implements PlateTemplateRepository {
  const FilePlateTemplateRepository({
    this.rootDirectory,
    this.fileStore = const SafeJsonFileStore(),
  });

  static const schemaVersion = 1;

  final String? rootDirectory;
  final SafeJsonFileStore fileStore;

  @override
  Future<List<PlateTemplate>> loadTemplates() async {
    final decoded = await fileStore.read(await _file, validator: _isValidFile);
    if (decoded == null) {
      return [];
    }
    final templates = _records(decoded).map(PlateTemplate.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return templates;
  }

  @override
  Future<void> saveTemplate(PlateTemplate template) async {
    final templates = await loadTemplates();
    final index = templates.indexWhere((item) => item.id == template.id);
    if (index == -1) {
      templates.add(template);
    } else {
      templates[index] = template;
    }
    await _write(templates);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final templates = await loadTemplates();
    templates.removeWhere((template) => template.id == id);
    await _write(templates);
  }

  Future<File> get _file async {
    final directory = rootDirectory == null
        ? await getApplicationDocumentsDirectory()
        : Directory(rootDirectory!);
    return File('${directory.path}/plate_templates.json');
  }

  bool _isValidFile(Object? decoded) {
    try {
      for (final record in _records(decoded)) {
        PlateTemplate.fromJson(record);
      }
      return true;
    } on Object {
      return false;
    }
  }

  List<Map<String, Object?>> _records(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException('Template file must contain an object.');
    }
    final object = Map<String, Object?>.from(decoded);
    if (object['schemaVersion'] != schemaVersion || object['data'] is! List) {
      throw const FormatException('Unsupported template file schema.');
    }
    return (object['data'] as List).map((record) {
      if (record is! Map) {
        throw const FormatException('Template record must be an object.');
      }
      return Map<String, Object?>.from(record);
    }).toList();
  }

  Future<void> _write(List<PlateTemplate> templates) async {
    await fileStore.write(
        await _file,
        {
          'schemaVersion': schemaVersion,
          'data': templates.map((template) => template.toJson()).toList(),
        },
        validator: _isValidFile);
  }
}
