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
    await _update((templates) {
      final index = templates.indexWhere((item) => item.id == template.id);
      if (index == -1) {
        templates.add(template);
      } else {
        templates[index] = template;
      }
    });
  }

  @override
  Future<void> deleteTemplate(String id) async {
    await _update(
      (templates) => templates.removeWhere((template) => template.id == id),
    );
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

  Future<void> _update(void Function(List<PlateTemplate>) mutate) async {
    await fileStore.update(
      await _file,
      (current) {
        final templates = current == null
            ? <PlateTemplate>[]
            : _records(current).map(PlateTemplate.fromJson).toList();
        mutate(templates);
        return {
          'schemaVersion': schemaVersion,
          'data': templates.map((template) => template.toJson()).toList(),
        };
      },
      validator: _isValidFile,
    );
  }
}
