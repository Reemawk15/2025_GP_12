import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chatbot_placeholder.dart';

// ألوان الثيم
 const _primary   = Color(0xFF0E3A2C); // نصوص/أيقونات داكنة
 const _accent    = Color(0xFF6F8E63); // زر محادثة
 const _pillGreen = Color(0xFFE6F0E0); // خلفيات فاتحة ناعمة
 const _chipRose  = Color(0xFFFFEFF0); // صندوق التعليقات
 const Color _darkGreen  = Color(0xFF0E3A2C);

class BookDetailsPage extends StatelessWidget {
  final String bookId;
  const BookDetailsPage({super.key, required this.bookId});



  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية الموحّدة
          Positioned.fill(
            child: Image.asset(
              'assets/images/back_private.png',
              fit: BoxFit.cover,
            ),
          ),

          // المحتوى فوق الخلفية
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 150,
              leading: IconButton(
                tooltip: 'رجوع',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 22, ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('تفاصيل الكتاب', style: TextStyle(color: _primary)),
            ),
            body: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('audiobooks')
                  .doc(bookId)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return const Center(child: Text('تعذّر تحميل تفاصيل الكتاب'));
                }

                final data = snap.data!.data() as Map<String, dynamic>? ?? {};
                final title = (data['title'] ?? '') as String;
                final author = (data['author'] ?? '') as String;
                final cover = (data['coverUrl'] ?? '') as String;
                final category = (data['category'] ?? '') as String;
                final desc = (data['description'] ?? '') as String;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // الغلاف
                      Center(
                        child: Container(
                          width: 220,
                          height: 270,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 20,
                                  offset: Offset(0, 8))
                            ],
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: cover.isNotEmpty
                              ? Image.network(cover, fit: BoxFit.cover)
                              : const Icon(Icons.menu_book,
                              size: 80, color: _primary),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // التصنيف
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: _pillGreen,
                                borderRadius: BorderRadius.circular(16)),
                            child:
                            Text(category.isEmpty ? 'غير مصنّف' : category),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // العنوان
                      Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _primary),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // تقييم شكلي + الكاتب
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mic_none, size: 18, color: _primary),
                          SizedBox(width: 6),
                          _Stars(rating: 4),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Center(
                          child: Text('الكاتب: $author',
                              style: const TextStyle(color: Colors.black54))),

                      const SizedBox(height: 18),

                      // نبذة
                      _PillCard(
                        title: 'نبذة عن الكتاب :',
                        child: Text(desc.isEmpty
                            ? 'لا توجد نبذة متاحة حالياً.'
                            : desc),
                      ),
                      const SizedBox(height: 12),

                      // أزرار صوتية شكلية
                      const _AudioPillButton(
                          icon: Icons.record_voice_over, label: 'ملخص عن الكتاب'),
                      const SizedBox(height: 10),
                      const _AudioPillButton(
                          icon: Icons.play_arrow, label: 'بدء الاستماع'),

                      const SizedBox(height: 18),

                      const Text('التعليقات حول الكتاب:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _ReviewsList(bookId: bookId),

                      const SizedBox(height: 12),
                      const Divider(height: 1),

                      // ✅ الخيارات الثلاثة (غير ثابتة — تحت التعليقات مباشرة)
                      const SizedBox(height: 8),
                      _InlineActionsRow(
                        onAddToList: () => _showAddToListSheet(
                          context,
                          bookId: bookId,
                          title: title,
                          author: author,
                          cover: cover,
                        ),
                        onDownload: null, // شكل فقط حالياً
                        onReview: () =>
                            _showAddReviewSheet(context, bookId, title, cover),
                      ),

                      const SizedBox(height: 90),
                    ],
                  ),
                );
              },
            ),

            // ✅ زر الشات بوت داخل الـ Scaffold وليس بعده
            floatingActionButton: FloatingActionButton(
              backgroundColor: _accent,
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ChatBotPlaceholderPage()));
              },
              child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
  // === شيت "إضافة إلى قائمة" ===
  void _showAddToListSheet(
      BuildContext context, {
        required String bookId,
        required String title,
        required String author,
        required String cover,
      }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddToListSheet(bookId: bookId, title: title, author: author, cover: cover),
    );
  }

  // شيت التعليقات (موجود عندك)
  void _showAddReviewSheet(BuildContext context, String bookId, String title, String cover) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddReviewSheet(bookId: bookId, bookTitle: title, bookCover: cover),
    );
  }
}

