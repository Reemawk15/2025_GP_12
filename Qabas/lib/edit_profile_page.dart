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

      final bytes = await x.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(uid)
          .set({'photoUrl': url}, SetOptions(merge: true));
      await _user.updatePhotoURL(url);
      await _user.reload();

      setState(() => _photoUrl = url);
      _snack('تم تحديث الصورة بنجاح');
    } catch (e) {
      _snack('تعذّر تحديث الصورة. تحقق من الاتصال وحاول مرة أخرى.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_photoUrl == null || _photoUrl!.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('إزالة الصورة', textAlign: TextAlign.center),
          content: const Text('هل تريد إزالة صورة الملف الشخصي؟', textAlign: TextAlign.center),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirm,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('تأكيد'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      final uid = _user.uid;

      try {
        final ref = FirebaseStorage.instance.ref('users/$uid/avatar.jpg');
        await ref.delete();
      } catch (_) {}

      await FirebaseFirestore.instance.collection('users').doc(uid)
          .set({'photoUrl': FieldValue.delete()}, SetOptions(merge: true));

      await _user.updatePhotoURL(null);
      await _user.reload();

      setState(() => _photoUrl = null);
      _snack('تمت إزالة الصورة');
    } catch (e) {
      _snack('تعذّرت إزالة الصورة. جرّب لاحقًا.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // رسائل أخطاء Firebase بالعربي
  String _authErrorAr(FirebaseAuthException e) {
    switch (e.code) {
      case 'requires-recent-login':
        return 'لا يمكن إكمال العملية الآن. سجّل خروجًا ثم ادخل من جديد وأعيد المحاولة.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة.';
      case 'too-many-requests':
        return 'طلبات كثيرة مؤخرًا. يرجى المحاولة لاحقًا.';
      case 'network-request-failed':
        return 'تعذر الاتصال. تحقق من الشبكة.';
      default:
        return 'تعذّر تنفيذ العملية. (${e.code})';
    }
  }

  // فحص بسيط لتنسيق كلمة المرور (اختياري)
  String? _validatePassword(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null; // اختيارية
    final hasUpper   = t.contains(RegExp(r'[A-Z]'));
    final hasLower   = t.contains(RegExp(r'[a-z]'));
    final hasDigit   = t.contains(RegExp(r'\d'));
    final hasSymbol  = t.contains(RegExp(r'[!@#\$%^&*()_+\-=\[\]{};:"\\|,.<>/?`~]'));
    final noSpaces   = !t.contains(' ');
    if (t.length < 8 || !hasUpper || !hasLower || !hasDigit || !hasSymbol || !noSpaces) {
      return 'كلمة المرور يجب أن تكون ٨ أحرف على الأقل\n وتضمّ حرفًا كبيرًا وحرفًا صغيرًا ورقمًا ورمزًا خاصًا.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final currentName  = _user.displayName ?? '';
    final currentPhoto = _user.photoURL ?? '';

    final newName   = _name.text.trim();
    final newUser   = _username.text.trim();  // لن نستخدمه (غير قابل للتعديل)
    final newEmail  = _email.text.trim();     // لن نستخدمه (غير قابل للتعديل)
    final newPass   = _password.text.trim();
    final newPhoto  = _photoUrl ?? '';

    final nameChanged  = newName.isNotEmpty && newName != currentName;
    final photoChanged = newPhoto != currentPhoto;
    final passProvided = newPass.isNotEmpty;

    bool anySuccess = false;
    bool anyError   = false;

    try {
      // 1) Firestore — اكتب كل الحقول المتوقعة للاسم لتتزامن كل الشاشات
      final profilePayload = <String, dynamic>{
        if (nameChanged) ...{
          'name': newName,
          'fullName': newName,
          'displayName': newName,
          'nameLower': newName.toLowerCase(),
        },
        if (_photoUrl != null) 'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final willWriteProfile = nameChanged || photoChanged;
      if (willWriteProfile) {
        await FirebaseFirestore.instance
            .collection('users').doc(_user.uid)
            .set(profilePayload, SetOptions(merge: true));
        anySuccess = true;
      }

      // 2) Auth: الاسم/الصورة لضمان تزامن FirebaseAuth أيضًا
      if (nameChanged) {
        await _user.updateDisplayName(newName);
      }
      if (photoChanged) {
        await _user.updatePhotoURL(_photoUrl);
      }
      if (nameChanged || photoChanged) {
        await _user.reload();
      }

      // 3) كلمة المرور (اختيارية)
      if (passProvided) {
        final passError = _validatePassword(newPass);
        if (passError != null) {
          anyError = true;
          _snack(passError, error: true);
        } else {
          try {
            await _user.updatePassword(newPass);
            anySuccess = true;
            _snack('تم تحديث كلمة المرور');
          } on FirebaseAuthException catch (e) {
            anyError = true;
            _snack(_authErrorAr(e), error: true);
          }
        }
      }

      // ✅ الرسالة النهائية/التنقّل
      if (anySuccess && !anyError) {
        _snack('تم حفظ التعديلات ✅');
        if (mounted) Navigator.pop(context);
      } else if (!anySuccess && !anyError) {
        _snack('لا توجد تغييرات لحفظها.');
      }

    } catch (e) {
      _snack('حدث خطأ أثناء الحفظ. حاول لاحقًا.', error: true);
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
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : AbsorbPointer(
              absorbing: _saving,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  children: [
                    const SizedBox(height: 100),
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
                                ? Icon(Icons.person, size: 50, color: _darkGreen.withOpacity(0.8))
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
                                backgroundColor: _confirm,
                                child: const Icon(Icons.edit, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                          if (_photoUrl != null && _photoUrl!.isNotEmpty)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: _removePhoto,
                                borderRadius: BorderRadius.circular(16),
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.red.shade600,
                                  child: const Icon(Icons.delete_outline, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
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
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 8, end: 4),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
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
                            const SizedBox(height: 16),
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _label('الاسم'),
                                  _field(controller: _name, hint: 'اكتب اسمك'),
                                  const SizedBox(height: 12),

                                  _label('اسم المستخدم'),
                                  _field(
                                    controller: _username,
                                    hint: '@username',
                                    enabled: false, // ⛔️ غير قابل للتعديل
                                    suffixIcon: const Icon(Icons.lock_outline, size: 18),
                                  ),
                                  const SizedBox(height: 12),

                                  _label('البريد الإلكتروني'),
                                  _field(
                                    controller: _email,
                                    keyboard: TextInputType.emailAddress,
                                    hint: 'name@example.com',
                                    enabled: false, // ⛔️ غير قابل للتعديل
                                    suffixIcon: const Icon(Icons.lock_outline, size: 18),
                                    // لا حاجة لمحقق صحة لأنه disabled
                                    validator: (_) => null,
                                  ),
                                  const SizedBox(height: 12),

                                  _label('كلمة المرور'),
                                  _field(
                                    controller: _password,
                                    hint: '••••••••',
                                    obscure: true,
                                    validator: _validatePassword,
                                  ),
                                  const SizedBox(height: 20),

                                  SizedBox(
                                    height: 48,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _confirm,
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
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _darkGreen),
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
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      validator: validator ??
              (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
      enabled: enabled,
      readOnly: !enabled,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: enabled ? const Color(0xFFF6F7F5) : const Color(0xFFF0F0F0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: enabled ? _lightGreen : Colors.grey.shade400, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade400, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkGreen, width: 2),
        ),
      ),
      style: TextStyle(
        color: enabled ? Colors.black : Colors.grey.shade700,
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
    );
  }
}
