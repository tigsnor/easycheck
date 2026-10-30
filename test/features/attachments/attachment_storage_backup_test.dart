import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easycheck/features/attachments/data/attachment_file_store.dart';
import 'package:easycheck/features/attachments/domain/experiment_attachment.dart';
import 'package:easycheck/features/backup/application/backup_restore_service.dart';
import 'package:easycheck/features/backup/data/file_backup_recovery_service.dart';
import 'package:easycheck/features/backup/domain/easycheck_backup_service.dart';
import 'package:easycheck/features/experiments/application/experiment_duplication_service.dart';
import 'package:easycheck/features/experiments/data/file_experiment_repository.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/features/plates/data/file_plate_repository.dart';
import 'package:easycheck/features/plates/domain/plate.dart';
import 'package:easycheck/shared/data/local_data_directory.dart';
import 'package:easycheck/shared/data/safe_json_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/attachment_fixture.dart';

void main() {
  const codec = EasyCheckBackupService();
  late Directory root;
  late FileAttachmentFileStore files;
  late FileExperimentRepository experiments;
  late FilePlateRepository plates;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('platenote-attachments-');
    files = FileAttachmentFileStore(rootDirectory: root.path);
    experiments = FileExperimentRepository(rootDirectory: root.path);
    plates = FilePlateRepository(rootDirectory: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  EasyCheckBackup backup({List<Experiment>? entries}) =>
      codec.decode(codec.encode(
          experiments: entries ?? [attachedExperiment()],
          plates: [],
          attachmentFiles: {attachmentBlob().digest: attachmentBlob()}));

  test(
      'stores immutable original bytes, deduplicates, and survives source removal and restart',
      () async {
    final source = File('${root.path}/reader.csv');
    await source.writeAsString('reader original,0.75\n');
    final input = await source.readAsBytes();
    final blob = AttachmentBlob(input);
    input[0] = 0;
    await files.write(blob);
    await files.write(blob);
    await source.delete();
    await experiments.saveExperiment(attachedExperiment());
    final loaded = (await FileExperimentRepository(rootDirectory: root.path)
            .loadExperiments())
        .single;
    expect(
        await FileAttachmentFileStore(rootDirectory: root.path)
            .read(loaded.attachments.single),
        blob.bytes);
    expect((await Directory('${root.path}/attachments').list().toList()).length,
        1);
  });

  test(
      'detects missing, truncated and same-size altered originals and repairs from verified bytes',
      () async {
    await files.write(attachmentBlob());
    final file =
        File('${root.path}/attachments/${attachmentBlob().digest}.bin');
    final altered = Uint8List.fromList(attachmentBlob().bytes);
    altered[0] ^= 1;
    await file.writeAsBytes(altered);
    await expectLater(
        files.read(attachment()), throwsA(isA<FileSystemException>()));
    await files.write(attachmentBlob());
    expect(await files.read(attachment()), attachmentBlob().bytes);
    await file.writeAsString('short');
    await expectLater(
        files.read(attachment()), throwsA(isA<FileSystemException>()));
    await file.delete();
    await expectLater(
        files.read(attachment()), throwsA(isA<FileSystemException>()));
  });

  test('rejects unsafe metadata, duplicate IDs and unsupported sizes', () {
    final json = attachment().toJson();
    for (final bad in [
      {...json, 'digest': '../../outside'},
      {...json, 'fileName': '../secret'},
      {...json, 'fileName': '..'},
      {...json, 'byteLength': 0},
      {...json, 'byteLength': maxAttachmentBytes + 1},
      {...json, 'scope': 'unknown'},
      {...json, 'scope': 'well', 'wellLabel': null},
    ]) {
      expect(() => ExperimentAttachment.fromJson(bad), throwsFormatException);
    }
    expect(
        () => Experiment.fromJson({
              ...attachedExperiment().toJson(),
              'attachments': [json, json]
            }),
        throwsFormatException);
    expect(() => AttachmentBlob([]), throwsFormatException);
    expect(() => AttachmentBlob(Uint8List(maxAttachmentBytes + 1)),
        throwsFormatException);
  });

  test(
      'backup includes exact bytes, deduplicates payloads and validates every reference',
      () {
    final a = attachment(scope: AttachmentScope.well, well: 'H12');
    final b = attachment(id: 'b', name: 'same-original.csv');
    final value = codec.decode(codec.encode(experiments: [
      attachedExperiment(attachments: [a, b])
    ], plates: [
      Plate(id: 'p', experimentId: 'e', name: 'P')
    ], attachmentFiles: {
      attachmentBlob().digest: attachmentBlob()
    }));
    expect(value.schemaVersion, 7);
    expect(value.attachmentCount, 2);
    expect(value.attachmentFiles, hasLength(1));
    expect(value.attachmentFiles.values.single.bytes, attachmentBlob().bytes);
    expect(value.experiments.single.attachments.first.wellLabel, 'H12');
    expect(() => codec.encode(experiments: [attachedExperiment()], plates: []),
        throwsFormatException);
    expect(
        () => codec.encode(experiments: [
              attachedExperiment(attachments: [a])
            ], plates: [], attachmentFiles: {
              attachmentBlob().digest: attachmentBlob()
            }),
        throwsFormatException);
  });

  test(
      'rejects corrupt, missing and unreferenced backup payloads before writing',
      () async {
    await experiments.saveExperiment(attachedExperiment(attachments: []));
    final original = jsonDecode(codec.encode(
            experiments: [attachedExperiment()],
            plates: [],
            attachmentFiles: {attachmentBlob().digest: attachmentBlob()}))
        as Map<String, dynamic>;
    for (final payload in [
      null,
      {},
      {attachmentBlob().digest: 'not base64'},
      {attachmentBlob().digest: base64Encode('corrupt'.codeUnits)},
      {
        '../x': base64Encode([1])
      },
      {
        attachmentBlob().digest: base64Encode(attachmentBlob().bytes),
        attachmentBlob('unused').digest: base64Encode('unused'.codeUnits)
      }
    ]) {
      expect(
          () => codec
              .decode(jsonEncode({...original, 'attachmentFiles': payload})),
          throwsFormatException);
    }
    expect((await experiments.loadExperiments()).single.attachments, isEmpty);
    expect(await Directory('${root.path}/attachments').exists(), false);
  });

  test(
      'fresh installation recovery restores files and metadata before activation',
      () async {
    await FileBackupRecoveryService(rootDirectory: root.path).recover(backup());
    final loaded = (await experiments.loadExperiments()).single;
    expect(await files.read(loaded.attachments.single), attachmentBlob().bytes);
    final active = await LocalDataDirectory.access(root.path, (d) async => d);
    expect(active.path, contains('restore-'));
    await files.write(attachmentBlob('after recovery'));
    expect(
        await File(
                '${active.path}/attachments/${attachmentBlob('after recovery').digest}.bin')
            .exists(),
        true);
  });

  test('failed activation preserves old attachment metadata and bytes',
      () async {
    final oldBlob = attachmentBlob('old original');
    final old = attachedExperiment(attachments: [attachment(blob: oldBlob)]);
    await files.write(oldBlob);
    await experiments.saveExperiment(old);
    await expectLater(
        FileBackupRecoveryService(
                rootDirectory: root.path, fileStore: _FailActivation())
            .recover(backup()),
        throwsStateError);
    final loaded = (await experiments.loadExperiments()).single;
    expect(loaded.attachments.single.digest, oldBlob.digest);
    expect(await files.read(loaded.attachments.single), oldBlob.bytes);
  });

  test(
      'merge writes originals before metadata and preserves unrelated attachments',
      () async {
    final oldBlob = attachmentBlob('unrelated');
    await files.write(oldBlob);
    await experiments.saveExperiment(attachedExperiment(
        id: 'other', attachments: [attachment(blob: oldBlob)]));
    await BackupRestoreService(
            experimentRepository: experiments,
            plateRepository: plates,
            attachmentFileStore: files)
        .restore(backup());
    for (final e in await experiments.loadExperiments()) {
      expect(await files.read(e.attachments.single),
          e.id == 'e' ? attachmentBlob().bytes : oldBlob.bytes);
    }
  });

  test('binary write failure cannot publish new metadata', () async {
    await experiments.saveExperiment(attachedExperiment(attachments: []));
    await expectLater(
        BackupRestoreService(
                experimentRepository: experiments,
                plateRepository: plates,
                attachmentFileStore: MemoryAttachmentStore()..failWrite = true)
            .restore(backup()),
        throwsStateError);
    expect((await experiments.loadExperiments()).single.attachments, isEmpty);
  });

  test(
      'later merge failure rolls back references and retains old original bytes',
      () async {
    final oldBlob = attachmentBlob('old original');
    await files.write(oldBlob);
    await experiments.saveExperiment(
        attachedExperiment(attachments: [attachment(blob: oldBlob)]));
    final incoming = EasyCheckBackup(
        schemaVersion: 4,
        exportedAt: DateTime.now(),
        experiments: [attachedExperiment()],
        plates: [Plate(id: 'p', experimentId: 'e', name: 'Incoming')],
        attachmentFiles: {attachmentBlob().digest: attachmentBlob()});
    await expectLater(
        BackupRestoreService(
                experimentRepository: experiments,
                plateRepository: _FailPlate(root.path),
                attachmentFileStore: files)
            .restore(incoming),
        throwsA(isA<BackupRestoreException>()));
    final restored =
        (await experiments.loadExperiments()).single.attachments.single;
    expect(restored.digest, oldBlob.digest);
    expect(await files.read(restored), oldBlob.bytes);
  });

  test(
      'legacy backups remain readable and design duplication does not copy attachments',
      () async {
    final json = jsonDecode(codec.encode(
        experiments: [attachedExperiment(attachments: [])],
        plates: [])) as Map<String, dynamic>;
    for (final version in [1, 2, 3]) {
      json['schemaVersion'] = version;
      json.remove('attachmentFiles');
      expect(codec.decode(jsonEncode(json)).experiments.single.attachments,
          isEmpty);
    }
    await experiments.saveExperiment(attachedExperiment());
    final copy = await ExperimentDuplicationService(
        experimentRepository: experiments,
        plateRepository: plates,
        createId: () => 'copy').duplicateDesign('e');
    expect(copy.attachments, isEmpty);
    expect(
        (await experiments.loadExperiments())
            .firstWhere((e) => e.id == 'e')
            .attachments,
        hasLength(1));
  });

  test('whole-data attachment budget counts shared blobs only once', () {
    final ten = attachment();
    expect(
        () => validateAttachmentBudget(List.filled(100, ten)), returnsNormally);
    final base = attachment().toJson();
    final entries = [
      for (var i = 0; i < 6; i++)
        ExperimentAttachment.fromJson({
          ...base,
          'id': '$i',
          'digest': i.toRadixString(16).padLeft(64, '0'),
          'byteLength': maxAttachmentBytes
        })
    ];
    expect(() => validateAttachmentBudget(entries), throwsFormatException);
  });
}

class _FailActivation extends SafeJsonFileStore {
  @override
  Future<void> write(File file, Object? value,
      {bool Function(Object?)? validator}) async {
    if (file.path.endsWith('${LocalDataDirectory.pointerName}.next')) {
      throw StateError('activation interrupted');
    }
    await super.write(file, value, validator: validator);
  }
}

class _FailPlate extends FilePlateRepository {
  _FailPlate(String root) : super(rootDirectory: root);
  @override
  Future<void> savePlate(Plate plate) async {
    if (plate.name == 'Incoming') throw StateError('plate write failure');
    await super.savePlate(plate);
  }
}
