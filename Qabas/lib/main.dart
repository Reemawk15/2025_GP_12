import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'sign_up_page.dart';
import 'sign_in_page.dart';
import 'splash_logo_page.dart';

/// درجات ألوان قَبَس
class QabasColors {
  static const primary     = Color(0xFF0E3A2C); // أخضر داكن للنصوص
  static const background  = Color(0xFFC6DABA); // ← خلفية البداية الجديدة (#c6daba)

  // ألوان الأزرار بنفس روح الصورة:
  static const btnSolid    = Color(0xFFDDE9C6); // الزر العلوي
  static const btnLight    = Color(0xFFF0F7DF); // الزر السفلي
  static const btnText     = primary;           // نص أخضر داكن
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
        background: QabasColors.background,
      ),
      scaffoldBackgroundColor: QabasColors.background, // ← يضمن خلفية الشاشة الافتتاحية
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
      home: const SplashLogoPage(), // شاشة الشعار الأولى
    );
  }
}

/// صفحة البداية (تسجيل الدخول / إنشاء حساب)
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // الخلفية: الصورة الجديدة
          Image.asset(
            'assets/images/First.png', // ← اسم الصورة
            fit: BoxFit.cover,
          ),

          // الأزرار فوق الخلفية
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // زر "تسجيل الدخول" (العلوي) – لون أغمق قليلًا مثل المثال
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
                          MaterialPageRoute(builder: (_) => const SignInPage()),
                        ),
                        child: const Text('تسجيل الدخول'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // زر "إنشاء حساب جديد" (السفلي) – أفتح
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
                          MaterialPageRoute(builder: (_) => const SignUpPage()),
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
    );
  }
}
