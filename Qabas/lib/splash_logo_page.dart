import 'dart:async';
import 'package:flutter/material.dart';
import 'main.dart'; // علشان نستخدم HomePage مباشرة

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
      duration: const Duration(milliseconds: 600),
    );
    _scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);

    _c.forward();

    // مدّة إجمالية بسيطة ثم الانتقال
    Timer(const Duration(milliseconds: 1800), () {
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
    return const _LogoOnWhite();
  }
}

class _LogoOnWhite extends StatelessWidget {
  const _LogoOnWhite();

  @override
  Widget build(BuildContext context) {
    // استخدم AnimatedBuilder لربط الأنيميشن
    final state = context.findAncestorStateOfType<_SplashLogoPageState>();
    final scale = state?._scale ?? const AlwaysStoppedAnimation(1.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: scale,
          child: Image.asset(
            'assets/images/qabas_mark.png', // ← شعارك
            width: MediaQuery.of(context).size.width * 0.38, // حجم واضح
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}