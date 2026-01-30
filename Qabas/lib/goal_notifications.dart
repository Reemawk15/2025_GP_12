import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class GoalNotifications {
  GoalNotifications._();
  static final GoalNotifications instance = GoalNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    // Android 13+ permission
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      'weekly_goal_channel',
      'Weekly Goal',
      channelDescription: 'Weekly goal reminders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: ios);
  }

  /// 🟢 الحالة 1: بداية الأسبوع (كل سبت 7 صباحًا)
  Future<void> scheduleWeeklyStartMotivation() async {
    try {
      await _plugin.zonedSchedule(
        1001,
        'بداية أسبوع جديدة',
        'ابدئي أسبوعك بخطوة صغيرة… استماع بسيط اليوم يصنع فرقًا كبيرًا.',
        _nextSaturdayAt(7, 0),
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (_) {
      // لا تسوين كراش للتطبيق
    }
  }

  /// 🔔 إشعار فوري (نستخدمه للحالات اللي تعتمد على التقدم)

  Future<void> showNow(int id, String title, String body) async {
    await _plugin.show(id, title, body, _details());
  }
  // داخل GoalNotifications class

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// جدولة تذكير لنهاية الأسبوع (الخميس/الجمعة)
  Future<void> scheduleEndOfWeekReminder({
    required int id,
    required int weekday, // DateTime.thursday / DateTime.friday
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      _nextWeekdayAt(weekday, hour, minute),
      _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// ترجع أقرب (الخميس/الجمعة) جاي حسب توقيت الرياض
  tz.TZDateTime _nextWeekdayAt(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  tz.TZDateTime _nextSaturdayAt(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);

    // في Dart: Monday=1 ... Sunday=7
    // Saturday = 6
    const targetWeekday = DateTime.saturday; // 6

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    //الحاله الثانيه في كلاس تفاصيل الكتاب
    //الحاله الثالثه هنا : و هي حقت التاخير
    while (scheduled.weekday != targetWeekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }
}
