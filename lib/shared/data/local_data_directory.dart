import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'safe_json_file_store.dart';

/// Keeps repository operations and recovery activation ordered in this isolate.
/// A complete recovery generation is published with a single pointer-file rename.
class LocalDataDirectory {
  static const pointerName = 'platenote-storage.json';
  static const generationsName = '.platenote-restores';
  static const readyName = 'ready.json';
  static final _pending = <String, Future<void>>{};

  static Future<T> exclusive<T>(
    String? rootDirectory,
    Future<T> Function(Directory root) action,
  ) async {
    final root = rootDirectory == null
        ? await getApplicationDocumentsDirectory()
        : Directory(rootDirectory);
    final key = root.absolute.uri.normalizePath().toString();
    final previous = _pending[key];
    final completed = Completer<void>();
    _pending[key] = completed.future;
    try {
      if (previous != null) await previous;
      return await action(root);
    } finally {
      completed.complete();
      if (identical(_pending[key], completed.future)) _pending.remove(key);
    }
  }

  static Future<T> access<T>(
    String? rootDirectory,
    Future<T> Function(Directory active) action,
  ) =>
      exclusive(rootDirectory, (root) async => action(await active(root)));

  static bool validPointer(Object? value) =>
      value is Map &&
      value['schemaVersion'] == 1 &&
      value['generation'] is String &&
      RegExp(r'^restore-[A-Za-z0-9-]+$')
          .hasMatch(value['generation'] as String);

  static Future<void> publish(
      Directory root, String generation, SafeJsonFileStore store) async {
    final pointer = File('${root.path}/$pointerName');
    // .next is deliberately not a read-recovery candidate for the pointer.
    // Failed preparation must never be activated on the following app start.
    final next = File('${pointer.path}.next');
    await store.write(next, {'schemaVersion': 1, 'generation': generation},
        validator: validPointer);
    if (await pointer.exists()) {
      await pointer.copy(
          '${pointer.path}.previous-${DateTime.now().microsecondsSinceEpoch}');
    }
    await next.rename(pointer.path);
  }

  /// Call while holding [exclusive]; never infer an empty dataset from a broken
  /// pointer or a missing generation.
  static Future<Directory> active(Directory root) async {
    final pointer = await const SafeJsonFileStore().read(
      File('${root.path}/$pointerName'),
      validator: validPointer,
    );
    if (pointer == null) return root;
    final name = (pointer as Map)['generation'] as String;
    final directory = Directory('${root.path}/$generationsName/$name');
    final ready = File('${directory.path}/$readyName');
    if (!await directory.exists() || !await ready.exists()) {
      throw const FormatException('복구 데이터 폴더가 없거나 준비되지 않았습니다.');
    }
    return directory;
  }
}
