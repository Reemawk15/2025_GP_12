// sign_up_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'sign_in_page.dart';

/// ===== تحكّم سريع بالمظهر والتموضع =====
const double kProgressTop = 210;          // موضع شريط التقدم + السهم من الأعلى
const double kContentBottomPadding = 240; // مسافة المحتوى من أسفل

/// إزاحات اختيارية لكل صفحة (سالب = يطلع فوق، موجب = ينزل)
const double kShiftIntro     = 0;
const double kShiftName      = 0;
const double kShiftNotifs    = 0;
const double kShiftGreat     = 0;
const double kShiftEmail     = 20;
const double kShiftPassword  = 100;
const double kShiftUsername  = 30;

/// ارتفاع حقول الإدخال
const double kFieldHeight = 90;

/// لوحة ألوان
class _SignupTheme {
  static const primary     = Color(0xFF0E3A2C);
  static const btnFill     = Color(0xFF6F8E63);
  static const inputBorder = Color(0xFF6F8E63);
  static const inputFill   = Colors.white;

  static const titleColor = Color(0xFF6F8E63);
  static const bodyColor  = Color(0xFF2E4A3F);
  static const hintColor  = Color(0x99334D40);

  static Color get track => const Color(0xFFD7E5CF);
  static Color get fill  => const Color(0xFF8EAA7F);
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final PageController _pc = PageController();
  int _index = 0;

  final TextEditingController _nameCtrl     = TextEditingController();
  final TextEditingController _emailCtrl    = TextEditingController();
  final TextEditingController _passCtrl     = TextEditingController();
  final TextEditingController _pass2Ctrl    = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();

  bool _notifsEnabled = true;
  bool _loading = false;

  String? _livePassError;
  String? _livePass2Error;

