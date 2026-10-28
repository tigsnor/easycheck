import 'package:flutter/material.dart';

import '../../domain/experiment.dart';

/// Historical metadata only; never opens current Plate/files as old originals.
class ExperimentRevisionScreen extends StatelessWidget {
  const ExperimentRevisionScreen({super.key, required this.revision});
  final ExperimentRevision revision;

  @override
  Widget build(BuildContext context) {
    final before = revision.before;
    String date(DateTime? value) => value?.toLocal().toString() ?? '미기록';
    final lines = <String>[
      revision.summary,
      '기록 시각: ${date(revision.changedAt)}',
      if (revision.reason.isNotEmpty) '사유·검토 메모: ${revision.reason}',
      if (before != null) ...[
        '',
        '변경 전 노트',
        '제목: ${before.title}',
        '유형: ${before.experimentType}',
        '상태: ${switch (before.status) {
          ExperimentStatus.draft => '초안',
          ExperimentStatus.planned => '계획됨',
          ExperimentStatus.inProgress => '진행 중',
          ExperimentStatus.completed => '완료',
          ExperimentStatus.archived => '보관됨',
          ExperimentStatus.correcting => '정정 중',
        }}',
        '프로젝트: ${before.projectName ?? '미지정'}',
        '담당자: ${before.researcher ?? '미지정'}',
        '세포수: ${before.cellCountLabel ?? '미지정'}',
        '태그: ${before.tags.join(', ')}',
        '생성: ${date(before.createdAt)}',
        '저장: ${date(before.updatedAt)}',
        '최초 완료: ${date(before.completedAt)}',
        '',
        '메모',
        before.notes,
        '',
        '실행 단계',
        for (final task in before.tasks)
          '${task.title} · ${task.isCompleted ? '완료' : '미완료'}\n'
              '시작: ${date(task.startedAt)} / 완료: ${date(task.completedAt)}\n'
              '예정: ${task.plannedMinutes == null ? '미지정' : '${task.plannedMinutes}분'} / 알림 설정: ${task.reminderEnabled ? '켜짐' : '꺼짐'}',
        '',
        '시약·장비',
        for (final resource in before.resources)
          '${resource.type == ExperimentResourceType.reagent ? '시약' : '장비'}: ${resource.name}\n'
              '제조사: ${resource.manufacturer} / 제품·모델: ${resource.catalogOrModel}\n'
              'Lot·일련번호: ${resource.lotOrSerial}\n${resource.note}',
        '',
        '첨부 목록',
        for (final attachment in before.attachments)
          '${attachment.fileName} · ${attachment.targetLabel}\n'
              '관찰: ${date(attachment.observedAt)} / 등록: ${date(attachment.addedAt)}\n'
              '${attachment.description}',
        '',
        '이 이력에는 노트 내용과 첨부 목록이 보존됩니다. 삭제된 첨부 원본은 복원하지 않습니다. Plate 변경 전 상태는 Plate의 최근 변경 이력에서 확인하세요.',
      ] else ...[
        '',
        '이 기록에는 변경 전 노트가 저장되어 있지 않습니다.',
      ],
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('노트 변경 상세')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(lines.join('\n\n')),
        ),
      ),
    );
  }
}
