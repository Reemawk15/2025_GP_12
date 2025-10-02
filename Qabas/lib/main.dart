import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'sign_up_page.dart';
import 'sign_in_page.dart';

/// درجات ألوان قَبَس
class QabasColors {
  static const primary     = Color(0xFF0E3A2C); // أخضر داكن
  static const primaryMid  = Color(0xFF2F5145); // أخضر متوسط (لزر حساب جديد)
  static const primaryDark = Color(0xFF06261C); // أغمق (لزر تسجيل الدخول)
  static const surface     = Colors.white;
  static const background  = Color(0xFFF7F8F7); // خلفية لطيفة
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        surface: QabasColors.surface,
        background: QabasColors.background,
      ),
      scaffoldBackgroundColor: QabasColors.background,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: QabasColors.surface,
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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // اللوجو
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: Image.asset(
                      'assets/images/qabas_logo.png',
                      height: 500, // غيّري المقاس إذا حبيتي
                      fit: BoxFit.contain,
                    ),
                  ),

                  // زر حساب جديد (الأخضر المتوسط)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: QabasColors.primaryMid,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpPage()),
                      ),
                      child: const Text('حساب جديد'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // زر تسجيل الدخول (الأخضر الأغمق)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: QabasColors.primaryDark,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignInPage()),
                      ),
                      child: const Text('تسجيل الدخول'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
