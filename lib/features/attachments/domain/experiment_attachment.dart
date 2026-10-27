import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../shared/data/json_validation.dart';

enum AttachmentScope { experiment, plate, well }

const maxAttachmentBytes = 10 * 1024 * 1024;
const maxBackupAttachmentBytes = 50 * 1024 * 1024;

class ExperimentAttachment {
  const ExperimentAttachment(
      {required this.id,
      required this.fileName,
      required this.digest,
      required this.byteLength,
      required this.addedAt,
      this.description = '',
      this.observedAt,
      this.scope = AttachmentScope.experiment,
      this.wellLabel});

  final String id;
  final String fileName;
  final String digest;
  final int byteLength;
  final DateTime addedAt;
  final String description;
  final DateTime? observedAt;
  final AttachmentScope scope;
  final String? wellLabel;

  bool get isPreviewableImage =>
      RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false)
          .hasMatch(fileName);
  String get targetLabel => switch (scope) {
        AttachmentScope.experiment => '실험 전체',
        AttachmentScope.plate => 'Plate 전체',
        AttachmentScope.well => 'Well $wellLabel',
      };

  factory ExperimentAttachment.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['fileName'];
    final digest = json['digest'];
    final size = json['byteLength'];
    final scope = AttachmentScope.values
        .where((s) => s.name == json['scope'])
        .firstOrNull;
    final well = json['wellLabel'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 255 ||
        name == '..' ||
        name == '.' ||
        RegExp(r'[/\\\x00-\x1f]').hasMatch(name) ||
        digest is! String ||
        !validAttachmentDigest(digest) ||
        size is! int ||
        size <= 0 ||
        size > maxAttachmentBytes ||
        scope == null ||
        (scope == AttachmentScope.well
            ? well is! String || !RegExp(r'^[A-Z]+[1-9][0-9]*$').hasMatch(well)
            : well != null)) {
      throw const FormatException('첨부파일 정보가 올바르지 않습니다.');
    }
    return ExperimentAttachment(
        id: id,
        fileName: name,
        digest: digest,
        byteLength: size,
        addedAt: DateTime.parse(json['addedAt'] as String).toUtc(),
        description: json['description'] as String? ?? '',
        observedAt: json['observedAt'] == null
            ? null
            : DateTime.parse(json['observedAt'] as String).toUtc(),
        scope: scope,
        wellLabel: well as String?);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'fileName': fileName,
        'digest': digest,
        'byteLength': byteLength,
        'addedAt': addedAt.toUtc().toIso8601String(),
        'description': description,
        'observedAt': observedAt?.toUtc().toIso8601String(),
        'scope': scope.name,
        'wellLabel': wellLabel,
      };

  static List<ExperimentAttachment> parseList(Object? json) {
    final values = jsonObjectList(json, 'attachments')
        .map(ExperimentAttachment.fromJson)
        .toList();
    if (values.map((a) => a.id).toSet().length != values.length) {
      throw const FormatException('첨부파일 ID가 중복되었습니다.');
    }
    return values;
  }
}

bool validAttachmentDigest(String digest) =>
    RegExp(r'^[a-f0-9]{64}$').hasMatch(digest);

/// Payloads are immutable copies. Filenames never determine a storage path.
class AttachmentBlob {
  factory AttachmentBlob(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw const FormatException('비어 있는 파일 또는 10MB를 초과하는 파일은 첨부할 수 없습니다.');
    }
    return AttachmentBlob._(Uint8List.fromList(bytes).asUnmodifiableView());
  }
  AttachmentBlob._(this.bytes);
  final Uint8List bytes;
  late final String digest = sha256.convert(bytes).toString();

  static Map<String, AttachmentBlob> decodeFiles(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('첨부 원본 목록이 없습니다.');
    }
    final files = <String, AttachmentBlob>{};
    var total = 0;
    for (final entry in json.entries) {
      if (!validAttachmentDigest(entry.key) ||
          entry.value is! String ||
          (entry.value as String).length >
              ((maxAttachmentBytes + 2) ~/ 3) * 4) {
        throw const FormatException('첨부 원본의 형식 또는 크기가 올바르지 않습니다.');
      }
      final blob = AttachmentBlob(base64Decode(entry.value as String));
      total += blob.bytes.length;
      if (total > maxBackupAttachmentBytes) {
        throw const FormatException('백업 첨부파일 합계는 50MB까지 지원합니다.');
      }
      if (blob.digest != entry.key) {
        throw const FormatException('첨부 원본이 손상되었습니다.');
      }
      files[entry.key] = blob;
    }
    return files;
  }
}

void validateAttachmentBudget(Iterable<ExperimentAttachment> attachments) {
  final sizes = <String, int>{};
  for (final attachment in attachments) {
    sizes[attachment.digest] = attachment.byteLength;
  }
  if (sizes.values.fold<int>(0, (sum, size) => sum + size) >
      maxBackupAttachmentBytes) {
    throw const FormatException(
        '전체 실험의 첨부 원본 합계는 50MB까지 지원합니다. 불필요한 첨부를 정리해주세요.');
  }
}
