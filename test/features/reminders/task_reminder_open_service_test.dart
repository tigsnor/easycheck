import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easycheck/features/reminders/data/task_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<String> calls;
  Map<String, Object?>? launch;
  bool failInitialize = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    launch = null;
    failInitialize = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'initialize') {
        if (failInitialize) {
          throw PlatformException(code: 'initialization-failed');
        }
        return true;
      }
      if (call.method == 'getNotificationAppLaunchDetails') {
        return launch ?? {'notificationLaunchedApp': false};
      }
      if (call.method == 'pendingNotificationRequests') return <Object>[];
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> response(String value) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            channel.codec
                .encodeMethodCall(MethodCall('didReceiveNotificationResponse', {
              'id': 1,
              'payload': value,
              'notificationResponseType': 0,
            })),
            (_) {});
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
        '${platform.name} cold launch and warm tap share initialization and consume launch once',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      if (platform == TargetPlatform.iOS) {
        IOSFlutterLocalNotificationsPlugin.registerWith();
      }
      launch = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'id': 1,
          'payload': 'cold',
          'notificationResponseType': 0,
        }
      };
      final service = PlatformTaskReminderService.forPlatformTests(platform);
      final opened = <String?>[];
      await Future.wait(
          [service.listenForOpens(opened.add), service.pending()]);
      expect(calls.where((call) => call == 'initialize').length, 1);
      expect(opened, ['cold']);
      await response('warm');
      expect(opened, ['cold', 'warm']);
      await service.listenForOpens(opened.add);
      expect(
          calls
              .where((call) => call == 'getNotificationAppLaunchDetails')
              .length,
          1);
      service.stopListeningForOpens();
      await response('disposed');
      expect(opened, ['cold', 'warm']);
      expect(calls.any((call) => call.contains('requestPermissions')), isFalse);
    });
  }
  test('initialization failure can retry without consuming cold launch',
      () async {
    final service =
        PlatformTaskReminderService.forPlatformTests(TargetPlatform.android);
    final opened = <String?>[];
    failInitialize = true;
    await expectLater(
        service.listenForOpens(opened.add), throwsA(isA<PlatformException>()));
    failInitialize = false;
    launch = {
      'notificationLaunchedApp': true,
      'notificationResponse': {
        'id': 2,
        'payload': 'retry',
        'notificationResponseType': 0,
      }
    };
    await service.listenForOpens(opened.add);
    expect(opened, ['retry']);
    service.stopListeningForOpens();
  });
}