  @override
  void initState() {
    super.initState();
    _passCtrl.addListener(() {
      final s = _passCtrl.text;
      _livePassError = _validatePassword(s);
      if (s.isEmpty) _livePassError = null;
      if (mounted) setState(() {});
    });
    _pass2Ctrl.addListener(() {
      _livePass2Error = (_pass2Ctrl.text.isEmpty)
          ? null
          : (_pass2Ctrl.text == _passCtrl.text ? null : 'غير مطابقة');
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pc.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  void _to(int i) {
    setState(() => _index = i);
    _pc.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
  }

  void _next() => _to((_index + 1).clamp(0, 6));
  void _back() => _to((_index - 1).clamp(0, 6));

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, textDirection: TextDirection.rtl), backgroundColor: color),
    );
  }

  // شروط كلمة المرور
  String? _validatePassword(String? v) {
    final s = v ?? '';
    if (s.length < 8) return 'الحد الأدنى 8 أحرف';
    if (!RegExp(r'[A-Z]').hasMatch(s)) return 'يلزم حرف كبير واحد على الأقل';
    if (!RegExp(r'[a-z]').hasMatch(s)) return 'يلزم حرف صغير واحد على الأقل';
    if (!RegExp(r'\d').hasMatch(s))    return 'يلزم رقم واحد على الأقل';
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(s)) return 'يلزم رمز خاص واحد على الأقل';
    return null;
  }

  bool _canGoNext() {
    switch (_index) {
      case 0: return true; // Intro
      case 1: return _nameCtrl.text.trim().length >= 2;
      case 2: return true; // الإشعارات اختيارية
      case 3: return true; // رائع
      case 4:
        return RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(_emailCtrl.text.trim());
      case 5:
        final p = _passCtrl.text, p2 = _pass2Ctrl.text;
        return _validatePassword(p) == null && p2 == p;
      case 6:
        return _usernameCtrl.text.trim().length >= 3 && !_loading;
      default:
        return true;
    }
  }

  InputDecoration _dec(String hint, {bool error = false, String? helper}) {
    const r = 22.0;
    final borderColor = error ? Colors.red : _SignupTheme.inputBorder.withOpacity(0.35);
    final focusColor  = error ? Colors.red : _SignupTheme.inputBorder;
    return InputDecoration(
      hintText: hint,
      hintTextDirection: TextDirection.rtl,
      hintStyle: const TextStyle(color: _SignupTheme.hintColor),
      helperText: helper,
      helperStyle: TextStyle(
        color: error ? Colors.red : _SignupTheme.bodyColor.withOpacity(0.65),
        fontSize: 12,
      ),
      filled: true,
      fillColor: _SignupTheme.inputFill.withOpacity(0.92),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: focusColor, width: 1.3),
      ),
    );
  }

  Future<void> _tryRegister() async {
    final name     = _nameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final pass     = _passCtrl.text;
    final pass2    = _pass2Ctrl.text;

    if (name.isEmpty || username.length < 3) return;
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) return;
    final pErr = _validatePassword(pass);
    if (pErr != null || pass2 != pass) return;

    setState(() => _loading = true);
    try {
      // تحقق من توفر اسم المستخدم
      final u = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (u.docs.isNotEmpty) {
        _showGenericExistsDialog();
        return;
      }

      // إنشاء مستخدم
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);

      final user = cred.user!;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'email': email,
        'emailLower': email.toLowerCase(),
        'username': username,
        'usernameLower': username.toLowerCase(),
        'notificationsEnabled': _notifsEnabled,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showGenericExistsDialog();
      } else {
        _snack('تعذّر إنشاء الحساب. حاول لاحقًا.', color: Colors.red);
      }
    } catch (e) {
      _snack('خطأ غير متوقع: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showGenericExistsDialog() {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFFE7EEE8),
          title: const Text('يبدو أنك جزء من قبس!', textAlign: TextAlign.center),
          content: const Text(
            'هذا البريد أو الاسم مستخدم من قبل.\nيمكنك تسجيل الدخول أو تجربة بيانات أخرى.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const SignInPage()),
                );
              },
              child: const Text('تسجيل الدخول'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.white,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // الخلفية
              Image.asset('assets/images/SignIn.png', fit: BoxFit.cover),

              // المحتوى — نخليه تحت السهم عشان ما يبلع اللمس
              SafeArea(
                child: PageView(
                  controller: _pc,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    // 0) المقدمة
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftIntro,
                      child: _IntroBlock(onStart: _next),
                    ),

                    // 1) الاسم
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftName,
                      child: _FormCols(children: [
                        const _Title('أهلاً بك، عرفنا باسمك؟'),
                        FractionallySizedBox(
                          widthFactor: 0.85,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: _dec(
                                'الاسم',
                                error: _nameCtrl.text.isEmpty && _index == 1,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _RoundMainButton(label: 'التالي', onTap: _canGoNext() ? _next : null),
                      ]),
                    ),

                    // 2) الإشعارات
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftNotifs,
                      child: _FormCols(children: [
                        const _Title('خلك دايمًا قريب من الكتاب'),
                        const Text(
                          'خلّنا نساعدك بالتذكير عشان تحقّق هدفك القرائي اليومي',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _SignupTheme.bodyColor),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _SignupTheme.inputBorder.withOpacity(0.35)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _notifsEnabled ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: _SignupTheme.inputBorder,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('الإشعارات', style: TextStyle(height: 1.2))),
                              const SizedBox(width: 8),
                              Switch(
                                value: _notifsEnabled,
                                onChanged: (v) => setState(() => _notifsEnabled = v),
                                activeColor: _SignupTheme.inputBorder,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _RoundMainButton(label: 'التالي', onTap: _next),
                      ]),
                    ),

                    // 3) رائع
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftGreat,
                      child: _FormCols(children: [
                        const _Title('رائع'),
                        const Text(
                          'جاهزون للبدء، لنقم بإنشاء حسابك لحفظ تفضيلاتك وتخصيص تجربتك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _SignupTheme.bodyColor),
                        ),
                        const SizedBox(height: 20),
                        _RoundMainButton(label: 'حسنًا', onTap: _next),
                      ]),
                    ),

                    // 4) البريد
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftEmail,
                      child: _FormCols(children: [
                        const _Title('ما هو بريدك الإلكتروني؟'),
                        FractionallySizedBox(
                          widthFactor: 0.85,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _dec(
                                'البريد الإلكتروني',
                                error: _emailCtrl.text.isNotEmpty &&
                                    !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(_emailCtrl.text),
                                helper: 'أدخل بريدًا صالحًا',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _RoundMainButton(label: 'التالي', onTap: _canGoNext() ? _next : null),
                      ]),
                    ),

                    // 5) كلمة المرور
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftPassword,
                      child: _FormCols(children: [
                        const _Title('كلمة المرور'),
                        FractionallySizedBox(
                          widthFactor: 0.85,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _passCtrl,
                              obscureText: true,
                              onChanged: (_) => setState(() {}),
                              decoration: _dec(
                                'كلمة المرور',
                                error: _livePassError != null,
                                helper: _livePassError ??
                                    'كلمة المرور يجب أن تكون ٨ أحرف على الأقل\nوتضمّ حرفًا كبيرًا وحرفًا صغيرًا ورقمًا ورمزًا خاصًا.',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FractionallySizedBox(
                          widthFactor: 0.85,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _pass2Ctrl,
                              obscureText: true,
                              onChanged: (_) => setState(() {}),
                              decoration: _dec(
                                'تأكيد كلمة المرور',
                                error: _livePass2Error != null,
                                helper: _livePass2Error,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _RoundMainButton(label: 'التالي', onTap: _canGoNext() ? _next : null),
                      ]),
                    ),

                    // 6) اسم المستخدم + تسجيل
                    _BottomSheetArea(
                      bottomPadding: kContentBottomPadding,
                      yShift: kShiftUsername,
                      child: _FormCols(children: [
                        const _Title('اسم المستخدم'),
                        const Text(
                          'اسم المستخدم حتى يتمكن أصدقاؤك من العثور عليك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _SignupTheme.bodyColor),
                        ),
                        const SizedBox(height: 14),
                        FractionallySizedBox(
                          widthFactor: 0.85,
                          child: SizedBox(
                            height: kFieldHeight,
                            child: TextField(
                              controller: _usernameCtrl,
                              decoration: _dec(
                                'اسم مستخدم',
                                error: _usernameCtrl.text.isNotEmpty &&
                                    _usernameCtrl.text.trim().length < 3,
                                helper: '3 أحرف على الأقل',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _RoundMainButton(
                          label: _loading ? '...جاري' : 'سجّل',
                          onTap: _canGoNext() ? _tryRegister : null,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),

              // ✅ شريط التقدم + السهم — آخر عنصر (فوق) ليأخذ اللمس
              Positioned(
                top: kProgressTop,
                left: 24,
                right: 24,
                child: _ProgressWithArrow(
                  step: _index,
                  total: 7,
                  onArrowTap: () {
                    if (_index > 0) {
                      _back(); // يرجّع خطوة داخل المعالج
                    } else if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop(); // يرجّع للشاشة السابقة
                    } else {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const SignInPage()),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/*====================== Widgets مساعدة ======================*/

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: _SignupTheme.titleColor,
        ),
      ),
    );
  }
}

class _IntroBlock extends StatelessWidget {
  final VoidCallback onStart;
  const _IntroBlock({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return _FormCols(children: [
      const _Title('أهلاً بك في قَبَس'),
      const SizedBox(height: 6),
      const Text(
        'قَبَس هو تطبيق ذكي يساعدك على بناء عادة القراءة بطريقة تناسب وقتك وأسلوبك، '
            'ويقدّم لك تجربة صوتية مخصّصة لكتابك العربي.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _SignupTheme.bodyColor),
      ),
      const SizedBox(height: 12),
      const Text(
        'قَبَس سيكون معك في كل شكل من أشكال القراءة ليكون صديقك الأول في هذه الرحلة.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _SignupTheme.bodyColor),
      ),
      const SizedBox(height: 12),
      const Text(
        'ولأهمية تخصيص التجربة، سنطرح عليك الآن بعض الأسئلة لنقدّم تجربة استثنائية تناسبك تمامًا.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _SignupTheme.bodyColor),
      ),
      const SizedBox(height: 20),
      _RoundMainButton(label: 'ابدأ', onTap: onStart),
    ]);
  }
}

class _BottomSheetArea extends StatelessWidget {
  final Widget child;
  final double bottomPadding;
  final double yShift; // + ينزل، - يطلع

  const _BottomSheetArea({
    required this.child,
    required this.bottomPadding,
    this.yShift = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding),
        child: Transform.translate(
          offset: Offset(0, yShift),
          child: child,
        ),
      ),
    );
  }
}

class _FormCols extends StatelessWidget {
  final List<Widget> children;
  const _FormCols({required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _RoundMainButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _RoundMainButton({required this.label, required this.onTap, super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240, height: 52,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: _SignupTheme.btnFill,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        child: Text(label),
      ),
    );
  }
}

/// شريط تقدم RTL بدون دائرة (يمتلي من اليمين لليسار)
class _ProgressBarRtl extends StatelessWidget {
  final int step;   // 0..(total-1)
  final int total;  // عدد الصفحات
  const _ProgressBarRtl({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final frac = ((step + 1) / total).clamp(0.0, 1.0);
    return SizedBox(
      height: 28,
      child: Stack(
        children: [
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: _SignupTheme.track,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _SignupTheme.inputBorder.withOpacity(0.35)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: frac,
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  color: _SignupTheme.fill,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ مركّب: شريط التقدم + دائرة سهم يمين (نفس فكرة تسجيل الدخول)
class _ProgressWithArrow extends StatelessWidget {
  final int step;
  final int total;
  final VoidCallback onArrowTap;
  const _ProgressWithArrow({
    required this.step,
    required this.total,
    required this.onArrowTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr, // نخلي الدائرة تثبت يمين الشريط
      children: [
        Expanded(child: _ProgressBarRtl(step: step, total: total)),
        const SizedBox(width: 10),
        InkWell(
          onTap: onArrowTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _SignupTheme.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_left, color: Colors.white),
          ),
        ),
      ],
    );
  }
}