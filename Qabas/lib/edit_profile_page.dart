import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';          // ✅ Auth
import 'package:cloud_firestore/cloud_firestore.dart';       // ✅ Firestore
import 'package:firebase_storage/firebase_storage.dart';     // ✅ Storage

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm    = Color(0xFF6F8E63);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _photoUrl;
  bool _loading = true;
  bool _saving = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _user.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};

      _name.text      = (data['name'] as String?) ?? _user.displayName ?? '';
      _username.text  = (data['username'] as String?) ?? '';
      _email.text     = (data['email'] as String?) ?? _user.email ?? '';
      _photoUrl       = (data['photoUrl'] as String?) ?? _user.photoURL;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;

    setState(() => _saving = true);
    try {
      final uid = _user.uid;
      final ref = FirebaseStorage.instance.ref('users/$uid/avatar.jpg');
      await ref.putFile(File(x.path));
      final url = await ref.getDownloadURL();

      // Firestore + Auth
      await FirebaseFirestore.instance.collection('users').doc(uid)
          .set({'photoUrl': url}, SetOptions(merge: true));
      await _user.updateProfile(photoURL: url); // ✅ نفس طريقتك

      setState(() => _photoUrl = url);
      _snack('تم تحديث الصورة بنجاح');
    } catch (e) {
      _snack('تعذّر تحديث الصورة: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final uid = _user.uid;

    try {
      // 1) Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name'     : _name.text.trim(),
        'username' : _username.text.trim(),
        'email'    : _email.text.trim(),
        if (_photoUrl != null) 'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) Auth: الاسم (والصورة لو كانت موجودة)
      final newName = _name.text.trim();
      if ((_user.displayName ?? '') != newName || (_user.photoURL ?? '') != (_photoUrl ?? '')) {
        await _user.updateProfile(
          displayName: newName,
          photoURL: _photoUrl,
        );
      }

      // 3) Auth: البريد (verifyBeforeUpdateEmail ترسل رسالة تحقق)
      final newEmail = _email.text.trim();
      if ((_user.email ?? '') != newEmail) {
        try {
          await _user.verifyBeforeUpdateEmail(newEmail);
          _snack('تم إرسال رسالة تحقق للبريد الجديد.\nبعد التأكيد سيتحدث البريد تلقائيًا.');
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            _snack('يحتاج إعادة تسجيل الدخول لتغيير البريد.', error: true);
          } else {
            _snack('تعذّر تحديث البريد: ${e.message}', error: true);
          }
        }
      }

      // 4) Auth: كلمة المرور (اختياري — فقط إذا امتلأت)
      final newPass = _password.text;
      if (newPass.isNotEmpty) {
        try {
          await _user.updatePassword(newPass);
          _snack('تم تحديث كلمة المرور');
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            _snack('يحتاج إعادة تسجيل الدخول لتغيير كلمة المرور.', error: true);
          } else {
            _snack('تعذّر تحديث كلمة المرور: ${e.message}', error: true);
          }
        }
      }

      _snack('تم حفظ التعديلات ✅');
      if (mounted) Navigator.pop(context); // رجوع لصفحة البروفايل
    } catch (e) {
      _snack('حدث خطأ أثناء الحفظ: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : _midGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),

          Scaffold(
            backgroundColor: Colors.transparent,
            // ❌ ما في AppBar — زر الرجوع داخل الكرت الأبيض
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : AbsorbPointer(
              absorbing: _saving,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  children: [
                    const SizedBox(height: 100), // ننزل المحتوى شوي

                    // صورة البروفايل مع زر تعديل صغير
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: _lightGreen,
                            backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
                                ? NetworkImage(_photoUrl!)
                                : null,
                            child: (_photoUrl == null || _photoUrl!.isEmpty)
                                ? Icon(Icons.person, size: 50, color: _darkGreen.withValues(alpha: 0.8))
                                : null,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: InkWell(
                              onTap: _pickAndUploadPhoto,
                              borderRadius: BorderRadius.circular(16),
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: _confirm, // ✅ نفس لون "تأكيد"
                                child: const Icon(Icons.edit, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10), // ننزل الكرت الأبيض أكثر

                    // الكرت الأبيض
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ✅ زر الرجوع داخل بداية الكرت (يمين لأن RTL) + مسافة تحته
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 8, end: 4),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart, // RTL: start = يمين
                                child: IconButton(
                                  tooltip: 'رجوع',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(0.85),
                                  ),
                                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                                  color: _darkGreen,
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16), // 👈 مسافة تحت السهم

                            // النموذج
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _label('الاسم'),
                                  _field(controller: _name, hint: 'اكتب اسمك'),
                                  const SizedBox(height: 12),

                                  _label('اسم المستخدم'),
                                  _field(controller: _username, hint: '@username'),
                                  const SizedBox(height: 12),

                                  _label('البريد الإلكتروني'),
                                  _field(
                                    controller: _email,
                                    keyboard: TextInputType.emailAddress,
                                    hint: 'name@example.com',
                                    validator: (v) {
                                      final t = (v ?? '').trim();
                                      if (t.isEmpty) return 'البريد مطلوب';
                                      if (!t.contains('@')) return 'صيغة البريد غير صحيحة';
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),

                                  _label('كلمة المرور'),
                                  _field(
                                    controller: _password,
                                    hint: '••••••••',
                                    obscure: true,
                                    validator: (_) => null, // اختيارية
                                  ),
                                  const SizedBox(height: 20),

                                  SizedBox(
                                    height: 48,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _confirm, // ✅ نفس لون "تأكيد"
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(26),
                                        ),
                                      ),
                                      onPressed: _save,
                                      child: _saving
                                          ? const CircularProgressIndicator(color: Colors.white)
                                          : const Text('حفظ', style: TextStyle(fontSize: 16)),
                                    ),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6, start: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: _darkGreen,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboard,
    bool obscure = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      validator: validator ??
              (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF6F7F5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightGreen, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkGreen, width: 2),
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
    );
  }
}