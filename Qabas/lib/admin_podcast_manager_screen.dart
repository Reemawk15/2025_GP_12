import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class AdminPodcastManagerScreen extends StatefulWidget {
  const AdminPodcastManagerScreen({super.key});

  @override
  State<AdminPodcastManagerScreen> createState() =>
      _AdminPodcastManagerScreenState();
}

class _AdminPodcastManagerScreenState extends State<AdminPodcastManagerScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Brand colors
  static const _confirmColor = Color(0xFF6F8E63);
  static const _titleColor = Color(0xFF0E3A2C);
  static const _fillGreen = Color(0xFFC9DABF);

  // Layout
  static const double _kFieldH = 56;
  static const double _kGap = 14;
  static const double _kDescH = 120;

  // Podcast fields
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _category; // ✅ NEW: category

  final _titleF = FocusNode();
  final _descF = FocusNode();

  File? _audioFile; // mp3/m4a/wav
  File? _coverFile;

  bool _saving = false;

  // Categories (same as books)
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

  // Snack
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
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _req(String label) => '$label *';

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onFormChanged);
    _descCtrl.addListener(_onFormChanged);
  }

  void _onFormChanged() => setState(() {});

  @override
  void dispose() {
    _titleCtrl.removeListener(_onFormChanged);
    _descCtrl.removeListener(_onFormChanged);

    _titleCtrl.dispose();
    _descCtrl.dispose();
    _titleF.dispose();
    _descF.dispose();
    super.dispose();
  }

  bool get _isFormReady {
    return _titleCtrl.text.trim().isNotEmpty &&
        _category != null &&
        _category!.trim().isNotEmpty &&
        _audioFile != null &&
        _coverFile != null;
  }

  // ---------- pickers ----------
  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _audioFile = File(result.files.single.path!));
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x =
    await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _coverFile = File(x.path));
  }

  // ---------- save ----------
  Future<void> _savePodcast() async {
    if (!_formKey.currentState!.validate()) {
      _showSnack('فضلاً أكمل الحقول المطلوبة', icon: Icons.info_outline);
      return;
    }
    if (_audioFile == null) {
      _showSnack('فضلاً اختر ملف الصوت', icon: Icons.info_outline);
      return;
    }
    if (_coverFile == null) {
      _showSnack('فضلاً اختر صورة الغلاف', icon: Icons.info_outline);
      return;
    }

    try {
      setState(() => _saving = true);

      final docRef = FirebaseFirestore.instance.collection('podcasts').doc();
      final storage = FirebaseStorage.instance;

      final ext = _audioFile!.path.split('.').last.toLowerCase();
      final audioRef = storage.ref('podcasts/${docRef.id}/audio.$ext');
      final coverRef = storage.ref('podcasts/${docRef.id}/cover.jpg');

      final audioTask = await audioRef.putFile(_audioFile!);
      final coverTask = await coverRef.putFile(_coverFile!);

      final audioUrl = await audioTask.ref.getDownloadURL();
      final coverUrl = await coverTask.ref.getDownloadURL();

      await docRef.set({
        'title': _titleCtrl.text.trim(),
        'category': _category?.trim(), // ✅ NEW
        'description': _descCtrl.text.trim(),
        'audioUrl': audioUrl,
        'audioExt': ext, // ✅ يساعد في الحذف/التعديل
        'coverUrl': coverUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _formKey.currentState!.reset();
      setState(() {
        _titleCtrl.clear();
        _descCtrl.clear();
        _category = null; // ✅ NEW
        _audioFile = null;
        _coverFile = null;
      });

      if (!mounted) return;
      _showSnack('تم حفظ البودكاست بنجاح');
    } catch (e) {
      if (mounted) {
        _showSnack('حدث خطأ أثناء الحفظ: $e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- delete ----------
  Future<void> _deletePodcast(DocumentSnapshot doc) async {
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
                  'تأكيد حذف البودكاست',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _titleColor,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد أنك تريد حذف هذا البودكاست؟ لن يكون متاحًا للمستخدمين.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirmColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('تأكيد',
                        style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء',
                        style: TextStyle(fontSize: 16, color: _titleColor)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;

    final podcastId = doc.id;

    try {
      final storage = FirebaseStorage.instance;

      final data = doc.data() as Map<String, dynamic>? ?? {};
      final audioExt = (data['audioExt'] ?? '').toString().trim().toLowerCase();

      final deletions = <Future>[];

      // cover
      deletions.add(
        storage
            .ref('podcasts/$podcastId/cover.jpg')
            .delete()
            .catchError((_) {}),
      );

      // audio
      if (audioExt.isNotEmpty) {
        deletions.add(
          storage
              .ref('podcasts/$podcastId/audio.$audioExt')
              .delete()
              .catchError((_) {}),
        );
      } else {
        for (final ext in const ['mp3', 'm4a', 'wav']) {
          deletions.add(
            storage
                .ref('podcasts/$podcastId/audio.$ext')
                .delete()
                .catchError((_) {}),
          );
        }
      }

      // doc
      deletions.add(doc.reference.delete());

      await Future.wait(deletions);

      if (mounted) _showSnack('تم حذف البودكاست بنجاح');
    } catch (e) {
      if (mounted) _showSnack('تعذّر الحذف: $e', icon: Icons.error_outline);
    }
  }

  // ---------- edit ----------
  void _openEditPodcast(DocumentSnapshot doc, Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EditPodcastPage(
          docId: doc.id,
          initialData: data,
          categories: _categories, // ✅ NEW
        ),
      ),
    );
  }

  // ================== Tabs UI ==================

  Widget _buildAddTab() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/admin2.png', fit: BoxFit.cover),
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

                        _sizedField(
                          height: _kFieldH,
                          child: _styledField(
                            controller: _titleCtrl,
                            label: _req('عنوان البودكاست'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'عنوان البودكاست مطلوب'
                                : null,
                            focusNode: _titleF,
                          ),
                        ),

                        const SizedBox(height: _kGap),

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

                        // ✅ Category (required)
                        _sizedField(
                          height: _kFieldH,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _fillGreen,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: DropdownButtonFormField<String>(
                              value: _categories.contains(_category)
                                  ? _category
                                  : null,
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
                              onChanged: (v) => setState(() => _category = v),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'التصنيف مطلوب'
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: _kGap),

                        _sizedField(
                          height: _kFieldH,
                          child: _fileButton(
                            text: _audioFile == null
                                ? _req('اختيار ملف الصوت')
                                : 'تم اختيار: ${_audioFile!.path.split('/').last}',
                            icon: Icons.podcasts,
                            onPressed: _pickAudio,
                          ),
                        ),

                        const SizedBox(height: _kGap),

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

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                            (_saving || !_isFormReady) ? null : _savePodcast,
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
            child: Image.asset('assets/images/admin2.png', fit: BoxFit.cover),
          ),
          SafeArea(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('podcasts')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                      child: Text('لا توجد بودكاستات مضافة حتى الآن'));
                }

                final docs = snap.data!.docs;

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>? ?? {};

                    final title = (data['title'] ?? '').toString();
                    final cat = (data['category'] ?? '').toString();
                    final desc = (data['description'] ?? '').toString();

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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title.isEmpty ? 'عنوان البودكاست' : title,
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
                                  cat.isEmpty ? '—' : cat,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    color: _titleColor.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  desc.isEmpty ? '—' : desc,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    color: _titleColor.withOpacity(0.75),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'تعديل',
                                icon: const Icon(Icons.edit_outlined,
                                    color: _titleColor),
                                onPressed: () => _openEditPodcast(doc, data),
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_forever,
                                    color: Colors.red),
                                onPressed: () => _deletePodcast(doc),
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

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/images/admin2.png', fit: BoxFit.cover),
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
                          Icon(Icons.arrow_back,
                              size: 30, color: Colors.white70),
                          Icon(Icons.arrow_back,
                              size: 26, color: Color(0xFF0E3A2C)),
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
                          Tab(icon: Icon(Icons.add), text: 'إضافة بودكاست'),
                          Tab(
                              icon: Icon(Icons.podcasts),
                              text: 'البودكاست المضاف'),
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

// ================== Helper widgets ==================

Widget _sizedField({required double height, required Widget child}) {
  return SizedBox(height: height, child: child);
}

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

// TabBarView needs stable widgets
class _AddTabHost extends StatelessWidget {
  const _AddTabHost();

  @override
  Widget build(BuildContext context) {
    final parent =
    context.findAncestorStateOfType<_AdminPodcastManagerScreenState>();
    return parent?._buildAddTab() ?? const SizedBox();
  }
}

class _ListTabHost extends StatelessWidget {
  const _ListTabHost();

  @override
  Widget build(BuildContext context) {
    final parent =
    context.findAncestorStateOfType<_AdminPodcastManagerScreenState>();
    return parent?._buildListTab() ?? const SizedBox();
  }
}

// ================== Edit podcast page ==================

class _EditPodcastPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> initialData;
  final List<String> categories; // ✅ NEW

  const _EditPodcastPage({
    required this.docId,
    required this.initialData,
    required this.categories,
  });

  @override
  State<_EditPodcastPage> createState() => _EditPodcastPageState();
}

class _EditPodcastPageState extends State<_EditPodcastPage> {
  final _formKey = GlobalKey<FormState>();

  // Same offsets like edit book
  static const double kAppBarHeight = 120;
  static const double kTitleTopOffset = 90;
  static const double kPageTopOffset = 40;
  static const double kFormTopOffset = 30;

  static const _titleColor = Color(0xFF0E3A2C);
  static const _fillGreen = Color(0xFFC9DABF);
  static const _confirmColor = Color(0xFF6F8E63);

  static const double _kFieldH = 56;
  static const double _kGap = 14;
  static const double _kDescH = 120;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  String? _category; // ✅ NEW

  File? _newAudioFile;
  File? _newCoverFile;

  String? _currentAudioUrl;
  String? _currentCoverUrl;
  String? _currentAudioExt;

  bool _saving = false;

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
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
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

    _titleCtrl = TextEditingController(text: (data['title'] ?? '').toString());
    _descCtrl =
        TextEditingController(text: (data['description'] ?? '').toString());

    final cat = (data['category'] ?? '').toString().trim();
    _category = cat.isEmpty ? null : cat;

    final a = (data['audioUrl'] ?? '').toString().trim();
    final c = (data['coverUrl'] ?? '').toString().trim();
    final ext = (data['audioExt'] ?? '').toString().trim().toLowerCase();

    _currentAudioUrl = a.isEmpty ? null : a;
    _currentCoverUrl = c.isEmpty ? null : c;
    _currentAudioExt = ext.isEmpty ? null : ext;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _newAudioFile = File(result.files.single.path!));
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x =
    await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) setState(() => _newCoverFile = File(x.path));
  }

  Future<void> _saveEdits() async {
    if (!_formKey.currentState!.validate()) {
      _showSnack('فضلاً أكمل الحقول المطلوبة', icon: Icons.info_outline);
      return;
    }

    try {
      setState(() => _saving = true);

      final docRef =
      FirebaseFirestore.instance.collection('podcasts').doc(widget.docId);
      final storage = FirebaseStorage.instance;

      String? audioUrl = _currentAudioUrl;
      String? coverUrl = _currentCoverUrl;
      String? audioExt = _currentAudioExt;

      // Change audio + delete old if ext differs
      if (_newAudioFile != null) {
        final newExt = _newAudioFile!.path.split('.').last.toLowerCase();
        final newAudioRef =
        storage.ref('podcasts/${widget.docId}/audio.$newExt');

        final task = await newAudioRef.putFile(_newAudioFile!);
        audioUrl = await task.ref.getDownloadURL();

        if (audioExt != null && audioExt.isNotEmpty && audioExt != newExt) {
          await storage
              .ref('podcasts/${widget.docId}/audio.$audioExt')
              .delete()
              .catchError((_) {});
        }

        audioExt = newExt;
      }

      // Change cover
      if (_newCoverFile != null) {
        final coverRef = storage.ref('podcasts/${widget.docId}/cover.jpg');
        final task = await coverRef.putFile(_newCoverFile!);
        coverUrl = await task.ref.getDownloadURL();
      }

      await docRef.update({
        'title': _titleCtrl.text.trim(),
        'category': _category?.trim(), // ✅ NEW
        'description': _descCtrl.text.trim(),
        if (audioUrl != null) 'audioUrl': audioUrl,
        if (audioExt != null) 'audioExt': audioExt,
        if (coverUrl != null) 'coverUrl': coverUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showSnack('تم حفظ تعديلات البودكاست');
      Navigator.of(context).pop();
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
    Widget coverPreview;
    if (_newCoverFile != null) {
      coverPreview = Image.file(_newCoverFile!, fit: BoxFit.contain);
    } else if (_currentCoverUrl != null) {
      coverPreview = Image.network(_currentCoverUrl!, fit: BoxFit.contain);
    } else {
      coverPreview = Container(
        color: Colors.white24,
        child: const Icon(Icons.image, size: 40, color: _titleColor),
      );
    }

    final audioButtonText = _newAudioFile != null
        ? 'تم اختيار: ${_newAudioFile!.path.split('/').last}'
        : (_currentAudioUrl != null
        ? 'الملف الحالي موجود (اضغط لاستبداله)'
        : 'اختيار ملف الصوت');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back1.jpeg', fit: BoxFit.cover),
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
                padding: const EdgeInsets.only(top: kTitleTopOffset),
                child: const Text(
                  'تفاصيل البودكاست',
                  style:
                  TextStyle(color: _titleColor, fontWeight: FontWeight.w600),
                ),
              ),
              centerTitle: true,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, kPageTopOffset, 16, 24),
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: Opacity(
                    opacity: _saving ? 0.6 : 1,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const SizedBox(height: kFormTopOffset),

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
                                    child: coverPreview,
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
                              label: 'عنوان البودكاست',
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'عنوان البودكاست مطلوب'
                                  : null,
                            ),
                          ),

                          const SizedBox(height: _kGap),

                          // ✅ Category
                          _sizedField(
                            height: _kFieldH,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _fillGreen,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                              child: DropdownButtonFormField<String>(
                                value: widget.categories.contains(_category)
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
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'التصنيف مطلوب'
                                    : null,
                              ),
                            ),
                          ),

                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kDescH,
                            child: _styledField(
                              controller: _descCtrl,
                              label: 'وصف مختصر',
                              maxLines: 5,
                            ),
                          ),

                          const SizedBox(height: _kGap),

                          _sizedField(
                            height: _kFieldH,
                            child: _fileButton(
                              text: audioButtonText,
                              icon: Icons.podcasts,
                              onPressed: _pickAudio,
                            ),
                          ),

                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _saveEdits,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _confirmColor,
                                padding:
                                const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _saving
                                  ? Row(
                                mainAxisAlignment:
                                MainAxisAlignment.center,
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