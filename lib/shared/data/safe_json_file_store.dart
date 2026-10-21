import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local_data_recovery_events.dart';

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

typedef LocalDataRecoverySink = void Function(LocalDataRecoveryEvent event);

class SafeJsonFileStore {
  const SafeJsonFileStore({this.recoverySink});

  // Shared across repository instances in the app isolate.
  static final _pending = <String, Future<void>>{};
  final LocalDataRecoverySink? recoverySink;

  Future<Object?> read(
    File file, {
    bool Function(Object? decoded)? validator,
  }) => _serialize(file, () => _read(file, validator));

  Future<T> _serialize<T>(File file, Future<T> Function() action) async {
    final key = file.absolute.uri.normalizePath().toString();
    final previous = _pending[key];
    final completed = Completer<void>();
    _pending[key] = completed.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      completed.complete();
      if (identical(_pending[key], completed.future)) _pending.remove(key);
    }
  }

  /// Read-modify-write must hold the same lock as individual file operations.
  Future<void> update(
    File file,
    Object? Function(Object? current) transform, {
    bool Function(Object? decoded)? validator,
  }) => _serialize(file, () async {
    final current = await _read(file, validator);
    await _write(file, transform(current), validator);
  });

  Future<Object?> _read(
    File file,
    bool Function(Object? decoded)? validator,
  ) async {
    final primaryExists = await file.exists();
    final backup = _backupFile(file);
    final temporary = _temporaryFile(file);
    if (!primaryExists &&
        !await backup.exists() &&
        !await temporary.exists()) {
      return null;
    }

    try {
      return await _decodeAndValidate(file, validator);
    } on Object catch (primaryError) {
      Object? recoveryError;
      // Prefer the last committed backup. A temporary file can recover a
      // first write interrupted before the primary was installed.
      for (final candidate in [backup, temporary]) {
        if (!await candidate.exists()) continue;
        try {
          final decoded = await _decodeAndValidate(candidate, validator);
          await _restorePrimary(file, await candidate.readAsString());
          final event = LocalDataRecoveryEvent(
            filePath: file.path,
            backupPath: candidate.path,
            recoveredAt: DateTime.now().toUtc(),
          );
          _reportRecovery(event);
          return decoded;
        } on Object catch (error) {
          recoveryError = error;
        }
      }
      throw JsonFileCorruptionException(
        filePath: file.path,
        backupPath: backup.path,
        primaryError: primaryError,
        backupError: recoveryError,
      );
    }
  }

  void _reportRecovery(LocalDataRecoveryEvent event) {
    try {
      (recoverySink ?? LocalDataRecoveryEvents.instance.publish)(event);
    } on Object {
      // Recovery must remain successful even if a UI/reporting listener fails.
    }
  }

  Future<void> write(
    File file,
    Object? value, {
    bool Function(Object? decoded)? validator,
  }) => _serialize(file, () => _write(file, value, validator));

  Future<void> _write(
    File file,
    Object? value,
    bool Function(Object? decoded)? validator,
  ) async {
    await file.parent.create(recursive: true);
    final temporary = _temporaryFile(file);
    final backup = _backupFile(file);
    final encoded = jsonEncode(value);

    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsString(encoded, flush: true);
    await _decodeAndValidate(temporary, validator);

    if (await file.exists()) {
      final primaryIsValid = await _isValidJson(file, validator);
      if (primaryIsValid) {
        // Keep the primary in place until the new file is ready. Never leave
        // a gap between moving away the primary and installing its replacement.
        final backupTemporary = File('${backup.path}.tmp');
        await backupTemporary.writeAsString(
          await file.readAsString(),
          flush: true,
        );
        await backupTemporary.rename(backup.path);
      } else {
        await _preservePrimary(file);
      }
    }

    await temporary.rename(file.path);
  }

  Future<void> delete(File file) => _serialize(file, () async {
    // Remove recovery candidates first so an interrupted deletion cannot
    // resurrect an already deleted primary.
    for (final candidate in [
      _backupFile(file),
      File('${file.path}.bak.tmp'),
      _temporaryFile(file),
      File('${file.path}.recovery.tmp'),
      file,
    ]) {
      if (await candidate.exists()) {
        await candidate.delete();
      }
    }
  });

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
    final temporary = File('${file.path}.recovery.tmp');
    if (await temporary.exists()) {
      await temporary.delete();
    }
    await temporary.writeAsString(encodedBackup, flush: true);
    await _decode(temporary);
    if (await file.exists()) await _preservePrimary(file);
    await temporary.rename(file.path);
    final pendingWrite = _temporaryFile(file);
    if (await pendingWrite.exists()) await pendingWrite.delete();
  }

  Future<void> _preservePrimary(File file) async {
    await file.copy(
      '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  File _backupFile(File file) => File('${file.path}.bak');

  File _temporaryFile(File file) => File('${file.path}.tmp');
}
