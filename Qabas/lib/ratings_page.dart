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


  Stream<List<_Rating>> _ratingsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // غير مسجل دخول: رجّع ستريم فاضي
      return Stream.value(const <_Rating>[]);
    }

    // users/{uid}/ratings مرتّبة بالأحدث
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ratings')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map((snap) {
      return snap.docs.map((d) => _Rating.fromDoc(d.id, d.data())).toList();
    }).handleError((_) {
      return <_Rating>[];
    });
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
                            alignment: AlignmentDirectional.centerStart, // start = يمين مع RTL
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
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'تقييماتي',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
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

                          // قائمة التقييمات من Firestore
                          StreamBuilder<List<_Rating>>(
                            stream: _ratingsStream(),
                            builder: (context, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return _loadingSkeleton();
                              }

                              if (snap.hasError) {
                                return _errorBox('حدث خطأ أثناء جلب التقييمات.');
                              }

                              final ratings = snap.data ?? const <_Rating>[];
                              if (ratings.isEmpty) {
                                return _emptyBox();
                              }

                              // قائمة بطاقات التقييم
                              return ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: ratings.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final r = ratings[i];
                                  return _RatingTile(
                                    title: r.bookTitle ?? 'كتاب بدون عنوان',
                                    stars: (r.rating >= 1 && r.rating <= 5) ? r.rating : 0,
                                    date: r.formattedDate,
                                    review: r.review,
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
      height: 72,
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

class _Rating {
  final String id;
  final String? bookTitle;
  final int rating;          // 1..5
  final String? review;      // اختياري
  final DateTime? createdAt; // قد يأتي كـ Timestamp أو String

  _Rating({
    required this.id,
    required this.bookTitle,
    required this.rating,
    required this.review,
    required this.createdAt,
  });

  factory _Rating.fromDoc(String id, Map<String, dynamic> data) {
    DateTime? created;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      created = raw.toDate();
    } else if (raw is String) {
      // ISO8601
      try { created = DateTime.tryParse(raw); } catch (_) {}
    }

    return _Rating(
      id: id,
      bookTitle: (data['bookTitle'] as String?)?.trim(),
      rating: (data['rating'] is num) ? (data['rating'] as num).toInt() : 0,
      review: (data['review'] as String?)?.trim(),
      createdAt: created,
    );
  }

  String get formattedDate {
    if (createdAt == null) return '';
    // تنسيق بسيط (YYYY-MM-DD). غيّريه لاحقاً لو تبين تنسيق عربي كامل.
    final y = createdAt!.year.toString().padLeft(4, '0');
    final m = createdAt!.month.toString().padLeft(2, '0');
    final d = createdAt!.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
    // مثال تنسيق عربي: '${d}‏/${m}‏/${y}'
  }
}

/* ------------------------------ عنصر البطاقة ------------------------------ */

class _RatingTile extends StatelessWidget {
  final String title;
  final int stars;       // 0..5
  final String date;     // نص جاهز للعرض
  final String? review;  // اختياري

  const _RatingTile({
    required this.title,
    required this.stars,
    required this.date,
    this.review,
  });

  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _lightGreen = Color(0xFFC9DABF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.book_outlined, size: 28, color: _darkGreen),
          const SizedBox(width: 12),
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
                        style: const TextStyle(
                          fontSize: 16,
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