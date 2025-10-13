import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chatbot_placeholder.dart';

class BookDetailsPage extends StatelessWidget {
  final String bookId;
  const BookDetailsPage({super.key, required this.bookId});

  // ألوان قريبة من المرفق
  static const _primary   = Color(0xFF0E3A2C); // أخضر داكن للنصوص
  static const _accent    = Color(0xFF6F8E63); // زر أساسي
  static const _pillGreen = Color(0xFFE6F0E0); // حبات خضراء فاتحة
  static const _chipRose  = Color(0xFFFFEFF0); // صندوق التعليقات وردي

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('تفاصيل الكتاب'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('audiobooks').doc(bookId).snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: Text('تعذر تحميل تفاصيل الكتاب'));
            }

            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final title = (data['title'] ?? '') as String;
            final author = (data['author'] ?? '') as String;
            final cover = (data['coverUrl'] ?? '') as String;
            final category = (data['category'] ?? '') as String;
            final desc = (data['description'] ?? '') as String;

            return Stack(
              children: [
                // الصفحة قابلة للسكرول بالكامل
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // غلاف كبير بظلال وحواف مدوّرة
                      Center(
                        child: Container(
                          width: 220,
                          height: 300,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 8))],
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: cover.isNotEmpty
                              ? Image.network(cover, fit: BoxFit.cover)
                              : const Icon(Icons.menu_book, size: 80, color: _primary),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // تصنيف الكتاب (حبة خضراء) ← ✅ تعديـل: عرض التصنيف الفعلي
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: _pillGreen, borderRadius: BorderRadius.circular(16)),
                            child: Text(category.isEmpty ? 'غير مصنّف' : category),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // عنوان كبير
                      Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _primary),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // الكاتب + تقييم شكلي (نجوم وأيقونة مايك)
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
                        child: Text('الكاتب: $author', style: const TextStyle(color: Colors.black54)),
                      ),

                      const SizedBox(height: 18),

                      // نبذة عن الكتاب (حبة خضراء كبيرة)
                      _PillCard(
                        title: 'نبذة عن الكتاب :',
                        child: Text(desc.isEmpty ? 'لا توجد نبذة متاحة حالياً.' : desc),
                      ),
                      const SizedBox(height: 12),

                      // زر "ملخص عن الكتاب" (شكل فقط)
                      _AudioPillButton(
                        icon: Icons.record_voice_over,
                        label: 'ملخص عن الكتاب',
                        onPressed: null, // مؤجل
                      ),
                      const SizedBox(height: 10),

                      // زر "بدء الاستماع" (شكل فقط)
                      _AudioPillButton(
                        icon: Icons.play_arrow,
                        label: 'بدء الاستماع',
                        onPressed: null, // مؤجل
                      ),

                      const SizedBox(height: 18),

                      const Text('التعليقات حول الكتاب:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),

                      const SizedBox(height: 8),

                      // قائمة التعليقات
                      _ReviewsList(bookId: bookId),

                      const SizedBox(height: 12),

                      // إضافة تعليق
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add_comment),
                          label: const Text('أضف تعليقك'),
                          onPressed: () => _showAddReviewSheet(context, bookId, title, cover),
                        ),
                      ),
                    ],
                  ),
                ),

                // زر التشات بوت داخل صفحة التفاصيل فقط
                Positioned(
                  bottom: 20,
                  left: 20,
                  child: FloatingActionButton(
                    backgroundColor: _accent,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ChatBotPlaceholderPage()),
                      );
                    },
                    child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAddReviewSheet(BuildContext context, String bookId, String title, String cover) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AddReviewSheet(bookId: bookId, bookTitle: title, bookCover: cover),
    );
  }
}

/// بطاقة خضراء ناعمة مع عنوان (مثل نبذة/ملخص)
class _PillCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _PillCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: BookDetailsPage._pillGreen, borderRadius: BorderRadius.circular(16)),
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

/// زر صوتي بشكل Pill مع أيقونة (للملخص / للكتاب)
class _AudioPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _AudioPillButton({required this.icon, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: BookDetailsPage._pillGreen,
          foregroundColor: BookDetailsPage._primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
        ),
        onPressed: onPressed, // مؤجل
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _ReviewsList extends StatelessWidget {
  final String bookId;
  const _ReviewsList({required this.bookId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('audiobooks')
          .doc(bookId)
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
                color: BookDetailsPage._chipRose,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: BookDetailsPage._accent.withOpacity(0.25),
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

    // اسم المستخدم من users/{uid}
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
        .collection('audiobooks')
        .doc(widget.bookId)
        .collection('reviews')
        .doc();

    final userReviewRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('reviews')
        .doc(bookReviewRef.id);

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
                decoration: const InputDecoration(
                  hintText: 'اكتب رأيك حول الكتاب...',
                  border: OutlineInputBorder(),
                ),
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
