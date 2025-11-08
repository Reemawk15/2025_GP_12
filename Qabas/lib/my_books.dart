import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'library_tab.dart'; // For returning to the private library hub
import 'my_book_details_page.dart';

const Color _darkGreen  = Color(0xFF0E3A2C);
const Color _midGreen   = Color(0xFF2F5145);
const Color _fillGreen  = Color(0xFFC9DABF);
const Color _confirm    = Color(0xFF6F8E63);

class MyBooksPage extends StatefulWidget {
  const MyBooksPage({super.key});

  @override
  State<MyBooksPage> createState() => _MyBooksPageState();
}

class _MyBooksPageState extends State<MyBooksPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Required / optional fields
  final _titleCtrl = TextEditingController();
  File? _pdfFile;
  File? _coverFile;

  bool _saving = false;

  // Force showing validation messages even before the fields are touched
  bool _forceValidate = false;

  // Local TabController (nullable to avoid LateInitializationError on hot reload)
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() => setState(() {})); // Update button state when title changes
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  // ✅ Unified SnackBar — same green style everywhere
  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _midGreen,
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

  // Button is enabled only when: title is not empty + PDF selected + not currently saving
  bool get _isReadyToSave =>
      _titleCtrl.text.trim().isNotEmpty &&
          _pdfFile != null &&
          !_saving;

  void _backToHub(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LibraryTab()),
            (route) => false,
      );
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    if (!mounted) return;
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pdfFile = File(result.files.single.path!);
        _forceValidate = true; // Immediately show required-field errors
      });
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (!mounted) return;
    if (x != null) {
      setState(() => _coverFile = File(x.path));
    }
  }

  Future<void> _saveBook() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('الرجاء تسجيل الدخول لإضافة كتاب', icon: Icons.login_rounded);
      return;
    }

    // Enable validation errors if user tries to save while required fields are missing
    if (_titleCtrl.text.trim().isEmpty || _pdfFile == null) {
      setState(() => _forceValidate = true);
    }

    // Extra safety layer to avoid incomplete submissions
    if (_titleCtrl.text.trim().isEmpty || _pdfFile == null) {
      _showSnack(_missingFriendlyMessage(), icon: Icons.info_outline);
      return;
    }

    if (!_formKey.currentState!.validate()) {
      _showSnack('فضلاً أكمل الحقول المطلوبة', icon: Icons.info_outline);
      return;
    }

    try {
      setState(() => _saving = true);

      // Firestore document reference inside the current user's "mybooks" subcollection
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mybooks')
          .doc();

      // Storage path for this user's book
      final storage = FirebaseStorage.instance;
      final baseRef = storage.ref('users/${user.uid}/mybooks/${docRef.id}');
      final pdfRef = baseRef.child('book.pdf');

      // Upload PDF file
      final pdfTask = await pdfRef.putFile(_pdfFile!);
      final pdfUrl  = await pdfTask.ref.getDownloadURL();

      // Upload cover image (optional)
      String? coverUrl;
      if (_coverFile != null) {
        final coverRef = baseRef.child('cover.jpg');
        final coverTask = await coverRef.putFile(_coverFile!);
        coverUrl = await coverTask.ref.getDownloadURL();
      }

      // Store basic book data only (title + file URLs)
      await docRef.set({
        'title': _titleCtrl.text.trim(),
        'pdfUrl': pdfUrl,
        'coverUrl': coverUrl,
        'ownerUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Reset form fields after saving
      _formKey.currentState!.reset();
      setState(() {
        _titleCtrl.clear();
        _pdfFile = null;
        _coverFile = null;
        _forceValidate = false;
      });

      if (mounted) {
        _showSnack('تمت إضافة الكتاب بنجاح', icon: Icons.check_circle);
        // Switch to "My Books" tab directly after saving
        _tabController?.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('حدث خطأ أثناء الحفظ: $e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteBook(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
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
                  'تأكيد حذف الكتاب',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: _darkGreen),
                ),
                const SizedBox(height: 10),
                const Text(
                    'هل أنت متأكد أنك تريد حذف هذا الكتاب من مكتبتك؟',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirm,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('تأكيد', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء', style: TextStyle(fontSize: 16, color: _darkGreen)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final storage = FirebaseStorage.instance;
      final baseRef = storage.ref('users/${user.uid}/mybooks/${doc.id}');

      // Delete files quietly (ignore if missing)
      await Future.wait([
        baseRef.child('book.pdf').delete().catchError((_) {}),
        baseRef.child('cover.jpg').delete().catchError((_) {}),
      ]);

      await doc.reference.delete();

      if (mounted) {
        _showSnack('تم حذف الكتاب', icon: Icons.check_circle);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('تعذّر الحذف: $e', icon: Icons.error_outline);
      }
    }
  }

  // Friendly missing-fields message used only in SnackBars
  String _missingFriendlyMessage() {
    final nameMissing = _titleCtrl.text.trim().isEmpty;
    final pdfMissing = _pdfFile == null;
    if (nameMissing && pdfMissing) {
      return 'أضيف اسم الكتاب واخترِي ملف PDF أولاً ✨';
    } else if (nameMissing) {
      return 'أضيف اسم الكتاب أولاً ✍️';
    } else {
      return 'اختار ملف الكتاب (PDF) أولاً 📄';
    }
  }

  // ===== Add Book tab UI (title + PDF are required, cover is optional) =====
  Widget _buildAddTab() {
    final nameMissing = _titleCtrl.text.trim().isEmpty;
    final pdfMissing  = _pdfFile == null;

    // ✅ Show PDF validation message as soon as the title is not empty
    final showPdfValidation = _forceValidate || _titleCtrl.text.trim().isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back_private.png', fit: BoxFit.cover),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: AbsorbPointer(
                absorbing: _saving,
                child: Opacity(
                  opacity: _saving ? 0.6 : 1,
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _forceValidate
                        ? AutovalidateMode.always
                        : AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),

                        // Book title
                        _fieldContainer(
                          isError: _forceValidate && nameMissing,
                          child: TextFormField(
                            controller: _titleCtrl,
                            textAlign: TextAlign.right,
                            decoration: const InputDecoration(
                              labelText: 'اسم الكتاب *',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              labelStyle: TextStyle(color: _darkGreen),
                            ),
                            validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'اسم الكتاب مطلوب' : null,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ✅ PDF file selector (required)
                        _fileButton(
                          text: _pdfFile == null
                              ? 'اختيار ملف PDF *'
                              : 'تم اختيار: ${_pdfFile!.path.split('/').last}',
                          icon: Icons.picture_as_pdf,
                          onPressed: _pickPdf,
                          required: true,
                          isMissing: showPdfValidation && pdfMissing,
                        ),
                        const SizedBox(height: 14),

                        // Cover image selector (optional)
                        _fileButton(
                          text: _coverFile == null
                              ? 'اختيار صورة الغلاف (اختياري)'
                              : 'تم اختيار الغلاف',
                          icon: Icons.image_outlined,
                          onPressed: _pickCover,
                        ),

                        const SizedBox(height: 8),

                        // Save button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isReadyToSave ? _saveBook : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _confirm,
                              disabledBackgroundColor: _confirm.withOpacity(0.45),
                              disabledForegroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              _saving ? 'جارٍ الحفظ...' : 'حفظ',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
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
    );
  }

  // ===== "My Books" tab UI (shows only current user's books) =====
  Widget _buildMyListTab() {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back_private.png', fit: BoxFit.cover),
          ),
          if (user == null)
            const Center(child: Text('الرجاء تسجيل الدخول لعرض كتبك'))
          else
            SafeArea(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('mybooks')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_midGreen),
                      ),
                    );
                  }
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return const Center(child: Text('لا توجد كتب مضافة حتى الآن'));
                  }
                  final docs = snap.data!.docs;

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>? ?? {};
                      final title = (data['title'] ?? '') as String;
                      final coverUrl = (data['coverUrl'] ?? '') as String;

                      return Container(
                        decoration: BoxDecoration(
                          color: _fillGreen,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            if (coverUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  coverUrl,
                                  width: 44,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 60),
                                ),
                              )
                            else
                              const SizedBox(width: 44, height: 60),

                            const SizedBox(width: 12),

                            // Clickable title → opens book details page
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MyBookDetailsPage(bookId: doc.id),
                                    ),
                                  );
                                },
                                child: Text(
                                  title.isEmpty ? 'كتاب بدون عنوان' : title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: _darkGreen,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),

                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                                  onPressed: () => _deleteBook(doc),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // In very rare cases (during hot reload) _tabController might still be null for one frame
    if (_tabController == null) {
      return const SizedBox.shrink();
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back_private.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leadingWidth: 56,
              toolbarHeight: 170,
              leading: SafeArea(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, top: 55),
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => _backToHub(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _midGreen,
                      size: 22,
                    ),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Column(
                  children: [
                    const SizedBox(height: 70),
                    TabBar(
                      controller: _tabController,
                      labelColor: _darkGreen,
                      unselectedLabelColor: Colors.black54,
                      indicatorColor: _darkGreen,
                      tabs: const [
                        Tab(icon: Icon(Icons.add), text: 'إضافة كتاب'),
                        Tab(icon: Icon(Icons.library_books), text: 'كتبي'),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildAddTab(),
                _buildMyListTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================== Helper Widgets ==================

Widget _fieldContainer({required Widget child, bool isError = false}) {
  return Container(
    decoration: BoxDecoration(
      color: _fillGreen,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isError ? Colors.red : Colors.transparent,
        width: isError ? 1.2 : 0,
      ),
    ),
    child: child,
  );
}

Widget _fileButton({
  required String text,
  required IconData icon,
  required VoidCallback onPressed,
  bool required = false,
  bool isMissing = false,
}) {
  // Visually distinguish required/optional + show a small error label when needed
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: _darkGreen),
        label: Text(
          text,
          style: const TextStyle(color: _darkGreen),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: isMissing ? Colors.red : _darkGreen),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: _fillGreen,
        ),
      ),
      if (required && isMissing)
        const Padding(
          padding: EdgeInsetsDirectional.only(top: 6, start: 6, end: 6),
          child: Text(
            'هذا الحقل مطلوب',
            textAlign: TextAlign.right,
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
    ],
  );
}
