import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'sign_in_page.dart';
import 'home_screen.dart';

class _SignupColors {
  static const primary     = Color(0xFF0E3A2C); // أخضر رئيسي
  static const primaryDark = Color(0xFF06261C); // نفس لون السهم في تسجيل الدخول
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey      = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _pass2Ctrl    = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    final username      = _usernameCtrl.text.trim();
    final usernameLower = username.toLowerCase();
    final email         = _emailCtrl.text.trim();
    final pass          = _passCtrl.text;

    setState(() => _loading = true);

    try {
      final exists = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isEqualTo: usernameLower)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));

      if (exists.docs.isNotEmpty) {
        _snack('اسم المستخدم مستخدم مسبقًا. جرّبي اسمًا آخر.', color: Colors.red);
        return;
      }

      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);

      final uid = cred.user!.uid;

      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'uid': uid,
          'email': email,
          'username': username,
          'usernameLower': usernameLower,
          'createdAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        _snack('تم إنشاء الحساب، وتأخر حفظ البيانات… نكمل.', color: Colors.orange);
      } catch (_) {
        _snack('تم إنشاء الحساب، وتعذّر حفظ البيانات… نكمل.', color: Colors.orange);
      }

      _snack('تم تسجيلك بنجاح', color: Colors.green);
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'حدث خطأ غير متوقع.';
      switch (e.code) {
        case 'email-already-in-use': msg = 'البريد مستخدم مسبقًا.'; break;
        case 'invalid-email':        msg = 'صيغة البريد غير صحيحة.'; break;
        case 'weak-password':        msg = 'كلمة المرور ضعيفة (6 أحرف على الأقل).'; break;
      }
      _snack(msg, color: Colors.red);
    } catch (e) {
      _snack('تعذّر إنشاء الحساب: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String hint) {
    const r = 24.0;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withOpacity(0.78),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: _SignupColors.primary.withOpacity(0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: _SignupColors.primary, width: 1.2),
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
          foregroundColor: _SignupColors.primaryDark, // ← نفس لون السهم من تسجيل الدخول
          centerTitle: true,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/signup_bg.png', // ← خلفية صفحة إنشاء الحساب
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
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.8,
                            child: TextFormField(
                              controller: _usernameCtrl,
                              validator: (v) {
                                final t = v?.trim() ?? '';
                                if (t.isEmpty) return 'أدخل اسم المستخدم';
                                if (t.length < 3) return 'اسم المستخدم قصير جدًا';
                                return null;
                              },
                              decoration: _dec('اسم المستخدم'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FractionallySizedBox(
                            widthFactor: 0.8,
                            child: TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                final email = v?.trim() ?? '';
                                final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                                if (!re.hasMatch(email)) return 'أدخل بريدًا صحيحًا';
                                return null;
                              },
                              decoration: _dec('البريد الإلكتروني'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FractionallySizedBox(
                            widthFactor: 0.8,
                            child: TextFormField(
                              controller: _passCtrl,
                              obscureText: true,
                              validator: (v) =>
                              (v ?? '').length < 6 ? 'أقل شيء 6 أحرف' : null,
                              decoration: _dec('كلمة المرور'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FractionallySizedBox(
                            widthFactor: 0.8,
                            child: TextFormField(
                              controller: _pass2Ctrl,
                              obscureText: true,
                              validator: (v) =>
                              v != _passCtrl.text ? 'غير مطابقة' : null,
                              decoration: _dec('تأكيد كلمة المرور'),
                            ),
                          ),
                          const SizedBox(height: 18),
                          FractionallySizedBox(
                            widthFactor: 0.7,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _SignupColors.primaryDark,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                shape: const StadiumBorder(),
                                side: const BorderSide(color: Colors.white, width: 1.4),
                                elevation: 2,
                              ),
                              onPressed: _loading ? null : _signUp,
                              child: _loading
                                  ? const SizedBox(
                                height: 22, width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Text('تسجيل'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const SignInPage()),
                            ),
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            child: const Text('لديك حساب مسبقًا؟ اضغط هنا'),
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