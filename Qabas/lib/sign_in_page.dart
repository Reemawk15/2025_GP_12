import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'sign_up_page.dart';
import 'admin_home_screen.dart';

/// ======== Quick control for positioning/colors ========
const double kSigninProgressTop      = 190;   // Progress bar position from the top
const double kSigninBottomPadding    = 190;   // Bottom padding between content and background
const double kSigninFieldWidthFactor = 0.85;  // Field width relative to screen width

class _SigninTheme {
  static const primary     = Color(0xFF0E3A2C); // Dark text/icons
  static const btnFill     = Color(0xFF6F8E63); // Filled buttons color
  static const inputBorder = Color(0xFF6F8E63); // Input borders color
  static const inputFill   = Colors.white;      // Input background fill
  static const textDark    = primary;

  static Color get track => const Color(0xFFD7E5CF); // Progress bar track color
  static Color get fill  => const Color(0xFF8EAA7F); // Progress bar fill color
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController(); // Email or username
  final _pass       = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _pass.dispose();
    super.dispose();
  }

  // Quick toast message
  void _toast(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl), backgroundColor: color),
    );
  }

  // Mask email: show first 3 characters of the local part and replace the rest with **, keep domain as is
  String _maskEmailForDisplay(String email) {
    final trimmed = email.trim();
    if (!trimmed.contains('@')) {
      final local = trimmed;
      final keep = local.length >= 3 ? 3 : local.length;
      final shown = local.substring(0, keep);
      return '$shown**';
    }
    final parts = trimmed.split('@');
    final local = parts[0];
    final domain = parts[1];
    final keep = local.length >= 3 ? 3 : local.length;
    final shown = local.substring(0, keep);
    return '$shown**@$domain';
  }

  // Resolve username to email from Firestore — if the input is an email, return it as is
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
        return 'بيانات الدخول غير صحيحة. تحقق من اسم المستخدم أو البريد الإلكتروني وكلمة المرور.';
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

      // After signing in with Firebase, check the user's role in Firestore
      final uid = cred.user?.uid;
      if (uid != null) {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = snap.data() ?? {};
        final role = (data['role'] as String?)?.toLowerCase();
        final isAdmin = (data['isAdmin'] == true);

        if (!mounted) return;

        // If this is an admin account, do NOT allow login from the regular sign-in page
        // Show a generic error without hinting about the admin role
        if (role == 'admin' || isAdmin) {
          await FirebaseAuth.instance.signOut();
          _toast(
            'بيانات الدخول غير صحيحة. تحقق من اسم المستخدم أو البريد الإلكتروني وكلمة المرور.',
            color: Colors.red,
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

      // Show the masked email in the message
      final masked = _maskEmailForDisplay(email);
      _toast('أرسلنا رابط إعادة تعيين كلمة المرور إلى $masked');
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
        // Keep elements stable with keyboard open + internal scroll
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background (same style as sign-up)
            Image.asset('assets/images/SignIn.png', fit: BoxFit.cover),

            // Thin progress bar + circular arrow to go back to main
            Positioned(
              top: kSigninProgressTop,
              left: 24,
              right: 24,
              child: _TopBarArrow(onTap: () => Navigator.pop(context)),
            ),

            // Main content
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, kSigninBottomPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title and description
                      const Text(
                        'مرحبًا بعودتك',
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

                      // Input fields
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
                                obscureText: _obscure,                 // Hide/show based on state
                                obscuringCharacter: '•',               // Obscuring character
                                enableSuggestions: false,
                                autocorrect: false,
                                validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                                onFieldSubmitted: (_) => _signIn(),
                                decoration: _dec(
                                  'كلمة المرور',
                                  suffix: IconButton(
                                    tooltip: _obscure ? 'إظهار' : 'إخفاء',
                                    onPressed: () => setState(() => _obscure = !_obscure),
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

                      // Forgot password
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _loading ? null : _resetPasswordInline,
                          style: TextButton.styleFrom(foregroundColor: _SigninTheme.textDark),
                          child: const Text('نسيت كلمة المرور؟'),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Sign in button
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
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text('تسجيل الدخول', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // No account yet? + Admin login link
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'لا يوجد لديك حساب؟ ',
                                style: TextStyle(color: _SigninTheme.textDark),
                              ),
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
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'هل أنت مشرف النظام؟ ',
                                style: TextStyle(
                                  color: _SigninTheme.textDark,
                                ),
                              ),
                              InkWell(
                                onTap: _loading
                                    ? null
                                    : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AdminSignInPage()),
                                  );
                                },
                                child: const Text(
                                  'سجّل الدخول',
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

/// Simple progress bar + circular arrow button on the right for going back
class _TopBarArrow extends StatelessWidget {
  final VoidCallback onTap;
  const _TopBarArrow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      // Force this row to be LTR so the order is:
      // [extended track] then [space] then [circle with arrow] on the right
      textDirection: TextDirection.ltr,
      children: [
        // Filled track (visual элемент similar to the design)
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
                widthFactor: 0.55, // Fill percentage (visual only)
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
        // Circular button with arrow
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _SigninTheme.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

// ================== Admin Sign-In Page ==================

class AdminSignInPage extends StatefulWidget {
  const AdminSignInPage({super.key});

  @override
  State<AdminSignInPage> createState() => _AdminSignInPageState();
}

class _AdminSignInPageState extends State<AdminSignInPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController(); // Email or username
  final _pass       = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _pass.dispose();
    super.dispose();
  }

  // Show simple toast-style SnackBar
  void _toast(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textDirection: TextDirection.rtl),
        backgroundColor: color,
      ),
    );
  }

  // Mask email for password reset message
  String _maskEmailForDisplay(String email) {
    final trimmed = email.trim();
    if (!trimmed.contains('@')) {
      final local = trimmed;
      final keep = local.length >= 3 ? 3 : local.length;
      final shown = local.substring(0, keep);
      return '$shown**';
    }
    final parts = trimmed.split('@');
    final local = parts[0];
    final domain = parts[1];
    final keep = local.length >= 3 ? 3 : local.length;
    final shown = local.substring(0, keep);
    return '$shown**@$domain';
  }

  // Resolve username to email based on Firestore user document
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
        return 'بيانات الدخول غير صحيحة. تحقق من اسم المستخدم أو البريد الإلكتروني وكلمة المرور.';
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

  Future<void> _signInAdmin() async {
    if (!_form.currentState!.validate()) return;

    final idInput = _identifier.text.trim();
    final passInput = _pass.text;

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

      final uid = cred.user?.uid;
      if (uid == null) {
        _toast('تعذّر تسجيل الدخول. حاول لاحقًا.', color: Colors.red);
        return;
      }

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
      } else {
        // Not an admin -> sign out for safety and show message
        await FirebaseAuth.instance.signOut();
        _toast(
          'هذا الحساب ليس حساب مدير النظام.\nيرجى استخدام شاشة تسجيل الدخول العادية.',
          color: Colors.red,
        );
      }
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

      final masked = _maskEmailForDisplay(email);
      _toast('أرسلنا رابط إعادة تعيين كلمة المرور إلى $masked');
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
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            Image.asset('assets/images/SignIn.png', fit: BoxFit.cover),

            // Progress bar + arrow at top
            Positioned(
              top: kSigninProgressTop,
              left: 24,
              right: 24,
              child: _TopBarArrow(onTap: () => Navigator.pop(context)),
            ),

            // Content bottom sheet
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, kSigninBottomPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'تسجيل دخول المشرف',
                        style: TextStyle(
                          color: _SigninTheme.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'هذه النافذة مخصّصة لمدير النظام فقط. يرجى إدخال بيانات حساب المشرف.',
                        style: TextStyle(color: _SigninTheme.textDark),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
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
                                obscureText: _obscure,
                                obscuringCharacter: '•',
                                enableSuggestions: false,
                                autocorrect: false,
                                validator: (v) =>
                                (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                                onFieldSubmitted: (_) => _signInAdmin(),
                                decoration: _dec(
                                  'كلمة المرور',
                                  suffix: IconButton(
                                    tooltip: _obscure ? 'إظهار' : 'إخفاء',
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
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
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _loading ? null : _resetPasswordInline,
                          style: TextButton.styleFrom(
                            foregroundColor: _SigninTheme.textDark,
                          ),
                          child: const Text('نسيت كلمة المرور؟'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: 0.7,
                        child: FilledButton(
                          onPressed: _loading ? null : _signInAdmin,
                          style: FilledButton.styleFrom(
                            backgroundColor: _SigninTheme.btnFill,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: const StadiumBorder(),
                          ),
                          child: _loading
                              ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : const Text(
                            'تسجيل الدخول',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
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
