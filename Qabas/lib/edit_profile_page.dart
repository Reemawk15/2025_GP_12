import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';          // Auth
import 'package:cloud_firestore/cloud_firestore.dart';       // Firestore
import 'package:firebase_storage/firebase_storage.dart';     // Storage

import 'change_password.dart';

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

  String? _photoUrl;
  bool _loading = true;
  bool _saving = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Unified SnackBar with the same desired style
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
      _showSnack('تم تحديث الصورة بنجاح', icon: Icons.check_circle);
    } catch (e) {
      _showSnack('تعذّر تحديث الصورة. تحقق من الاتصال وحاول مرة أخرى.', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_photoUrl == null || _photoUrl!.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إزالة الصورة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل تريد إزالة صورة الملف الشخصي؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirm,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'تأكيد',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontSize: 16, color: _darkGreen),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'photoUrl': FieldValue.delete()}, SetOptions(merge: true));

      await _user.updatePhotoURL(null);
      await _user.reload();

      setState(() => _photoUrl = null);
      _showSnack('تمت إزالة الصورة', icon: Icons.check_circle);
    } catch (e) {
      _showSnack('تعذّرت إزالة الصورة. جرّب لاحقًا.', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final currentName  = _user.displayName ?? '';
    final currentPhoto = _user.photoURL ?? '';

    final newName   = _name.text.trim();
    final newPhoto  = _photoUrl ?? '';

    final nameChanged  = newName.isNotEmpty && newName != currentName;
    final photoChanged = newPhoto != currentPhoto;

    bool anySuccess = false;

    try {
      // 1) تحديث بيانات المستخدم في Firestore
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

      // 2) Auth: display name / photo
      if (nameChanged) {
        await _user.updateDisplayName(newName);
      }
      if (photoChanged) {
        await _user.updatePhotoURL(_photoUrl);
      }
      if (nameChanged || photoChanged) {
        await _user.reload();
      }

      if (anySuccess) {
        _showSnack('تم حفظ التعديلات ', icon: Icons.check_circle);
        if (mounted) Navigator.pop(context);
      } else {
        _showSnack('لا توجد تغييرات لحفظها.', icon: Icons.info_outline);
      }

    } catch (e) {
      _showSnack('حدث خطأ أثناء الحفظ. حاول لاحقًا.', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_midGreen),
              ),
            )
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
                                ? Icon(Icons.person,
                                size: 50,
                                color: _darkGreen.withOpacity(0.8))
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
                                child: const Icon(Icons.edit,
                                    size: 16, color: Colors.white),
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
                                  backgroundColor: Colors.redAccent,
                                  child: const Icon(Icons.delete_outline,
                                      size: 16, color: Colors.white),
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
                              padding: const EdgeInsetsDirectional.only(
                                  top: 8, end: 4),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: IconButton(
                                  tooltip: 'رجوع',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                    Colors.white.withOpacity(0.85),
                                  ),
                                  icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded),
                                  color: _darkGreen,
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                                children: [
                                  _label('الاسم'),
                                  _field(
                                    controller: _name,
                                    hint: 'اكتب اسمك',
                                  ),
                                  const SizedBox(height: 12),

                                  _label('اسم المستخدم'),
                                  _field(
                                    controller: _username,
                                    hint: '@username',
                                    enabled: false, // غير قابل للتعديل
                                    suffixIcon: const Icon(
                                      Icons.lock_outline,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  _label('البريد الإلكتروني'),
                                  _field(
                                    controller: _email,
                                    keyboard: TextInputType.emailAddress,
                                    hint: 'name@example.com',
                                    enabled: false, // غير قابل للتعديل
                                    suffixIcon: const Icon(
                                      Icons.lock_outline,
                                      size: 18,
                                    ),
                                    validator: (_) => null,
                                  ),
                                  const SizedBox(height: 12),

                                  _label('كلمة المرور'),
                                  SizedBox(
                                    height: 48,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: _confirm, width: 1.6),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(26),
                                        ),
                                        backgroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                            const ChangePasswordPage(),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        'تغيير كلمة المرور',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: _darkGreen,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  SizedBox(
                                    height: 48,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _confirm,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(26),
                                        ),
                                      ),
                                      onPressed: _save,
                                      child: _saving
                                          ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                          : const Text(
                                        'حفظ',
                                        style: TextStyle(
                                            fontSize: 16),
                                      ),
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
    bool enabled = true,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      validator: validator ??
              (v) =>
          (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
      enabled: enabled,
      readOnly: !enabled,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor:
        enabled ? const Color(0xFFF6F7F5) : const Color(0xFFF0F0F0),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: suffixIcon,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: enabled ? _lightGreen : Colors.grey.shade400,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.grey.shade400,
            width: 2,
          ),
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
