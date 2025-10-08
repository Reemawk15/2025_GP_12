// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

class _HomeColors {
  // أخضر الهوية (عدّليه لو تبين درجة ثانية)
  static const confirm = Color(0xFF6F8E63); // الأخضر الغامق
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('  متأكد من تسجيل الخروج؟    '),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),

              const SizedBox(height: 16),
              // زر التأكيد (بالأخضر)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _HomeColors.confirm,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد'),
                ),
              ),
              // زر الإلغاء تحت التأكيد
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await _logout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الرئيسية'),
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmLogout(context),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/qabas_logo.png',
                height: 160,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text('تم تسجيل الدخول بنجاح ✨'),
              const SizedBox(height: 8),
              // (تم إزالة زر تسجيل الخروج السفلي كما طلبت)
            ],
          ),
        ),
      ),
    );
  }
}
