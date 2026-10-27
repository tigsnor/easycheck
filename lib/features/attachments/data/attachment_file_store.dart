import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../shared/data/local_data_directory.dart';
import '../domain/experiment_attachment.dart';

abstract interface class AttachmentFileStore {
  Future<void> write(AttachmentBlob blob);
  Future<Uint8List> read(ExperimentAttachment attachment);
}

class FileAttachmentFileStore implements AttachmentFileStore {
  const FileAttachmentFileStore({this.rootDirectory});
  final String? rootDirectory;

  @override
  Future<void> write(AttachmentBlob blob) =>
      LocalDataDirectory.access(rootDirectory, (directory) async {
        final file = File('${directory.path}/attachments/${blob.digest}.bin');
        await file.parent.create(recursive: true);
        if (await file.exists() &&
            await file.length() == blob.bytes.length &&
            sha256.convert(await file.readAsBytes()).toString() ==
                blob.digest) {
          return;
        }
        // Commit the verified binary before publishing any metadata that refers to it.
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(blob.bytes, flush: true);
        if (sha256.convert(await temporary.readAsBytes()).toString() !=
            blob.digest) {
          throw const FileSystemException('첨부 원본 저장 검증에 실패했습니다.');
        }
        if (await file.exists()) {
          await file.copy(
              '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}');
        }
        await temporary.rename(file.path);
      });

  @override
  Future<Uint8List> read(ExperimentAttachment attachment) =>
      LocalDataDirectory.access(rootDirectory, (directory) async {
        ExperimentAttachment.fromJson(attachment.toJson());
        final file =
            File('${directory.path}/attachments/${attachment.digest}.bin');
        if (!await file.exists() ||
            await file.length() != attachment.byteLength) {
          throw FileSystemException(
              '${attachment.fileName}: 원본이 없거나 크기가 다릅니다. 백업에서 복원해주세요.');
        }
        final bytes = await file.readAsBytes();
        if (sha256.convert(bytes).toString() != attachment.digest) {
          throw FileSystemException(
              '${attachment.fileName}: 원본이 손상되었습니다. 백업에서 복원해주세요.');
        }
        return bytes;
      });
}
