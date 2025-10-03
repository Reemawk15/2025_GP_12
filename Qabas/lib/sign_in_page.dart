import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';

/// ألوان محلية للصفحة
class _SigninColors {
  static const primary     = Color(0xFF0E3A2C); // أخضر رئيسي (سهم/نصوص)
  static const primaryDark = Color(0xFF06261C); // الأخضر الغامق للخلفية
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<String?> _resolveEmail(String input) async {
    final id = input.trim();
    if (id.isEmpty) return null;
    if (id.contains('@')) return id;

    try {
      final col = FirebaseFirestore.instance.collection('users');
      var q = await col.where('usernameLower', isEqualTo: id.toLowerCase()).limit(1).get();
      if (q.docs.isEmpty) {
        q = await col.where('username', isEqualTo: id).limit(1).get();
      }
      if (q.docs.isEmpty) return null;
      final data = q.docs.first.data();
      return (data['email'] as String?)?.trim();
    } on FirebaseException {
      return null;
    }
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = await _resolveEmail(_identifier.text);
      if (email == null) {
        _toast('لا يوجد حساب بهذا البريد الإلكتروني/الاسم.', color: Colors.red);
        return;
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _pass.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'حدث خطأ، حاول لاحقًا.';
      switch (e.code) {
        case 'user-not-found': msg = 'الحساب غير موجود.'; break;
        case 'wrong-password': msg = 'كلمة المرور غير صحيحة.'; break;
        case 'invalid-email': msg = 'البريد الإلكتروني غير صالح.'; break;
        case 'user-disabled': msg = 'تم تعطيل هذا الحساب.'; break;
      }
      _toast(msg, color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPasswordInline() async {
    setState(() => _loading = true);
    try {
      final email = await _resolveEmail(_identifier.text);
      if (email == null) {
        _toast('أدخل البريد الإلكتروني أو اسم المستخدم أولًا.', color: Colors.red);
        return;
      }
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast('أرسلنا رابط إعادة التعيين إلى $email');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decoration(String hint, {Widget? suffix}) {
    const radius = 24.0;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withOpacity(0.78),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: _SigninColors.primary.withOpacity(0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: _SigninColors.primary, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: _SigninColors.primary,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/signin_bg.png',
              fit: BoxFit.cover,
            ),

            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // البريد
                          FractionallySizedBox(
                            widthFactor: 0.8, // أقصر
                            child: TextFormField(
                              controller: _identifier,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'أدخل البريد الإلكتروني أو اسم المستخدم'
                                  : null,
                              decoration: _decoration('البريد الإلكتروني أو اسم المستخدم'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // كلمة المرور
                          FractionallySizedBox(
                            widthFactor: 0.8,
                            child: TextFormField(
                              controller: _pass,
                              obscureText: _obscure,
                              validator: (v) =>
                              (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                              onFieldSubmitted: (_) => _signIn(),
                              decoration: _decoration(
                                'كلمة المرور',
                                suffix: IconButton(
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure ? Icons.visibility : Icons.visibility_off,
                                    color: _SigninColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // زر تسجيل الدخول
                          FractionallySizedBox(
                            widthFactor: 0.7, // أقصر أكثر
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _SigninColors.primaryDark, // نفس الخلفية
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                shape: const StadiumBorder(),
                                side: const BorderSide(color: Colors.white, width: 1.4),
                                elevation: 2,
                              ),
                              onPressed: _loading ? null : _signIn,
                              child: _loading
                                  ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Text('تسجيل دخول'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextButton(
                            onPressed: _loading ? null : _resetPasswordInline,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('نسيتِ كلمة المرور؟'),
                          ),
                        ],
                      ),
                    ),
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