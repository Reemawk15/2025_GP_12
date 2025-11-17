import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class AdminBookManagerScreen extends StatefulWidget {
  const AdminBookManagerScreen({super.key});

  @override
  State<AdminBookManagerScreen> createState() => _AdminBookManagerScreenState();
}

class _AdminBookManagerScreenState extends State<AdminBookManagerScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Brand colors
  static const _confirmColor = Color(0xFF6F8E63); // Confirm buttons + SnackBar
  static const _titleColor   = Color(0xFF0E3A2C); // Dark green for texts
  static const _fillGreen    = Color(0xFFC9DABF); // Light green for fields

  // Layout constants
  static const double _kFieldH = 56;
  static const double _kGap    = 14;
  static const double _kDescH  = 120;

  // Book fields (Add tab)
  final _titleCtrl  = TextEditingController();
  final _authorCtrl = TextEditingController();
  String? _category;
  final _descCtrl   = TextEditingController(); // optional description

  // FocusNodes
  final _titleF  = FocusNode();
  final _authorF = FocusNode();
  final _descF   = FocusNode();

  // Picked files
  File? _pdfFile;
  File? _coverFile;

  bool _saving = false;

  // Categories
  final List<String> _categories = const [
    'الأدب والشعر',
    'التاريخ والجغرافيا',
    'التقنية والكمبيوتر',
    'القصة والرواية',
    'الكتب الإسلامية والدينية',
    'كتب الأطفال',
    'معلومات عامة',
    'تطوير الذات',
  ];

  // Unified SnackBar helper
  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirmColor,
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

  // Helper to mark required fields
  String _req(String label) => '$label *';

  // ---- Lifecycle ----
  @override
  void initState() {
    super.initState();
    // Listen to text changes so the Save button state is updated
    _titleCtrl.addListener(_onAddFormChanged);
    _authorCtrl.addListener(_onAddFormChanged);
    _descCtrl.addListener(_onAddFormChanged);
  }

  void _onAddFormChanged() {
    setState(() {}); // rebuild to re-check _isAddFormReady
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onAddFormChanged);
    _authorCtrl.removeListener(_onAddFormChanged);
    _descCtrl.removeListener(_onAddFormChanged);

    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descCtrl.dispose();
    _titleF.dispose();
    _authorF.dispose();
    _descF.dispose();
    super.dispose();
  }

  // Required fields for adding a book:
  // title, author, category, pdf file, cover file
  bool get _isAddFormReady {
    return _titleCtrl.text.trim().isNotEmpty &&
        _authorCtrl.text.trim().isNotEmpty &&
        _category != null &&
        _category!.trim().isNotEmpty &&
        _pdfFile != null &&
        _coverFile != null;
  }

  // ---- File pickers ----
  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _pdfFile = File(result.files.single.path!));
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) {
      setState(() => _coverFile = File(x.path));
    }
  }

  // ---- Add new book ----
  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) {
      _showSnack('فضلاً أكمل الحقول المطلوبة', icon: Icons.info_outline);
      return;
    }
    if (_pdfFile == null) {
      _showSnack('فضلاً اختر ملف الكتاب (PDF)', icon: Icons.info_outline);
      return;
    }
    if (_coverFile == null) {
      _showSnack('فضلاً اختر صورة الغلاف', icon: Icons.info_outline);
      return;
    }

    try {
      setState(() => _saving = true);

      final docRef = FirebaseFirestore.instance.collection('audiobooks').doc();
      final storage  = FirebaseStorage.instance;
      final pdfRef   = storage.ref('audiobooks/${docRef.id}/book.pdf');
      final coverRef = storage.ref('audiobooks/${docRef.id}/cover.jpg');

      final pdfTask   = await pdfRef.putFile(_pdfFile!);
      final coverTask = await coverRef.putFile(_coverFile!);

      final pdfUrl   = await pdfTask.ref.getDownloadURL();
      final coverUrl = await coverTask.ref.getDownloadURL();

      await docRef.set({
        'title': _titleCtrl.text.trim(),
        'author': _authorCtrl.text.trim(),
        'category': _category?.trim(),
        'description': _descCtrl.text.trim(),
        'pdfUrl': pdfUrl,
        'coverUrl': coverUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'published': true,
      });

      _formKey.currentState!.reset();
      setState(() {
        _pdfFile = null;
        _coverFile = null;
        _category = null;
      });

      // Show success message and "refresh" the whole screen
      if (!mounted) return;
      _showSnack('تم حفظ الكتاب بنجاح');

      // Replace current screen with a fresh instance so everything resets
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AdminBookManagerScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnack('حدث خطأ أثناء الحفظ: $e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- Delete book + all related data ----
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _titleColor,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد أنك تريد حذف هذا الكتاب؟ لن يكون متاحًا للمستخدمين.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirmColor,
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
                    child: const Text('إلغاء', style: TextStyle(fontSize: 16, color: _titleColor)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;

    final String bookId = doc.id;

    try {
      final firestore = FirebaseFirestore.instance;
      final storage  = FirebaseStorage.instance;

      // Collect all delete operations
      final List<Future> deletions = [];

      // 1) Delete main book files from Storage (pdf, cover)
      deletions.add(
        storage
            .ref('audiobooks/$bookId/book.pdf')
            .delete()
            .catchError((_) {}),
      );
      deletions.add(
        storage
            .ref('audiobooks/$bookId/cover.jpg')
            .delete()
            .catchError((_) {}),
      );

      // 2) Delete possible OCR text files (safe even if they do not exist)
      deletions.add(
        storage
            .ref('audiobooks/$bookId/ocr.txt')
            .delete()
            .catchError((_) {}),
      );
      deletions.add(
        storage
            .ref('ocr/$bookId.txt')
            .delete()
            .catchError((_) {}),
      );

      // 3) Delete OCR result document in Firestore (if you store it there)
      deletions.add(
        firestore
            .collection('ocr_results')
            .doc(bookId)
            .delete()
            .catchError((_) {}),
      );

      // 4) Delete reviews AND shelves entries from every user
      final usersSnap = await firestore.collection('users').get();
      for (final userDoc in usersSnap.docs) {
        // 4.a) Delete all reviews for this book from "reviews" subcollection
        final reviewsSnap = await userDoc.reference
            .collection('reviews')
            .where('bookId', isEqualTo: bookId)
            .get();

        for (final reviewDoc in reviewsSnap.docs) {
          deletions.add(reviewDoc.reference.delete());
        }

        // 4.b) Delete this book from user's shelves ("library" subcollection)
        final librarySnap = await userDoc.reference
            .collection('library')
            .where('bookId', isEqualTo: bookId)
            .get();

        for (final libDoc in librarySnap.docs) {
          deletions.add(libDoc.reference.delete());
        }
      }

      // 5) Finally delete the audiobook document itself
      deletions.add(doc.reference.delete());

      await Future.wait(deletions);

      if (mounted) _showSnack('تم حذف الكتاب بنجاح');
    } catch (e, st) {
      debugPrint('Error deleting book $bookId: $e\n$st');
      if (mounted) _showSnack('تعذّر الحذف: $e', icon: Icons.error_outline);
    }
  }

  // Open edit page (pencil icon)
  void _openEdit(DocumentSnapshot doc, Map<String, dynamic> data) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EditBookPage(
        docId: doc.id,
        initialData: data,
        categories: _categories,
      ),
    ));
  }

  // ================== Tabs content ==================

  Widget _buildAddTab() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back1.png', fit: BoxFit.cover),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: AbsorbPointer(
                absorbing: _saving,
                child: Opacity(
                  opacity: _saving ? 0.6 : 1,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'الحقول المشار إليها بـ * مطلوبة',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Book title (required)
                        _sizedField(
                          height: _kFieldH,
                          child: _styledField(
                            controller: _titleCtrl,
                            label: _req('اسم الكتاب'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'اسم الكتاب مطلوب' : null,
                            focusNode: _titleF,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // Author name (required)
                        _sizedField(
                          height: _kFieldH,
                          child: _styledField(
                            controller: _authorCtrl,
                            label: _req('اسم المؤلف'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'اسم المؤلف مطلوب' : null,
                            focusNode: _authorF,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // Category (required)
                        _sizedField(
                          height: _kFieldH,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _fillGreen,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: DropdownButtonFormField<String>(
                              value: _category,
                              dropdownColor: _fillGreen,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                              ).copyWith(
                                labelText: _req('التصنيف'),
                              ),
                              items: _categories
                                  .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ))
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _category = v);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // Description (optional)
                        _sizedField(
                          height: _kDescH,
                          child: _styledField(
                            controller: _descCtrl,
                            label: 'وصف مختصر',
                            maxLines: 5,
                            focusNode: _descF,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // PDF file (required)
                        _sizedField(
                          height: _kFieldH,
                          child: _fileButton(
                            text: _pdfFile == null
                                ? _req('اختيار ملف PDF')
                                : 'تم اختيار: ${_pdfFile!.path.split('/').last}',
                            icon: Icons.picture_as_pdf,
                            onPressed: _pickPdf,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // Cover image (required)
                        _sizedField(
                          height: _kFieldH,
                          child: _fileButton(
                            text: _coverFile == null
                                ? _req('اختيار صورة الغلاف')
                                : 'تم اختيار: ${_coverFile!.path.split('/').last}',
                            icon: Icons.image,
                            onPressed: _pickCover,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Save button: disabled if saving OR required fields are not filled
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                            (_saving || !_isAddFormReady) ? null : _saveBook,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _confirmColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _saving
                                ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                    AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'جار الحفظ...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                                : const Text(
                              'حفظ',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
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

  Widget _buildListTab() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back1.png', fit: BoxFit.cover),
          ),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('audiobooks')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('لا توجد كتب مضافة حتى الآن'));
                }
                final docs = snap.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final title = (data['title'] ?? '') as String;
                    final author = (data['author'] ?? '') as String;

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
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Texts (left)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.isEmpty ? 'اسم الكتاب' : title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  style: const TextStyle(
                                    color: _titleColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    color: _titleColor.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Icons (right)
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'تعديل',
                                icon: const Icon(Icons.edit_outlined, color: _titleColor),
                                onPressed: () => _openEdit(doc, data),
                              ),
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
    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/images/back1.png', fit: BoxFit.cover),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leadingWidth: 56,
                toolbarHeight: 75,
                leading: SafeArea(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
                    child: IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Stack(
                        alignment: Alignment.center,
                        children: const [
                          Icon(Icons.arrow_back, size: 30, color: Colors.white70),
                          Icon(Icons.arrow_back, size: 26, color: Color(0xFF0E3A2C)),
                        ],
                      ),
                    ),
                  ),
                ),
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(100),
                  child: Column(
                    children: [
                      SizedBox(height: 60),
                      TabBar(
                        labelColor: _titleColor,
                        unselectedLabelColor: Colors.black54,
                        indicatorColor: _titleColor,
                        tabs: [
                          Tab(icon: Icon(Icons.add), text: 'إضافة كتاب'),
                          Tab(icon: Icon(Icons.library_books), text: 'الكتب المضافة'),
                        ],
                      ),
                      SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              body: TabBarView(
                children: [
                  _AddTabHost(),
                  _ListTabHost(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== Helper widgets ==================

// Wrapper to control height for a child widget
Widget _sizedField({required double height, required Widget child}) {
  return SizedBox(height: height, child: child);
}

// Styled text field widget (supports hintText for placeholders)
Widget _styledField({
  required TextEditingController controller,
  required String label,
  String? Function(String?)? validator,
  int maxLines = 1,
  FocusNode? focusNode,
  ValueChanged<String>? onFieldSubmitted,
  bool readOnly = false,
  String? hintText,
}) {
  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFFC9DABF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      focusNode: focusNode,
      readOnly: readOnly,
      onFieldSubmitted: onFieldSubmitted,
      textAlign: TextAlign.right,
      decoration: const InputDecoration(
        labelStyle: TextStyle(color: Color(0xFF0E3A2C)),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ).copyWith(labelText: label, hintText: hintText),
    ),
  );
}

// File/image picker button
Widget _fileButton({
  required String text,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, color: const Color(0xFF0E3A2C)),
    label: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Color(0xFF0E3A2C)),
    ),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Color(0xFF0E3A2C)),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFFC9DABF),
    ),
  );
}

// Simple wrappers because TabBarView needs constant widgets
class _AddTabHost extends StatelessWidget {
  const _AddTabHost();

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_AdminBookManagerScreenState>();
    return parent?._buildAddTab() ?? const SizedBox();
  }
}

class _ListTabHost extends StatelessWidget {
  const _ListTabHost();

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_AdminBookManagerScreenState>();
    return parent?._buildListTab() ?? const SizedBox();
  }
}

// ================== Edit book page ==================

class _EditBookPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> initialData;
  final List<String> categories;

  const _EditBookPage({
    required this.docId,
    required this.initialData,
    required this.categories,
  });

  @override
  State<_EditBookPage> createState() => _EditBookPageState();
}

