import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/services/document_exchange_service.dart';
import '../domain/experiment_attachment.dart';

class PickedAttachment {
  const PickedAttachment({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

abstract interface class AttachmentExchangeService {
  Future<PickedAttachment?> pick({required bool imageOnly});
  Future<DocumentShareStatus> share(
      {required String name, required Uint8List bytes, Rect? origin});
}

class PlatformAttachmentExchangeService implements AttachmentExchangeService {
  const PlatformAttachmentExchangeService();
  @override
  Future<PickedAttachment?> pick({required bool imageOnly}) async {
    final selection = await FilePicker.pickFiles(
        allowMultiple: false,
        compressionQuality: 0,
        type: imageOnly ? FileType.image : FileType.any);
    if (selection == null || selection.xFiles.isEmpty) return null;
    final file = selection.xFiles.single;
    final size = await file.length();
    if (size <= 0 || size > maxAttachmentBytes) {
      throw const FormatException('파일당 10MB까지 첨부할 수 있습니다.');
    }
    return PickedAttachment(name: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<DocumentShareStatus> share(
      {required String name, required Uint8List bytes, Rect? origin}) async {
    final result = await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes)],
        fileNameOverrides: [name],
        sharePositionOrigin: origin));
    return switch (result.status) {
      ShareResultStatus.success => DocumentShareStatus.success,
      ShareResultStatus.dismissed => DocumentShareStatus.dismissed,
      ShareResultStatus.unavailable => DocumentShareStatus.unavailable,
    };
  }
}
