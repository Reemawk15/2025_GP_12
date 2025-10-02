// lib/sign_up_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// عدّلي اسم الصفحة التالية حسب مشروعك
import 'sign_in_page.dart';
import 'home_screen.dart';
/// ألوان قَبَس
class QabasColors {
  static const primary     = Color(0xFF0E3A2C); // أخضر داكن
  static const primaryMid  = Color(0xFF2F5145); // أخضر متوسط
  static const background  = Color(0xFFF7F8F7);
  static const onDark      = Colors.white;
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
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
      // 1) فحص تكرار اسم المستخدم
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

      // 2) إنشاء الحساب
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);

      final uid = cred.user!.uid;

      // 3) حفظ البيانات
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

      _snack('تم تسجيلك بنجاح ', color: Colors.green);
      await Future.delayed(const Duration(milliseconds: 500));

      // ✅ إدخال المستخدم مباشرةً للصفحة الرئيسية وهو مسجّل دخول
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()), // اسم ويدجت الصفحة الرئيسية
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

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.of(context).size;
    final safeH  = size.height - MediaQuery.of(context).padding.vertical;
    final headerHeight = (safeH * 0.42).clamp(220.0, 420.0); // استجابة للشاشة

    // ——— هذا المتغير يحدد نزول/طلوع المستطيل تحت الأقواس ———
    // <<< غيّري هذا الرقم لرفع/إنزال المستطيل (بالبكسل). كلما كبّر الرقم نزل تحت. >>>
    const double kRectShift = 24; // جرّبي: 8, 16, 24, 36 …
    // ——————————————————————————————————————————————————————————

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: Colors.white24),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: QabasColors.background,
        appBar: AppBar(
          title: const Text('حساب جديد'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: QabasColors.primary,
          elevation: 0,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final contentWidth = maxW.clamp(320.0, 560.0);

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Column(
                    children: [
                      // الهيدر (الأقواس + المستطيل)
                      SizedBox(
                        height: headerHeight,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _HeaderPainter(
                            rectShift: kRectShift, // ←← هنا يُمرَّر تحريك المستطيل
                          ),
                        ),
                      ),

                      // الفورم فوق المستطيل الداكن
                      Container(
                        width: double.infinity,
                        color: QabasColors.primary, // نفس لون المستطيل
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _usernameCtrl,
                                style: const TextStyle(color: QabasColors.onDark),
                                decoration: InputDecoration(
                                  labelText: 'اسم المستخدم',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  enabledBorder: fieldBorder,
                                  focusedBorder: fieldBorder.copyWith(
                                    borderSide: const BorderSide(color: Colors.white),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                ),
                                validator: (v) {
                                  final t = v?.trim() ?? '';
                                  if (t.isEmpty) return 'أدخل اسم المستخدم';
                                  if (t.length < 3) return 'اسم المستخدم قصير جدًا';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: QabasColors.onDark),
                                decoration: InputDecoration(
                                  labelText: 'البريد الإلكتروني',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  enabledBorder: fieldBorder,
                                  focusedBorder: fieldBorder.copyWith(
                                    borderSide: const BorderSide(color: Colors.white),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                ),
                                validator: (v) {
                                  final email = v?.trim() ?? '';
                                  final re = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                                  if (!re.hasMatch(email)) return 'أدخل بريدًا صحيحًا';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: true,
                                style: const TextStyle(color: QabasColors.onDark),
                                decoration: InputDecoration(
                                  labelText: 'كلمة المرور',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  enabledBorder: fieldBorder,
                                  focusedBorder: fieldBorder.copyWith(
                                    borderSide: const BorderSide(color: Colors.white),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                ),
                                validator: (v) =>
                                (v ?? '').length < 6 ? 'أقل شيء 6 أحرف' : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _pass2Ctrl,
                                obscureText: true,
                                style: const TextStyle(color: QabasColors.onDark),
                                decoration: InputDecoration(
                                  labelText: 'تأكيد كلمة المرور',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.18),
                                  enabledBorder: fieldBorder,
                                  focusedBorder: fieldBorder.copyWith(
                                    borderSide: const BorderSide(color: Colors.white),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                ),
                                validator: (v) =>
                                v != _passCtrl.text ? 'غير مطابقة' : null,
                              ),
                              const SizedBox(height: 22),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white, width: 1.5),
                                    foregroundColor: Colors.white,
                                    shape: const StadiumBorder(),
                                  ),
                                  onPressed: _loading ? null : _signUp,
                                  child: _loading
                                      ? const SizedBox(
                                    height: 22, width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white,
                                    ),
                                  )
                                      : const Text('تسجيل'),
                                ),
                              ),

                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (_) => const SignInPage()),
                                  );
                                },
                                child: const Text(
                                  'لديك حساب مسبقًا؟ اضغط هنا',
                                  style: TextStyle(color: Colors.white70, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// رسّام الهيدر (الأقواس + المستطيل)
class _HeaderPainter extends CustomPainter {
  /// **هذا المتغيّر هو مفتاح تحريك المستطيل**.
  /// كلما كبرت القيمة نزل المستطيل لتحت، وكلما صغرت طلع لفوق.
  final double rectShift; // بالبكسل

  _HeaderPainter({this.rectShift = 24});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // ألوان
    final Paint dark    = Paint()..color = QabasColors.primary;                 // المستطيل
    final Paint arcDark = Paint()..color = QabasColors.primary;                 // القوس الداكن
    final Paint arcMid  = Paint()..color = QabasColors.primaryMid.withOpacity(0.55);
    final Paint arcLite = Paint()..color = QabasColors.primaryMid.withOpacity(0.32);

    // مكان الأقواس (لو تبين تنزلين/تطلعين الأقواس كلها غيّري 0.93)
    final Offset center = Offset(w / 2, h * 0.93);
    final double rDark  = w * 0.78;

    // الأقواس الثلاثة
    canvas.drawCircle(center, rDark, arcDark);
    canvas.drawCircle(center.translate(0, -h * 0.08), rDark * .80, arcMid);
    canvas.drawCircle(center.translate(0, -h * 0.16), rDark * 0.62, arcLite);

    // ———————— أهم مكان للتعديل ————————
    // أعلى المستطيل تحت الأقواس:
    // <<< غيّري rectShift عند الإنشاء أو هنا لرفع/إنزال المستطيل >>>
    final double rectTop = center.dy - rDark + 700;
    canvas.drawRect(Rect.fromLTWH(0, rectTop, w, h - rectTop), dark);
    // ————————————————————————————————
  }

  @override
  bool shouldRepaint(covariant _HeaderPainter oldDelegate) =>
      oldDelegate.rectShift != rectShift;
}