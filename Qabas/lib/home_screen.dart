// lib/home_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ⬅️ هذا للاستفادة من HomePage (صفحة الاختيار حساب جديد / تسجيل الدخول)
import 'main.dart'; // تأكد أن فيه كلاس HomePage وما يستورد هذا الملف عشان ما يصير تعارض دوّري

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    // تسجيل خروج فعلي من Firebase
    await FirebaseAuth.instance.signOut();

    // الذهاب لصفحة الاختيار ومسح سجل التنقل
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
          title: const Text('تأكيد تسجيل الخروج'),
          content: const Text('هل تريد تسجيل الخروج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
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
              const SizedBox(height: 32),

              // زر واضح لتسجيل الخروج أيضًا داخل المحتوى
              SizedBox(
                width: 220,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                  onPressed: () => _confirmLogout(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}