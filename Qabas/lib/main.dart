import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'sign_up_page.dart';
import 'sign_in_page.dart';
import 'splash_logo_page.dart';

/// Qabas color palette
class QabasColors {
  static const primary    = Color(0xFF0E3A2C); // Dark green for texts
  static const background = Color(0xFFC6DABA); // Start screen background (#c6daba)

  // Button colors matching the design:
  static const btnSolid   = Color(0xFFDDE9C6); // Top button
  static const btnLight   = Color(0xFFF0F7DF); // Bottom button
  static const btnText    = primary;           // Dark green text
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Unify status bar and bottom navigation bar colors with Qabas green
  const navBg = QabasColors.background;
  final baseStyle = const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
  SystemChrome.setSystemUIOverlayStyle(
    baseStyle.copyWith(systemNavigationBarColor: navBg),
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const QabasApp());
}

class QabasApp extends StatelessWidget {
  const QabasApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: QabasColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: QabasColors.primary,
        background: QabasColors.background,
      ),
      scaffoldBackgroundColor: QabasColors.background, // Ensures opening screen background
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
      home: const SplashLogoPage(), // First splash logo screen
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
        systemNavigationBarColor: Colors.white,         // Navigation bar in white
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background: main image
            Image.asset(
              'assets/images/First.png', // Image file name
              fit: BoxFit.cover,
            ),

            // Buttons layered above the background
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "Sign in" button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: QabasColors.btnSolid,
                            foregroundColor: QabasColors.btnText,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SignInPage()),
                          ),
                          child: const Text('تسجيل الدخول'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // "Create new account" button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: QabasColors.btnLight,
                            foregroundColor: QabasColors.btnText,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SignUpPage()),
                          ),
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