class _EditBookPageState extends State<_EditBookPage> {
  final _formKey = GlobalKey<FormState>();

  static const double kAppBarHeight   = 120;
  static const double kTitleTopOffset = 90;
  static const double kPageTopOffset  = 40;
  static const double kFormTopOffset  = 30;

  static const _titleColor   = Color(0xFF0E3A2C);
  static const _fillGreen    = Color(0xFFC9DABF);
  static const _confirmColor = Color(0xFF6F8E63);

  static const double _kFieldH = 56;
  static const double _kGap    = 14;
  static const double _kDescH  = 120;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _descCtrl;

  String? _category;

  File? _newPdfFile;
  File? _newCoverFile;

  bool _saving = false;

  String? _currentPdfUrl;
  String? _currentCoverUrl;

  // Local unified SnackBar
  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirmColor,
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

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;

    _titleCtrl  = TextEditingController(text: (data['title'] ?? '').toString());
    _authorCtrl = TextEditingController(text: (data['author'] ?? '').toString());
    _descCtrl   = TextEditingController(text: (data['description'] ?? '').toString());

    final cat = (data['category'] ?? '').toString().trim();
    _category = cat.isEmpty ? null : cat;

    final pdf = (data['pdfUrl'] ?? '').toString().trim();
    final cov = (data['coverUrl'] ?? '').toString().trim();
    _currentPdfUrl   = pdf.isEmpty ? null : pdf;
    _currentCoverUrl = cov.isEmpty ? null : cov;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _newPdfFile = File(result.files.single.path!));
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) {
      setState(() => _newCoverFile = File(x.path));
    }
  }

  Future<void> _saveEdits() async {
    if (!_formKey.currentState!.validate()) {
      _showSnack('فضلاً أكمل الحقول المطلوبة', icon: Icons.info_outline);
      return;
    }

    try {
      setState(() => _saving = true);

      final docRef   = FirebaseFirestore.instance.collection('audiobooks').doc(widget.docId);
      final storage  = FirebaseStorage.instance;
      final pdfRef   = storage.ref('audiobooks/${widget.docId}/book.pdf');
      final coverRef = storage.ref('audiobooks/${widget.docId}/cover.jpg');

      String? pdfUrl   = _currentPdfUrl;
      String? coverUrl = _currentCoverUrl;

      if (_newPdfFile != null) {
        final task = await pdfRef.putFile(_newPdfFile!);
        pdfUrl = await task.ref.getDownloadURL();
      }
      if (_newCoverFile != null) {
        final task = await coverRef.putFile(_newCoverFile!);
        coverUrl = await task.ref.getDownloadURL();
      }

      await docRef.update({
        'title': _titleCtrl.text.trim(),
        'author': _authorCtrl.text.trim(),
        'category': _category?.trim(),
        'description': _descCtrl.text.trim(),
        if (pdfUrl != null) 'pdfUrl': pdfUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack('تم حفظ تعديلاتك');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showSnack('تعذّر حفظ التعديلات: $e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Show full image (no cropping) inside fixed 80x100 box
    Widget coverPreview;
    if (_newCoverFile != null) {
      coverPreview = Image.file(
        _newCoverFile!,
        fit: BoxFit.contain, // ← يعرض كل الصورة بدون قص
      );
    } else if (_currentCoverUrl != null) {
      coverPreview = Image.network(
        _currentCoverUrl!,
        fit: BoxFit.contain, // ← نفس الشي للرابط الحالي
      );
    } else {
      coverPreview = Container(
        color: Colors.white24,
        child: const Icon(Icons.image, size: 40, color: _titleColor),
      );
    }

    final pdfButtonText = _newPdfFile != null
        ? 'تم اختيار: ${_newPdfFile!.path.split('/').last}'
        : (_currentPdfUrl != null
        ? 'الملف الحالي: book.pdf (اضغط لاستبداله)'
        : 'اختيار ملف PDF');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back1.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: kAppBarHeight,
              leadingWidth: 56,
              leading: SafeArea(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Stack(
                      alignment: Alignment.center,
                      children: const [
                        Icon(Icons.arrow_back, size: 30, color: Colors.white70),
                        Icon(Icons.arrow_back, size: 26, color: _titleColor),
                      ],
                    ),
                  ),
                ),
              ),
              title: Padding(
                padding: EdgeInsets.only(top: kTitleTopOffset),
                child: const Text(
                  'تفاصيل الكتاب',
                  style: TextStyle(color: _titleColor, fontWeight: FontWeight.w600),
                ),
              ),
              centerTitle: true,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, kPageTopOffset, 16, 24),
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: Opacity(
                    opacity: _saving ? 0.6 : 1,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          SizedBox(height: kFormTopOffset),

                          // Cover + change button
                          Container(
                            decoration: BoxDecoration(
                              color: _fillGreen,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 80,
                                    height: 100,
                                    child: coverPreview, // 👈 الصورة بنفس المقاس وتظهر كاملة
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _fileButton(
                                    text: _newCoverFile == null
                                        ? 'تغيير صورة الغلاف'
                                        : 'تم اختيار غلاف جديد',
                                    icon: Icons.image_outlined,
                                    onPressed: _pickCover,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kFieldH,
                            child: _styledField(
                              controller: _titleCtrl,
                              label: 'اسم الكتاب',
                              hintText: (_titleCtrl.text.trim().isEmpty)
                                  ? 'لا يوجد عنوان'
                                  : null,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'اسم الكتاب مطلوب'
                                  : null,
                            ),
                          ),
                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kFieldH,
                            child: _styledField(
                              controller: _authorCtrl,
                              label: 'اسم المؤلف',
                              hintText: (_authorCtrl.text.trim().isEmpty)
                                  ? 'لا يوجد مؤلف'
                                  : null,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'اسم المؤلف مطلوب'
                                  : null,
                            ),
                          ),
                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kFieldH,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _fillGreen,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: DropdownButtonFormField<String>(
                                value: (widget.categories.contains(_category))
                                    ? _category
                                    : null,
                                dropdownColor: _fillGreen,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  labelText: 'التصنيف',
                                ),
                                items: widget.categories
                                    .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ))
                                    .toList(),
                                onChanged: (v) => setState(() => _category = v),
                              ),
                            ),
                          ),

                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kDescH,
                            child: _styledField(
                              controller: _descCtrl,
                              label: 'وصف مختصر',
                              hintText: (_descCtrl.text.trim().isEmpty)
                                  ? 'لا توجد نبذة'
                                  : null,
                              maxLines: 5,
                            ),
                          ),

                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kFieldH,
                            child: _fileButton(
                              text: pdfButtonText,
                              icon: Icons.picture_as_pdf,
                              onPressed: _pickPdf,
                            ),
                          ),

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _saveEdits,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _confirmColor,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _saving
                                  ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'جار الحفظ...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                                  : const Text(
                                'حفظ التعديلات',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
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
          ),
        ],
      ),
    );
  }
}
