import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _confirm    = Color(0xFF6F8E63);

  final _formKey = GlobalKey<FormState>();
  final _currentPass = TextEditingController();
  final _newPass     = TextEditingController();
  final _confirmPass = TextEditingController();

  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew     = true;
  bool _obscureNew2    = true;

  String? _livePassError;

  User get _user => FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _newPass.addListener(() {
      final s = _newPass.text;
      _livePassError = _validatePassword(s);
      if (s.isEmpty) _livePassError = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _currentPass.dispose();
    _newPass.dispose();
    _confirmPass.dispose();
    super.dispose();
  }

  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFE7C4DA)),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// نفس شروط الباسوورد في sign_up_page.dart
  String? _validatePassword(String? v) {
    final s = v ?? '';
    if (s.length < 8) return 'الحد الأدنى 8 أحرف';
    if (!RegExp(r'[A-Z]').hasMatch(s)) return 'يلزم حرف كبير واحد على الأقل';
    if (!RegExp(r'[a-z]').hasMatch(s)) return 'يلزم حرف صغير واحد على الأقل';
    if (!RegExp(r'\d').hasMatch(s))    return 'يلزم رقم واحد على الأقل';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(s)) return 'يلزم رمز خاص واحد على الأقل';
    return null;
  }

  String _authErrorAr(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'كلمة المرور الحالية غير صحيحة.';
      case 'requires-recent-login':
        return 'لأسباب أمنية، سجّل خروجًا ثم ادخل من جديد وأعد المحاولة.';
      case 'too-many-requests':
        return 'طلبات كثيرة مؤخرًا. يرجى المحاولة لاحقًا.';
      case 'network-request-failed':
        return 'تعذر الاتصال. تحقق من الشبكة.';
      default:
        return 'تعذّر تغيير كلمة المرور. (${e.code})';
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    // تأكيد كلمة المرور الجديدة يطابق
    if (_newPass.text.trim() != _confirmPass.text.trim()) {
      _showSnack('تأكيد كلمة المرور لا يطابق الكلمة الجديدة.', icon: Icons.error_outline);
      return;
    }

    // تحقق من قوة الباسوورد
    final passError = _validatePassword(_newPass.text.trim());
    if (passError != null) {
      _showSnack(passError, icon: Icons.error_outline);
      return;
    }

    // 🔥 الجديدة نفس القديمة؟
    if (_currentPass.text.trim() == _newPass.text.trim()) {
      _showSnack('يجب اختيار كلمة مرور جديدة مختلفة عن الحالية.', icon: Icons.error_outline);
      return;
    }

    setState(() => _saving = true);

    try {
      final email = _user.email;
      if (email == null) {
        _showSnack('لا يمكن تغيير كلمة المرور لهذا الحساب.', icon: Icons.error_outline);
        return;
      }

      // 1) Reauthenticate
      final cred = EmailAuthProvider.credential(
        email: email,
        password: _currentPass.text.trim(),
      );
      await _user.reauthenticateWithCredential(cred);

      // 2) Update password
      await _user.updatePassword(_newPass.text.trim());
      await _user.reload();

      _showSnack('تم تغيير كلمة المرور بنجاح', icon: Icons.check_circle);
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _showSnack(_authErrorAr(e), icon: Icons.error_outline);
    } catch (_) {
      _showSnack('حدث خطأ غير متوقع. حاول لاحقًا.', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // نفس الخلفية المستخدمة في التسجيل
          Image.asset('assets/images/pass.png', fit: BoxFit.cover),

          Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false, // 👈 نخليها زي ما هي

            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight: 90,
              flexibleSpace: SafeArea(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'رجوع',
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
                    color: _darkGreen,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),

            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // constraints.maxHeight = ارتفاع مساحة الـ body
                  return Center(
                    child: Container(
                      width: double.infinity,
                      height: constraints.maxHeight,                // 👈 الكارد بطول الصفحة
                      constraints: const BoxConstraints(maxWidth: 480),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.94),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                        child: SingleChildScrollView(
                          // المسافة اللي تحت عشان الكيبورد ما يغطي آخر الحقول
                          padding: EdgeInsets.only(
                            bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'تغيير كلمة المرور',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: _darkGreen,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'لأسباب أمنية، أدخل كلمة المرور الحالية ثم اختر كلمة مرور جديدة قوية.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // كلمة المرور الحالية
                                _field(
                                  label: 'كلمة المرور الحالية',
                                  controller: _currentPass,
                                  obscure: _obscureCurrent,
                                  validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'هذا الحقل مطلوب'
                                      : null,
                                  suffix: IconButton(
                                    tooltip: _obscureCurrent ? 'إظهار' : 'إخفاء',
                                    onPressed: () => setState(
                                          () => _obscureCurrent = !_obscureCurrent,
                                    ),
                                    icon: Icon(
                                      _obscureCurrent
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: _midGreen,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // كلمة المرور الجديدة
                                _field(
                                  label: 'كلمة المرور الجديدة',
                                  controller: _newPass,
                                  obscure: _obscureNew,
                                  validator: _validatePassword,
                                  error: _livePassError != null,
                                  helper: _livePassError ??
                                      'كلمة المرور يجب أن تكون ٨ أحرف على الأقل\n'
                                          'وتضمّ حرفًا كبيرًا وحرفًا صغيرًا ورقمًا ورمزًا خاصًا.',
                                  suffix: IconButton(
                                    tooltip: _obscureNew ? 'إظهار' : 'إخفاء',
                                    onPressed: () => setState(
                                          () => _obscureNew = !_obscureNew,
                                    ),
                                    icon: Icon(
                                      _obscureNew
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: _midGreen,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // تأكيد كلمة المرور الجديدة
                                _field(
                                  label: 'تأكيد كلمة المرور الجديدة',
                                  controller: _confirmPass,
                                  obscure: _obscureNew2,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'هذا الحقل مطلوب';
                                    }
                                    if (v.trim() != _newPass.text.trim()) {
                                      return 'غير مطابقة لكلمة المرور الجديدة';
                                    }
                                    return null;
                                  },
                                  suffix: IconButton(
                                    tooltip: _obscureNew2 ? 'إظهار' : 'إخفاء',
                                    onPressed: () => setState(
                                          () => _obscureNew2 = !_obscureNew2,
                                    ),
                                    icon: Icon(
                                      _obscureNew2
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: _midGreen,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _confirm,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(26),
                                      ),
                                    ),
                                    onPressed: _saving ? null : _changePassword,
                                    child: _saving
                                        ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                        : const Text(
                                      'حفظ',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool obscure = false,
    String? Function(String?)? validator,
    Widget? suffix,
    bool error = false,
    String? helper,
  }) {
    const r = 14.0;
    final borderColor = error ? Colors.red : _midGreen.withOpacity(0.35);
    final focusColor  = error ? Colors.red : _midGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: _darkGreen,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF6F7F5),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: suffix,
            helperText: helper,
            helperMaxLines: 3,
            helperStyle: TextStyle(
              fontSize: 11.5,
              color: error ? Colors.red : Colors.grey.shade800,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(r),
              borderSide: BorderSide(color: focusColor, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}