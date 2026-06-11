import 'dart:convert';
import 'dart:io';

class JsonFileCorruptionException implements IOException {
  const JsonFileCorruptionException({
    required this.filePath,
    required this.backupPath,
    required this.primaryError,
    this.backupError,
  });

  final String filePath;
  final String backupPath;
  final Object primaryError;
  final Object? backupError;

  @override
  String toString() {
    final backupMessage = backupError == null
        ? 'No usable backup was found.'
        : 'Backup error: $backupError';
    return 'Could not read JSON file $filePath. Primary error: '
        '$primaryError. $backupMessage';
  }
}

class SafeJsonFileStore {
  const SafeJsonFileStore();

  Future<Object?> read(
    File file, {
    bool Function(Object? decoded)? validator,
  }) async {
    if (!await file.exists()) {
      return null;
    }

    try {
      return await _decodeAndValidate(file, validator);
    } on Object catch (primaryError) {
      final backup = _backupFile(file);
      if (await backup.exists()) {
        try {
          final decoded = await _decodeAndValidate(backup, validator);
          await _restorePrimary(file, await backup.readAsString());
          return decoded;
        } on Object catch (backupError) {
          throw JsonFileCorruptionException(
            filePath: file.path,
            backupPath: backup.path,
            primaryError: primaryError,
            backupError: backupError,
          );
        }
      }
      throw JsonFileCorruptionException(
        filePath: file.path,
        backupPath: backup.path,
        primaryError: primaryError,
      );
    }
  }

  Future<void> write(
    File file,
    Object? value, {
    bool Function(Object? decoded)? validator,
  }) async {
    await file.parent.create(recursive: true);
    final temporary = _temporaryFile(file);
    final backup = _backupFile(file);
    final encoded = jsonEncode(value);

    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsString(encoded, flush: true);
    await _decodeAndValidate(temporary, validator);

    var rotatedPrimary = false;
    if (await file.exists()) {
      final primaryIsValid = await _isValidJson(file, validator);
      if (primaryIsValid) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename(backup.path);
        rotatedPrimary = true;
      } else {
        await file.delete();
      }
    }

    try {
      await temporary.rename(file.path);
    } on Object {
      if (rotatedPrimary && !await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    }
  }

  Future<void> delete(File file) async {
    for (final candidate in [file, _backupFile(file), _temporaryFile(file)]) {
      if (await candidate.exists()) {
        await candidate.delete();
      }
    }
  }

  Future<Object?> _decodeAndValidate(
    File file,
    bool Function(Object? decoded)? validator,
  ) async {
    final decoded = await _decode(file);
    if (validator != null && !validator(decoded)) {
      throw const FormatException(
        'JSON data does not match the expected schema.',
      );
    }
    return decoded;
  }

  Future<Object?> _decode(File file) async {
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      throw const FormatException('JSON file is empty.');
    }
    return jsonDecode(raw);
  }

  Future<bool> _isValidJson(
    File file,
    bool Function(Object? decoded)? validator,
  ) async {
    try {
      await _decodeAndValidate(file, validator);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _restorePrimary(File file, String encodedBackup) async {
    final temporary = _temporaryFile(file);
    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsString(encodedBackup, flush: true);
    await _decode(temporary);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  File _backupFile(File file) => File('${file.path}.bak');

  File _temporaryFile(File file) => File('${file.path}.tmp');
}
