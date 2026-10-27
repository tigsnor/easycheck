import 'dart:typed_data';
import 'dart:ui';

import 'package:easycheck/features/attachments/data/attachment_exchange_service.dart';
import 'package:easycheck/features/attachments/data/attachment_file_store.dart';
import 'package:easycheck/features/attachments/domain/experiment_attachment.dart';
import 'package:easycheck/features/experiments/domain/experiment.dart';
import 'package:easycheck/shared/services/document_exchange_service.dart';

AttachmentBlob attachmentBlob([String text = 'reader original,0.75\n']) =>
    AttachmentBlob(text.codeUnits);
ExperimentAttachment attachment(
    {AttachmentBlob? blob,
    String id = 'a',
    AttachmentScope scope = AttachmentScope.experiment,
    String? well,
    String name = 'reader.csv'}) {
  final data = blob ?? attachmentBlob();
  return ExperimentAttachment(
      id: id,
      fileName: name,
      digest: data.digest,
      byteLength: data.bytes.length,
      addedAt: DateTime.utc(2026, 10, 26),
      description: '원본 장비 결과',
      scope: scope,
      wellLabel: well);
}

Experiment attachedExperiment(
        {String id = 'e', List<ExperimentAttachment>? attachments}) =>
    Experiment(
        id: id,
        title: 'Assay',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        attachments: attachments ?? [attachment()]);

class MemoryAttachmentStore implements AttachmentFileStore {
  final files = <String, Uint8List>{};
  bool failWrite = false;
  int writes = 0;
  @override
  Future<void> write(AttachmentBlob blob) async {
    writes++;
    if (failWrite) throw StateError('disk full');
    files[blob.digest] = blob.bytes;
  }

  @override
  Future<Uint8List> read(ExperimentAttachment attachment) async {
    final data = files[attachment.digest];
    if (data == null) throw StateError('missing original');
    return data;
  }
}

class FakeAttachmentExchange implements AttachmentExchangeService {
  PickedAttachment? picked;
  Uint8List? sharedBytes;
  String? sharedName;
  int picks = 0;
  bool? imageOnly;
  @override
  Future<PickedAttachment?> pick({required bool imageOnly}) async {
    picks++;
    this.imageOnly = imageOnly;
    return picked;
  }

  @override
  Future<DocumentShareStatus> share(
      {required String name, required Uint8List bytes, Rect? origin}) async {
    sharedName = name;
    sharedBytes = bytes;
    return DocumentShareStatus.success;
  }
}
