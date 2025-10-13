import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'sign_up_page.dart';
import 'admin_home_screen.dart'; //

/// ======== تحكم سريع بالتموضع/الألوان ========
const double kSigninProgressTop      = 170;   // موضع الشريط من الأعلى
const double kSigninBottomPadding    = 270;   // مسافة المحتوى عن أسفل الخلفية
const double kSigninFieldWidthFactor = 0.85;  // عرض الحقول بالنسبة لعرض الشاشة

class _SigninTheme {
  static const primary     = Color(0xFF0E3A2C); // نصوص/أيقونات غامق
  static const btnFill     = Color(0xFF6F8E63); // لون الأزرار المعبّأة
  static const inputBorder = Color(0xFF6F8E63); // حدود الحقول
  static const inputFill   = Colors.white;      // تعبئة الحقول
  static const textDark    = primary;

  static Color get track => const Color(0xFFD7E5CF); // مسار الشريط
  static Color get fill  => const Color(0xFF8EAA7F); // تعبئة الشريط
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController(); // بريد أو اسم مستخدم
  final _pass       = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _pass.dispose();
    super.dispose();
  }

  // رسالة سريعة
  void _toast(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl), backgroundColor: color),
    );
  }

  // نحول اسم المستخدم إلى بريد من Firestore — لو دخل بريد نرجعه كما هو
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


  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة. تأكد منها ثم جرّب مرة أخرى.';
      case 'user-not-found':
        return 'لا يوجد حساب يطابق البريد الإلكتروني/اسم المستخدم المدخل.';
      case 'invalid-credential':
        return 'بيانات الدخول غير صحيحة. تحقق من المعرّف وكلمة المرور.';
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'too-many-requests':
        return 'محاولات كثيرة خلال وقت قصير. انتظر قليلًا ثم جرّب مجددًا.';
      case 'network-request-failed':
        return 'لا يوجد اتصال بالإنترنت. تحقّق من الشبكة ثم حاول مرة أخرى.';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب.';
      default:
        return 'تعذّر تسجيل الدخول. حاول لاحقًا.';
    }
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;

    final idInput = _identifier.text.trim();
    final passInput = _pass.text;

    // ✅ مسار أدمن ثابت بالاسم Admin والباس Admin1234_
    if (idInput.toLowerCase() == 'admin' && passInput == 'Admin1234_') {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
            (_) => false,
      );
      return;
    }

    // 👇 غير كذا: نستمر لمسار Firebase
    setState(() => _loading = true);
    try {
      final email = await _resolveEmail(idInput);
      if (email == null) {
        _toast('لا يوجد حساب يطابق البريد الإلكتروني/اسم المستخدم المدخل.', color: Colors.red);
        return;
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: passInput,
      );

      // بعد تسجيل دخول Firebase نتحقق من دوره في Firestore
      final uid = cred.user?.uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = snap.data() ?? {};
        final role = (data['role'] as String?)?.toLowerCase();
        final isAdmin = (data['isAdmin'] == true);

        if (!mounted) return;
        if (role == 'admin' || isAdmin) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
                (_) => false,
          );
          return;
        }
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _toast(_authMessage(e), color: Colors.red);
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
      _toast('أرسلنا رابط إعادة تعيين كلمة المرور إلى $email');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) {
    const r = 22.0;
    return InputDecoration(
      hintText: hint,
      hintTextDirection: TextDirection.rtl,
      filled: true,
      fillColor: _SigninTheme.inputFill.withOpacity(0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: _SigninTheme.inputBorder.withOpacity(0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: const BorderSide(color: _SigninTheme.inputBorder, width: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // العناصر ثابتة حتى مع ظهور الكيبورد + سكرول داخلي
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // الخلفية (نفس أسلوب التسجيل)
            Image.asset('assets/images/signin_bg.png', fit: BoxFit.cover),

            // شريط رفيع + دائرة بسهم ترجع للمين
            Positioned(
              top: kSigninProgressTop,
              left: 24,
              right: 24,
              child: _TopBarArrow(onTap: () => Navigator.pop(context)),
            ),

            // المحتوى
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, kSigninBottomPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // العنوان والوصف
                      const Text(
                        'مرحباً بعودتك',
                        style: TextStyle(
                          color: _SigninTheme.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'يرجى إدخال البريد الإلكتروني أو اسم المستخدم وكلمة المرور لتسجيل الدخول إلى حسابك',
                        style: TextStyle(color: _SigninTheme.textDark),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),

                      // الحقول
                      FractionallySizedBox(
                        widthFactor: kSigninFieldWidthFactor,
                        child: Form(
                          key: _form,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _identifier,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'أدخل البريد الإلكتروني أو اسم المستخدم'
                                    : null,
                                decoration: _dec('البريد الإلكتروني أو اسم المستخدم'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _pass,
                                obscureText: _obscure,                 // يختفي/يظهر حسب الحالة
                                obscuringCharacter: '•',               // شكل الإخفاء
                                enableSuggestions: false,
                                autocorrect: false,
                                validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                                onFieldSubmitted: (_) => _signIn(),
                                decoration: _dec(
                                  'كلمة المرور',
                                  suffix: IconButton(
                                    tooltip: _obscure ? 'إظهار' : 'إخفاء',
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                    // لما تكون مخفية نعرض أيقونة "مخفي" (عين عليها شطب)
                                    icon: Icon(
                                      _obscure ? Icons.visibility_off : Icons.visibility,
                                      color: _SigninTheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // نسيان كلمة المرور
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _loading ? null : _resetPasswordInline,
                          style: TextButton.styleFrom(foregroundColor: _SigninTheme.textDark),
                          child: const Text('نسيت كلمة المرور؟'),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // زر تسجيل الدخول
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: FilledButton(
                          onPressed: _loading ? null : _signIn,
                          style: FilledButton.styleFrom(
                            backgroundColor: _SigninTheme.btnFill,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: const StadiumBorder(),
                          ),
                          child: _loading
                              ? const SizedBox(
                            height: 22, width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Text('تسجيل الدخول', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // لا يوجد حساب؟
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('لا يوجد لديك حساب؟ ', style: TextStyle(color: _SigninTheme.textDark)),
                          InkWell(
                            onTap: _loading
                                ? null
                                : () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const SignUpPage()),
                              );
                            },
                            child: const Text(
                              'سجّل الآن',
                              style: TextStyle(
                                color: _SigninTheme.textDark,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

/// شريط بسيط + دائرة يمين فيها سهم، للرجوع
class _TopBarArrow extends StatelessWidget {
  final VoidCallback onTap;
  const _TopBarArrow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // المسار المليان (شكل جمالي مثل التصميم)
        Expanded(
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: _SigninTheme.track,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _SigninTheme.inputBorder.withOpacity(0.35)),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.55, // نسبة التعبئة (شكل فقط)
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: _SigninTheme.fill,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // الدائرة بالسهم (ترجع للمين)
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _SigninTheme.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_right, color: Colors.white), // يتجه لليمين
          ),
        ),
      ],
    );
  }
}
