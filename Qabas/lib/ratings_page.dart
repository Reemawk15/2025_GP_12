import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> {
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm    = Color(0xFF6F8E63);
  static Color get fill  => const Color(0xFF8EAA7F);

  Stream<List<_Review>> _reviewsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const <_Review>[]);
    }

    // ✅ نقرأ من users/{uid}/reviews بالأحدث أولاً
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('reviews')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map((snap) {
      return snap.docs.map((d) => _Review.fromDoc(d.id, d.data())).toList();
    }).handleError((_) => <_Review>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية نفسها
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),

          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 140, 18, 40),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // سهم الرجوع — نفس weekly_goal_page
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: IconButton(
                              tooltip: 'رجوع',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.85),
                              ),
                              icon: const Icon(Icons.arrow_back),
                              color: _darkGreen,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // عنوان الصفحة
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'تقييماتي',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16.5,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'جميع التقييمات التي أضفتها على الكتب الصوتية ستظهر هنا',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: _darkGreen.withOpacity(0.85),
                                fontSize: 13.5,
                                height: 1.35,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ✅ قائمة التقييمات (reviews)
                          StreamBuilder<List<_Review>>(
                            stream: _reviewsStream(),
                            builder: (context, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return _loadingSkeleton();
                              }
                              if (snap.hasError) {
                                return _errorBox('حدث خطأ أثناء جلب التقييمات.');
                              }
                              final reviews = snap.data ?? const <_Review>[];
                              if (reviews.isEmpty) {
                                return _emptyBox();
                              }

                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: reviews.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final r = reviews[i];
                                  return _ReviewTile(
                                    title: r.bookTitle ?? 'كتاب بدون عنوان',
                                    stars: (r.rating >= 0 && r.rating <= 5) ? r.rating : 0,
                                    date: r.formattedDate,
                                    review: r.text,
                                    coverUrl: r.bookCover,
                                  );
                                },
                              );
                            },
                          ),
                        ],
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

  // حالة فارغة
  Widget _emptyBox() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: const [
          SizedBox(height: 10),
          Text(
            'لا توجد تقييمات بعد',
            style: TextStyle(
              color: _darkGreen,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // صندوق خطأ بسيط
  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // لودينغ شكلي بسيط
  Widget _loadingSkeleton() {
    Widget bone() => Container(
      height: 84,
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
    );

    return Column(
      children: [
        bone(),
        const SizedBox(height: 10),
        bone(),
        const SizedBox(height: 10),
        bone(),
      ],
    );
  }
}

/* ------------------------------ نموذج البيانات ------------------------------ */

class _Review {
  final String id;
  final String? bookTitle;
  final String? bookCover;
  final String? text;        // نص التعليق
  final int rating;          // 0..5
  final DateTime? createdAt;

  _Review({
    required this.id,
    required this.bookTitle,
    required this.bookCover,
    required this.text,
    required this.rating,
    required this.createdAt,
  });

  factory _Review.fromDoc(String id, Map<String, dynamic> data) {
    DateTime? created;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      created = raw.toDate();
    } else if (raw is String) {
      try { created = DateTime.tryParse(raw); } catch (_) {}
    }

    return _Review(
      id: id,
      bookTitle: (data['bookTitle'] as String?)?.trim(),
      bookCover: (data['bookCover'] as String?)?.trim(),
      text: (data['text'] as String?)?.trim(),
      rating: (data['rating'] is num) ? (data['rating'] as num).toInt() : 0,
      createdAt: created,
    );
  }

  String get formattedDate {
    if (createdAt == null) return '';
    final y = createdAt!.year.toString().padLeft(4, '0');
    final m = createdAt!.month.toString().padLeft(2, '0');
    final d = createdAt!.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/* ------------------------------ عنصر البطاقة ------------------------------ */

class _ReviewTile extends StatelessWidget {
  final String title;
  final int stars;       // 0..5
  final String date;     // نص جاهز للعرض
  final String? review;  // اختياري
  final String? coverUrl;

  const _ReviewTile({
    required this.title,
    required this.stars,
    required this.date,
    this.review,
    this.coverUrl,
  });

  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _lightGreen = Color(0xFFC9DABF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // الغلاف
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (coverUrl != null && coverUrl!.isNotEmpty)
                ? Image.network(coverUrl!, width: 56, height: 72, fit: BoxFit.cover)
                : Container(
              width: 56,
              height: 72,
              color: Colors.white.withOpacity(0.6),
              child: const Icon(Icons.menu_book, color: _darkGreen),
            ),
          ),
          const SizedBox(width: 12),

          // المحتوى
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // العنوان + التاريخ
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _darkGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: const TextStyle(fontSize: 12, color: _darkGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // النجوم
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: List.generate(5, (i) {
                    final filled = i < stars;
                    return Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        filled ? Icons.star : Icons.star_border,
                        size: 18,
                        color: _darkGreen,
                      ),
                    );
                  }),
                ),

                if (review != null && review!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      review!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: _darkGreen,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
