import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart'; // لاستخدام HomePage و QabasColors إن وُجدت

class SplashLogoPage extends StatefulWidget {
  const SplashLogoPage({super.key});

  @override
  State<SplashLogoPage> createState() => _SplashLogoPageState();
}

class _SplashLogoPageState extends State<SplashLogoPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    _c.forward();

    // بعد 2 ثانية ننتقل إلى HomePage
    Timer(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const _LogoOnGreen(); // نفس الاسم القديم
  }
}

class _LogoOnGreen extends StatelessWidget {
  const _LogoOnGreen();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_SplashLogoPageState>();
    final scale = state?._scale ?? const AlwaysStoppedAnimation(1.0);

    // لون الخلفية #C6DABA (لو عندك QabasColors.background استخدمناه؛ وإلا استبدلي بالسطر المعلّق)
    const splashBg = QabasColors.background;
    // const splashBg = Color(0xFFC6DABA);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: splashBg,
        body: Center(
          child: ScaleTransition(
            scale: scale,
            child: Image.asset(
              'assets/images/qabas_mark.png', // شعارك
              width: MediaQuery.of(context).size.width * 0.38,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