/// صف خيارات أسفل التعليقات (ألوان من الثيم)
class _InlineActionsRow extends StatelessWidget {
  final VoidCallback? onAddToList;
  final VoidCallback? onDownload;
  final VoidCallback? onReview;
  const _InlineActionsRow({this.onAddToList, this.onDownload, this.onReview});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String l1, String l2, VoidCallback? onTap) {
      final enabled = onTap != null;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _pillGreen,
                child: Icon(icon, color: _accent),
              ),
              const SizedBox(height: 6),
              Text(
                l1,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87.withOpacity(enabled ? 1 : 0.4),
                ),
              ),
              if (l2.trim().isNotEmpty)
                Text(
                  l2,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: Colors.black87.withOpacity(enabled ? 1 : 0.4),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        item(Icons.folder_copy_rounded, 'إضافة', 'إلى قائمة', onAddToList),
        const _DividerV(),
        item(Icons.download_rounded, 'تحميل الكتاب', ' ', onDownload), // شكل فقط
        const _DividerV(),
        item(Icons.star_rate_rounded, 'أضف', 'تقييماً', onReview),
      ],
    );
  }
}

/// فاصل عمودي رفيع
class _DividerV extends StatelessWidget {
  const _DividerV();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 1,
      height: 44,
      child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFEEEEEE))),
    );
  }
}

/// بطاقة خضراء
class _PillCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _PillCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _pillGreen, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// زر صوتي شكلي
class _AudioPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AudioPillButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _pillGreen,
          foregroundColor: _primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
        ),
        onPressed: null,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

/// نجوم تقييم شكلية
class _Stars extends StatelessWidget {
  final int rating; // 0..5
  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        return Icon(i < rating ? Icons.star : Icons.star_border, size: 16, color: Colors.amber[700]);
      }),
    );
  }
}

/// قائمة التعليقات (كما كانت)
class _ReviewsList extends StatelessWidget {
  final String bookId;
  const _ReviewsList({required this.bookId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('audiobooks').doc(bookId)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, rs) {
        if (rs.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = rs.data?.docs ?? [];
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('لا توجد تعليقات بعد. كن أول من يقيّم هذا الكتاب!'),
          );
        }
        return Column(
          children: items.map((d) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final userName = (m['userName'] ?? 'قارئ') as String;
            final rating = (m['rating'] ?? 0) as int;
            final text = (m['text'] ?? '') as String;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _chipRose,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: _accent.withOpacity(0.25),
                    child: Text(userName.isNotEmpty ? userName.characters.first : 'ق'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w700))),
                            _Stars(rating: rating),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(text),
                      ],
                    ),
                  )
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// شيت إضافة إلى قائمة (يحفظ في users/{uid}/library/{bookId})
class _AddToListSheet extends StatelessWidget {
  final String bookId, title, author, cover;
  const _AddToListSheet({required this.bookId, required this.title, required this.author, required this.cover});

  Future<void> _setStatus(BuildContext context, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء تسجيل الدخول أولاً')));
      return;
    }
    final ref = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('library').doc(bookId);

    await ref.set({
      'bookId'   : bookId,
      'status'   : status, // listen_now | want | listened
      'title'    : title,
      'author'   : author,
      'coverUrl' : cover,
      'addedAt'  : FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى قائمتك')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('إضافة إلى أي قائمة؟', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.play_circle_fill, color: _primary),
              title: const Text('استمع لها الآن'),
              onTap: () => _setStatus(context, 'listen_now'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: _primary),
              title: const Text('أرغب بالاستماع لها'),
              onTap: () => _setStatus(context, 'want'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: _primary),
              title: const Text('استمعت لها'),
              onTap: () => _setStatus(context, 'listened'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ======= شيت إضافة تعليق (كما عندك) =======
class _AddReviewSheet extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final String bookCover;
  const _AddReviewSheet({required this.bookId, required this.bookTitle, required this.bookCover});

  @override
  State<_AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<_AddReviewSheet> {
  int _rating = 4;
  final _ctrl = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء تسجيل الدخول أولاً')));
      return;
    }
    if (_ctrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فضلاً اكتب تعليقاً مختصراً')));
      return;
    }
    setState(() => _saving = true);

    String userName = user.displayName ?? 'قارئ';
    try {
      final u = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (u.exists) {
        final data = u.data() ?? {};
        final candidate = (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '') as String;
        if (candidate.trim().isNotEmpty) userName = candidate;
      }
    } catch (_) {}

    final batch = FirebaseFirestore.instance.batch();

    final bookReviewRef = FirebaseFirestore.instance
        .collection('audiobooks').doc(widget.bookId)
        .collection('reviews').doc();

    final userReviewRef = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('reviews').doc(bookReviewRef.id);

    final payload = {
      'userId': user.uid,
      'userName': userName,
      'bookId': widget.bookId,
      'bookTitle': widget.bookTitle,
      'bookCover': widget.bookCover,
      'rating': _rating,
      'text': _ctrl.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    batch.set(bookReviewRef, payload);
    batch.set(userReviewRef, payload);

    await batch.commit();

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إضافة تعليقك بنجاح')));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              const Text('إضافة تعليق', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(filled ? Icons.star : Icons.star_border, color: Colors.amber[700]),
                  );
                }),
              ),
              TextField(
                controller: _ctrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'اكتب رأيك حول الكتاب...', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التعليق'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}