import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> {
  static const Color _darkGreen = Color(0xFF0E3A2C);
  static const Color _midGreen = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm = Color(0xFF6F8E63);
  static Color get fill => const Color(0xFF8EAA7F);

  // Helper for unified SnackBar
  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
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
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Stream of the current listener reviews from users/{uid}/reviews
  Stream<List<_Review>> _reviewsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const <_Review>[]);
    }

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('reviews')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map((snap) {
      return snap.docs.map((d) => _Review.fromDoc(d.id, d.data())).toList();
    }).handleError((_) => <_Review>[]);
  }

  // Delete review from:
  // 1) users/{uid}/reviews/{reviewId}
  // 2) audiobooks/{bookId}/reviews/* where userId == uid
  Future<void> _deleteReview(_Review review) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Confirmation dialog
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
                  'حذف التقييم',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد من حذف هذا التقييم؟ لن يظهر على صفحة الكتاب أو في ملفك الشخصي.',
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

    if (ok != true) return;

    try {
      final firestore = FirebaseFirestore.instance;
      final List<Future> ops = [];

      // 1) Delete review from user profile
      ops.add(
        firestore
            .collection('users')
            .doc(user.uid)
            .collection('reviews')
            .doc(review.id)
            .delete(),
      );

      // 2) Delete review from the book document (if bookId is available)
      if (review.bookId != null && review.bookId!.isNotEmpty) {
        final bookReviewsCol =
        firestore.collection('audiobooks').doc(review.bookId).collection('reviews');

        // We delete all docs for this user on that book (safe even if one)
        final snap =
        await bookReviewsCol.where('userId', isEqualTo: user.uid).get();

        for (final d in snap.docs) {
          ops.add(d.reference.delete());
        }
      }

      await Future.wait(ops);

      if (mounted) {
        _showSnack('تم حذف التقييم بنجاح');
      }
    } catch (e, st) {
      debugPrint('Error deleting review ${review.id}: $e\n$st');
      if (mounted) {
        _showSnack(
          'تعذّر حذف التقييم، تحققي من الاتصال أو الصلاحيات.',
          icon: Icons.error_outline,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // Background
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
                          // Back arrow
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: IconButton(
                              tooltip: 'رجوع',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.85),
                              ),
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                              color: _darkGreen,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // Page title
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

                          // Reviews list
                          StreamBuilder<List<_Review>>(
                            stream: _reviewsStream(),
                            builder: (context, snap) {
                              if (snap.connectionState ==
                                  ConnectionState.waiting) {
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
                                separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                                itemBuilder: (context, i) {
                                  final r = reviews[i];
                                  return _ReviewTile(
                                    title: r.bookTitle ?? 'كتاب بدون عنوان',
                                    stars: (r.rating >= 0 && r.rating <= 5)
                                        ? r.rating
                                        : 0,
                                    date: r.formattedDate,
                                    review: r.text,
                                    coverUrl: r.bookCover,
                                    onDelete: () => _deleteReview(r),
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

  // Empty state box
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

  // Simple error box
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
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Simple loading skeleton
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

/* ------------------------------ Data model ------------------------------ */

class _Review {
  final String id;
  final String? bookId;
  final String? bookTitle;
  final String? bookCover;
  final String? text; // Review text
  final int rating; // 0..5
  final DateTime? createdAt;

  _Review({
    required this.id,
    required this.bookId,
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
      try {
        created = DateTime.tryParse(raw);
      } catch (_) {}
    }

    return _Review(
      id: id,
      bookId: (data['bookId'] as String?)?.trim(),
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

/* ------------------------------ Review card widget ------------------------------ */
class _ReviewTile extends StatelessWidget {
  final String title;
  final int stars; // 0..5
  final String date; // Preformatted date
  final String? review; // Optional text
  final String? coverUrl;
  final VoidCallback? onDelete;

  const _ReviewTile({
    required this.title,
    required this.stars,
    required this.date,
    this.review,
    this.coverUrl,
    this.onDelete,
  });

  static const Color _darkGreen = Color(0xFF0E3A2C);
  static const Color _lightGreen = Color(0xFFC9DABF);

  // Size of the book cover (you can change these)
  static const double _coverWidth = 80;
  static const double _coverHeight = 100;

  // Card padding values
  static const double _cardPaddingTop = 0;
  static const double _cardPaddingSide = 12;
  static const double _cardPaddingBottom = 12;

  // Shared left inset for both date row and stars row
  static const double _leftAlignInset = 0; // change if you want some inset

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        _cardPaddingSide,
        _cardPaddingTop,
        _cardPaddingSide,
        _cardPaddingBottom,
      ),
      decoration: BoxDecoration(
        color: _lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Book cover
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (coverUrl != null && coverUrl!.isNotEmpty)
                ? Image.network(
              coverUrl!,
              width: _coverWidth,
              height: _coverHeight,
              fit: BoxFit.cover,
            )
                : Container(
              width: _coverWidth,
              height: _coverHeight,
              color: Colors.white.withOpacity(0.6),
              child: const Icon(
                Icons.menu_book,
                color: _darkGreen,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Date + delete icon at top-left (aligned with stars)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: _leftAlignInset),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _darkGreen,
                          ),
                        ),
                        if (onDelete != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'حذف التقييم',
                            onPressed: onDelete,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Book title
                Align(
                  alignment: Alignment.centerRight,
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

                // Review text directly under the title
                if (review != null && review!.isNotEmpty) ...[
                  const SizedBox(height: 6),
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

                const SizedBox(height: 6),

                // Stars row aligned with the same left inset as date
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: _leftAlignInset),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (i) {
                        final filled = i < stars;
                        return Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            filled ? Icons.star : Icons.star_border,
                            size: 18,
                            color: _darkGreen,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
