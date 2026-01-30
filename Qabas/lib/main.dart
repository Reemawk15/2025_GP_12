import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_options.dart';
import 'sign_up_page.dart';
import 'sign_in_page.dart';
import 'splash_logo_page.dart';
import 'goal_notifications.dart';

/// Qabas color palette
class QabasColors {
  static const primary = Color(0xFF0E3A2C);
  static const background = Color(0xFFC6DABA);

  static const btnSolid = Color(0xFFDDE9C6);
  static const btnLight = Color(0xFFF0F7DF);
  static const btnText = primary;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status & navigation bar styling
  const navBg = QabasColors.background;
  const baseStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
  SystemChrome.setSystemUIOverlayStyle(
    baseStyle.copyWith(systemNavigationBarColor: navBg),
  );

  // Firebase init
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await GoalNotifications.instance.init();
  await GoalNotifications.instance.scheduleWeeklyStartMotivation();

  runApp(const QabasApp());
  // ✅ اطبع projectId (مهم جداً عشان نتأكد انه نفس مشروع الفنكشن)
  debugPrint('APP projectId = ${Firebase.app().options.projectId}');
  debugPrint('APP appId     = ${Firebase.app().options.appId}');

  // ✅ App Check
  if (kDebugMode) {
    // في الديبق: استخدمي Debug provider عشان ما يعطل Requests
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );

    debugPrint('✅ AppCheck: Debug provider activated');
    // ملاحظة: لا نستدعي getToken هنا لأنه أحيانًا ما يطبع شيء ويشوّش.
  } else {
    // 🔒 في الريليز (اختياري): فعّليه فقط إذا فعلتي Enforcement في الكونسول
    // إذا ما تبين AppCheck الآن، خليه معلق أو احذفيه.
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck, // أو appAttest لو فعلتيه
    );
  }

  runApp(const QabasApp());
}

class QabasApp extends StatelessWidget {
  const QabasApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: QabasColors.primary,
            brightness: Brightness.light,
          ).copyWith(
            primary: QabasColors.primary,
            background: QabasColors.background,
          ),
      scaffoldBackgroundColor: QabasColors.background,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: QabasColors.primary,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(height: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          side: const BorderSide(color: QabasColors.primary),
          foregroundColor: QabasColors.primary,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );

    return MaterialApp(
      title: 'قَبَس',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      home: const SplashLogoPage(),
    );
  }
}

/// Home page (Sign in / Sign up)
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/First.png', fit: BoxFit.cover),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: QabasColors.btnSolid,
                            foregroundColor: QabasColors.btnText,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignInPage(),
                              ),
                            );
                          },
                          child: const Text('تسجيل الدخول'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: QabasColors.btnLight,
                            foregroundColor: QabasColors.btnText,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignUpPage(),
                              ),
                            );
                          },
                          child: const Text('إنشاء حساب جديد'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
