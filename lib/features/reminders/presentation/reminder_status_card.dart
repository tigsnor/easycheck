import 'package:flutter/material.dart';
import '../application/task_reminder_coordinator.dart';
import '../data/task_reminder_service.dart';

class ReminderStatusCard extends StatelessWidget {
  const ReminderStatusCard({super.key, required this.coordinator});
  final TaskReminderCoordinator coordinator;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('종료 알림',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(coordinator.busy
                          ? '저장된 기록과 알림을 확인하는 중…'
                          : coordinator.error != null
                              ? '알림 예약 상태를 확인하지 못했습니다. 실험 기록과 별개로 알림 동기화를 다시 시도하세요.'
                              : switch (coordinator.permission) {
                                  ReminderPermission.granted =>
                                    '전체 실험의 예약된 알림 ${coordinator.scheduledKeys.length}개',
                                  ReminderPermission.denied =>
                                    '알림 권한이 꺼져 있습니다. 허용되지 않으면 기기 설정에서 PlateNote 알림을 켜 주세요.',
                                  ReminderPermission.unsupported =>
                                    '종료 알림은 Android와 iPhone에서 지원합니다.',
                                  null => '저장된 알림 상태를 확인해 주세요.',
                                }),
                      if (coordinator.deferredCount > 0)
                        Text(
                            '예약 한도: 가까운 시각부터 60개까지 예약합니다. 나머지 ${coordinator.deferredCount}개는 앱 재진입·저장·동기화 시 다시 확인합니다.'),
                      const SizedBox(height: 8),
                      const Text(
                          '미저장 설정은 예약에 반영되지 않습니다. 알림은 예정 시각 안내이며 단계 완료를 자동으로 기록하지 않습니다. Android 알림은 정시 도착을 보장하지 않습니다.'),
                      Wrap(spacing: 8, children: [
                        if (coordinator.permission !=
                                ReminderPermission.granted &&
                            coordinator.permission !=
                                ReminderPermission.unsupported)
                          TextButton(
                              key:
                                  const ValueKey('request-reminder-permission'),
                              onPressed: coordinator.busy
                                  ? null
                                  : () => coordinator.refresh(
                                      requestPermission: true),
                              child: const Text('알림 허용')),
                        TextButton(
                            key: const ValueKey('refresh-reminders'),
                            onPressed: coordinator.busy
                                ? null
                                : () => coordinator.refresh(),
                            child: const Text('알림 동기화')),
                      ]),
                    ])),
          ));
}
