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

  // ألوان ثابتة
  static const _confirmColor = Color(0xFF6F8E63); // زر حفظ وتأكيد
  static const _titleColor   = Color(0xFF0E3A2C); // أخضر داكن للنصوص
  static const _fillGreen    = Color(0xFFC9DABF); // أخضر فاتح لحقول الإدخال

  // أبعاد
  static const double _kFieldH = 56;
  static const double _kGap    = 14;
  static const double _kDescH  = 120;

  // حقول الكتاب
  final _titleCtrl  = TextEditingController();
  final _authorCtrl = TextEditingController();
  String? _category;
  final _descCtrl   = TextEditingController();

  // FocusNodes (لو حبيتي ترجعي للنقاط لاحقًا)
  final _titleF  = FocusNode();
  final _authorF = FocusNode();
  final _descF   = FocusNode();

  // الملفات
  File? _pdfFile;
  File? _coverFile;

  bool _saving = false;

  // أقسام
  final _categories = const [
    'تطوير ذات',
    'روايات',
    'تقنية',
    'دين',
    'تاريخ',
    'علم نفس',
    'تعليمي',
    'أعمال',
    'أطفال',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descCtrl.dispose();
    _titleF.dispose();
    _authorF.dispose();
    _descF.dispose();
    super.dispose();
  }

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

  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فضلاً أكمل الحقول المطلوبة')),
      );
      return;
    }
    if (_pdfFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فضلاً اختر ملف الكتاب (PDF)')),
      );
      return;
    }
    if (_coverFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فضلاً اختر صورة الغلاف')),
      );
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة الكتاب بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
        );
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

    try {
      final storage  = FirebaseStorage.instance;
      final pdfRef   = storage.ref('audiobooks/${doc.id}/book.pdf');
      final coverRef = storage.ref('audiobooks/${doc.id}/cover.jpg');

      await Future.wait([
        pdfRef.delete().catchError((_) {}),
        coverRef.delete().catchError((_) {}),
      ]);

      await doc.reference.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الكتاب بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر الحذف: $e')),
        );
      }
    }
  }

  // ================== واجهات التبويبات ==================

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
                        // اسم الكتاب
                        _sizedField(
                          height: _kFieldH,
                          child: _styledField(
                            controller: _titleCtrl,
                            label: 'اسم الكتاب',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'اسم الكتاب مطلوب' : null,
                            focusNode: _titleF,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // اسم المؤلف
                        _sizedField(
                          height: _kFieldH,
                          child: _styledField(
                            controller: _authorCtrl,
                            label: 'اسم المؤلف',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'اسم المؤلف مطلوب' : null,
                            focusNode: _authorF,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // التصنيف
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
                                labelText: 'التصنيف',
                              ),
                              items: _categories
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

                        // وصف مختصر
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

                        // PDF
                        _sizedField(
                          height: _kFieldH,
                          child: _fileButton(
                            text: _pdfFile == null
                                ? 'اختيار ملف PDF'
                                : 'تم اختيار: ${_pdfFile!.path.split('/').last}',
                            icon: Icons.picture_as_pdf,
                            onPressed: _pickPdf,
                          ),
                        ),
                        const SizedBox(height: _kGap),

                        // الغلاف
                        _sizedField(
                          height: _kFieldH,
                          child: _fileButton(
                            text: _coverFile == null
                                ? 'اختيار صورة الغلاف'
                                : 'تم اختيار الغلاف',
                            icon: Icons.image,
                            onPressed: _pickCover,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // زر الحفظ
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveBook,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _confirmColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _saving ? 'جارٍ الحفظ...' : 'حفظ',
                              style: const TextStyle(
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, // توزيع الطرفين
                        children: [
                          // ✅ النصوص (يسار)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, // يخليها يسار
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

                          // ✅ الأيقونات (يمين)
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'تعديل (لاحقاً)',
                                icon: const Icon(Icons.edit_outlined, color: _titleColor),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ميزة التعديل ستُضاف لاحقًا')),
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_forever, color: Colors.red),
                                onPressed: () => _deleteBook(doc),
                              ),
                            ],
                          ),
                        ],
                      )
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
                toolbarHeight: 75, // يبعده شوي عن الحافة ويخليه تحت الستاتس بار
                leading: SafeArea(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
                    child: IconButton(
                      tooltip: 'رجوع',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Stack(
                        alignment: Alignment.center,
                        children: const [
                          // هالة خفيفة خلف السهم (بدون دائرة)
                          Icon(Icons.arrow_back,
                              size: 30, color: Colors.white70),
                          Icon(Icons.arrow_back,
                              size: 26, color: Color(0xFF0E3A2C)), // _titleColor
                        ],
                      ),
                    ),
                  ),
                ),
                // 👇 "نزول" التبويبات: زيدي القيمتين إذا تبين تنزل أكثر
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(100), // <-- غيّري الرقم للنزول العام
                  child: Column(
                    children: const [
                      SizedBox(height: 60),                // <-- زيديه لين يوصل المكان اللي تبين
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
              body: const TabBarView(
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

// ================== Widgets مساعدة ==================

// غلاف لضبط ارتفاع أي ويدجت (ما يغيّر السلوك)
Widget _sizedField({required double height, required Widget child}) {
  return SizedBox(height: height, child: child);
}

// حقل إدخال مصمم
Widget _styledField({
  required TextEditingController controller,
  required String label,
  String? Function(String?)? validator,
  int maxLines = 1,
  FocusNode? focusNode,
  ValueChanged<String>? onFieldSubmitted,
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
      onFieldSubmitted: onFieldSubmitted,
      textAlign: TextAlign.right,
      decoration: const InputDecoration(
        labelStyle: TextStyle(color: Color(0xFF0E3A2C)),
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ).copyWith(labelText: label),
    ),
  );
}

// زر اختيار ملف/صورة
Widget _fileButton({
  required String text,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, color: const Color(0xFF0E3A2C)),
    label: Text(text, style: const TextStyle(color: Color(0xFF0E3A2C))),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Color(0xFF0E3A2C)),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFFC9DABF),
    ),
  );
}

// التفاف بسيط لأن TabBarView يحتاج Widgets ثابتة
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