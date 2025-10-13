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

class _AdminBookManagerScreenState extends State<AdminBookManagerScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // ألوان حوار التأكيد مطابقة لصفحة الأدمن
  static const _confirmColor = Color(0xFF6F8E63);
  static const _titleColor   = Color(0xFF0E3A2C);

  // حقول الكتاب
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  String? _category;
  final _descCtrl = TextEditingController();

  // الملفات
  File? _pdfFile;
  File? _coverFile;

  bool _saving = false;

  // لعرض أقسام مسبقة في الدروب داون (قابلة للتعديل)
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
    // تحقّق من الحقول الإلزامية
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

      // 1) أنشئ وثيقة مبدئية للحصول على docId
      final docRef = FirebaseFirestore.instance.collection('audiobooks').doc();

      // 2) ارفع الملفات إلى Storage بمسارات مرتبة
      final storage = FirebaseStorage.instance;
      final pdfRef   = storage.ref('audiobooks/${docRef.id}/book.pdf');
      final coverRef = storage.ref('audiobooks/${docRef.id}/cover.jpg');

      final pdfTask = await pdfRef.putFile(_pdfFile!);
      final coverTask = await coverRef.putFile(_coverFile!);

      final pdfUrl = await pdfTask.ref.getDownloadURL();
      final coverUrl = await coverTask.ref.getDownloadURL();

      // 3) خزّن البيانات في Firestore
      await docRef.set({
        'title': _titleCtrl.text.trim(),
        'author': _authorCtrl.text.trim(),
        'category': _category?.trim(),
        'description': _descCtrl.text.trim(),
        'pdfUrl': pdfUrl,
        'coverUrl': coverUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'published': true, // منشور لعرضه مباشرة في المكتبة العامة
      });

      // 4) نظّف الحقول + رسالة نجاح
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
    // نافذة تأكيد بنفس شكل "تأكيد تسجيل الخروج"
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
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontSize: 16, color: _titleColor),
                    ),
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
      // احذف الملفات من Storage إن وجدت
      final storage = FirebaseStorage.instance;
      final pdfRef   = storage.ref('audiobooks/${doc.id}/book.pdf');
      final coverRef = storage.ref('audiobooks/${doc.id}/cover.jpg');

      await Future.wait([
        pdfRef.delete().catchError((_) {}),
        coverRef.delete().catchError((_) {}),
      ]);

      // احذف الوثيقة من Firestore
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

  Widget _buildAddTab() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AbsorbPointer(
          absorbing: _saving,
          child: Opacity(
            opacity: _saving ? 0.65 : 1,
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // العنوان
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الكتاب *',
                      hintText: 'مثال: الخيميائي',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'العنوان مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  // المؤلف
                  TextFormField(
                    controller: _authorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المؤلف *',
                      hintText: 'مثال: باولو كويلو',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم المؤلف مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  // التصنيف (اختياري)
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'التصنيف (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 12),
                  // وصف مختصر (اختياري)
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'وصف مختصر (اختياري)',
                      hintText: 'نبذة قصيرة عن الكتاب',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // اختيار الملفات
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickPdf,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: Text(_pdfFile == null ? 'اختيار ملف PDF' : 'تم اختيار: ${_pdfFile!.path.split('/').last}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickCover,
                          icon: const Icon(Icons.image),
                          label: Text(_coverFile == null ? 'اختيار صورة الغلاف' : 'تم اختيار الغلاف'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveBook,
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListTab() {
    return Directionality(
      textDirection: TextDirection.rtl,
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
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final title = (data['title'] ?? '') as String;
              final author = (data['author'] ?? '') as String;
              final cover = (data['coverUrl'] ?? '') as String;
              final category = (data['category'] ?? '') as String;

              return Card(
                child: ListTile(
                  leading: cover.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(cover, width: 48, height: 64, fit: BoxFit.cover),
                  )
                      : const Icon(Icons.menu_book, size: 36),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    category.isNotEmpty ? '$author • $category' : author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    onPressed: () => _deleteBook(doc),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('إدارة الكتب'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.add), text: 'إضافة كتاب'),
                Tab(icon: Icon(Icons.library_books), text: 'الكتب المضافة'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              // إضافة
              _AddTabHost(),
              // قائمة
              _ListTabHost(),
            ],
          ),
        ),
      ),
    );
  }
}

// التفاف بسيط لأن TabBarView يحتاج Widgets ثابتة
class _AddTabHost extends StatelessWidget {
  const _AddTabHost();

  @override
  Widget build(BuildContext context) {
    // نصل إلى State الفعلي للأب عبر context.findAncestorStateOfType
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
