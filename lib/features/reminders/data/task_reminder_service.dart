import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../domain/task_reminder.dart';

enum ReminderPermission { granted, denied, unsupported }

abstract class TaskReminderService {
  Future<ReminderPermission> permission({bool request = false});
  Future<Map<int, String?>> pending();
  Future<void> schedule(TaskReminder reminder);
  Future<void> cancel(int id);
}

class PlatformTaskReminderService implements TaskReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<void> _initialize() async {
    if (_initialized || !_supported) return;
    final ok = await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('ic_task_reminder'),
      iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false),
    ));
    if (ok != true) throw StateError('알림 기능을 초기화하지 못했습니다.');
    _initialized = true;
  }

  @override
  Future<ReminderPermission> permission({bool request = false}) async {
    if (!_supported) return ReminderPermission.unsupported;
    await _initialize();
    bool enabled;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()!;
      if (request) await android.requestNotificationsPermission();
      enabled = await android.areNotificationsEnabled() ?? false;
    } else {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()!;
      if (request) {
        await ios.requestPermissions(alert: true, sound: true, badge: false);
      }
      final status = await ios.checkPermissions();
      enabled = status?.isEnabled ?? false;
    }
    return enabled ? ReminderPermission.granted : ReminderPermission.denied;
  }

  @override
  Future<Map<int, String?>> pending() async {
    if (!_supported) return {};
    await _initialize();
    return {
      for (final n in await _plugin.pendingNotificationRequests())
        n.id: n.payload
    };
  }

  @override
  Future<void> schedule(TaskReminder reminder) async {
    await _initialize();
    if (!_supported) throw UnsupportedError('이 기기는 종료 알림을 지원하지 않습니다.');
    await _plugin.zonedSchedule(
      reminder.id,
      reminder.title,
      reminder.body,
      tz.TZDateTime.from(reminder.dueAt, tz.UTC),
      const NotificationDetails(
        android: AndroidNotificationDetails('experiment_steps_v1', '실험 단계 종료',
            channelDescription: '저장한 실험 단계의 예정 종료 시각 안내',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_task_reminder'),
        iOS: DarwinNotificationDetails(
            presentAlert: true, presentSound: true, presentBadge: false),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: reminder.payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (_supported) {
      await _initialize();
      await _plugin.cancel(id);
    }
  }
}
