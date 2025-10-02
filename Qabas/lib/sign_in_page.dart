import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';


class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController(); // إيميل أو اسم مستخدم
  final _pass = TextEditingController();
  bool _loading = false;

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

  /// يحوّل الإدخال (إيميل أو اسم مستخدم) إلى إيميل
  Future<String?> _resolveEmail(String input) async {
    final id = input.trim();
    if (id.isEmpty) return null;

    if (id.contains('@')) return id; // إيميل مباشر

    try {
      final col = FirebaseFirestore.instance.collection('users');

      // المحاولة 1: usernameLower (مستحسن)
      var q = await col
          .where('usernameLower', isEqualTo: id.toLowerCase())
          .limit(1)
          .get();

      // المحاولة 2: username كما هو (لدعم بيانات قديمة)
      if (q.docs.isEmpty) {
        q = await col.where('username', isEqualTo: id).limit(1).get();
      }

      if (q.docs.isEmpty) return null;
      final data = q.docs.first.data();
      final email = (data['email'] as String?)?.trim();
      return email;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _toast('لا يمكن قراءة بيانات المستخدم من Firestore (قواعد الحماية تمنع ذلك أثناء التطوير).');
      }
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
    } on FirebaseAuthException {
      _toast('تعذّر إرسال الرابط. تأكّد من صحة البريد.', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل الدخول')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _identifier,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني أو اسم المستخدم',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل البريد الإلكتروني أو اسم المستخدم' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (v) => (v ?? '').isEmpty ? 'أدخل كلمة المرور' : null,
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _signIn,
                        child: _loading
                            ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('دخول'),
                      ),
                    ),

                    // اختر واحد:
                    // (1) ريسِت داخل نفس الصفحة:
                    TextButton(
                      onPressed: _loading ? null : _resetPasswordInline,
                      child: const Text('نسيت كلمة المرور؟'),
                    ),

                    // أو (2) افتح صفحة الريسِت المستقلة:
                    // TextButton(
                    //   onPressed: _loading
                    //       ? null
                    //       : () => Navigator.push(
                    //             context,
                    //             MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
                    //           ),
                    //   child: const Text('نسيت كلمة المرور؟'),
                    // ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}