import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:just_audio/just_audio.dart';
import 'friend_details_page.dart';
import 'package:firebase_core/firebase_core.dart';

import 'Book_chatbot.dart';

// Theme colors
const _primary   = Color(0xFF0E3A2C); // Dark text/icons
const _accent    = Color(0xFF6F8E63); // Chat button + SnackBar
const _pillGreen = Color(0xFFE6F0E0); // Soft light backgrounds
const _chipRose  = Color(0xFFFFEFF0); // Review bubbles background
const Color _darkGreen  = Color(0xFF0E3A2C);

/// Unified SnackBar with app style
void _showSnack(BuildContext context, String message, {IconData icon = Icons.check_circle}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: _accent,
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

class BookDetailsPage extends StatelessWidget {
  final String bookId;
  const BookDetailsPage({super.key, required this.bookId});

  /// ✅✅✅ الصوت فقط: توحيد الحالات مع Cloud Function (processing / completed)
  /// ✅✅✅ الصوت فقط: لا نرسل idToken للفنكشن (يعتمد على request.auth)
  Future<void> _startOrGenerateAudio(
      BuildContext context, {
        required Map<String, dynamic> data,
      }) async {

    final status = (data['audioStatus'] ?? 'idle') as String;
    final partsRaw = data['audioParts'];

    // 1) إذا الصوت جاهز → افتح المشغل
    if (status == 'completed' && partsRaw is List && partsRaw.isNotEmpty) {
      final urls = partsRaw.map((e) => e.toString()).toList();

      final lastPartIndex = (data['lastPartIndex'] ?? 0) as int;
      final lastPositionMs = (data['lastPositionMs'] ?? 0) as int;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookAudioPlayerPage(
            bookId: bookId,
            audioUrls: urls,
            initialPartIndex: lastPartIndex,
            initialPositionMs: lastPositionMs,
          ),
        ),
      );
      return;
    }

    // 2) إذا جاري التوليد
    if (status == 'processing') {
      _showSnack(
        context,
        'جاري توليد الصوت... انتظري قليلاً',
        icon: Icons.hourglass_top_rounded,
      );
      return;
    }

    // 3) غير ذلك → ابدأ التوليد
    try {
      _showSnack(
        context,
        'بدأنا توليد الصوت... قد يستغرق وقتاً بسيطاً',
        icon: Icons.settings_rounded,
      );

      // تأكدي أن اليوزر موجود (عشان request.auth بالفنكشن)
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack(context, 'لازم تسجلين دخول أولاً', icon: Icons.info_outline);
        return;
      }

      // ✅ (2) اجبري تحديث التوكن قبل استدعاء الفنكشن
      await user.getIdToken(true);

      // ✅ (1) استخدمي FirebaseFunctions.instance + Timeout
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateBookAudio',
        options: HttpsCallableOptions(
          timeout: const Duration(minutes: 9),
        ),
      );

      await callable.call({
        'bookId': bookId,
      });

    } on FirebaseFunctionsException catch (e) {
      _showSnack(context, 'تعذّر: ${e.code} - ${e.message ?? ""}', icon: Icons.error_outline);
    } catch (e) {
      _showSnack(context, 'تعذّر بدء توليد الصوت', icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // Shared background
          Positioned.fill(
            child: Image.asset(
              'assets/images/back_private.png',
              fit: BoxFit.cover,
            ),
          ),

          // Content above the background
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
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _primary,
                  size: 22,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text(
                'تفاصيل الكتاب',
                style: TextStyle(color: _primary),
              ),
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

                final audioStatus = (data['audioStatus'] ?? 'idle') as String;
                final audioPartsRaw = data['audioParts'];
                final bool hasAudioParts = audioPartsRaw is List && audioPartsRaw.isNotEmpty;

                // ✅✅✅ الصوت فقط: نفس حالات الفنكشن
                final bool isGenerating = audioStatus == 'processing';
                final bool isReady = audioStatus == 'completed' && hasAudioParts;

                final listenLabel = isGenerating
                    ? 'جاري توليد الصوت...'
                    : isReady
                    ? 'متابعة الاستماع'
                    : 'بدء الاستماع';

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cover
                      Center(
                        child: Container(
                          width: 220,
                          height: 270,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: cover.isNotEmpty
                              ? Image.network(
                            cover,
                            fit: BoxFit.contain,
                          )
                              : const Icon(
                            Icons.menu_book,
                            size: 80,
                            color: _primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _pillGreen,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(category.isEmpty ? 'غير مصنّف' : category),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      _AverageRatingRow(bookId: bookId),
                      const SizedBox(height: 4),

                      // Author
                      Center(
                        child: Text(
                          'الكاتب: $author',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Description
                      _PillCard(
                        title: 'نبذة عن الكتاب :',
                        child: Text(desc.isEmpty ? 'لا توجد نبذة متاحة حالياً.' : desc),
                      ),
                      const SizedBox(height: 12),

                      // Audio action buttons (UI only for now)
                      const _AudioPillButton(
                        icon: Icons.record_voice_over,
                        label: 'ملخص عن الكتاب',
                      ),
                      const SizedBox(height: 10),

                      // Start Listening
                      _AudioPillButton(
                        icon: Icons.play_arrow,
                        label: listenLabel,
                        enabled: !isGenerating,
                        onPressed: () => _startOrGenerateAudio(context, data: data),
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'التعليقات حول الكتاب:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _ReviewsList(bookId: bookId),

                      const SizedBox(height: 12),
                      const Divider(height: 1),

                      // Inline actions row just under reviews
                      const SizedBox(height: 8),
                      _InlineActionsRow(
                        onAddToList: () => _showAddToListSheet(
                          context,
                          bookId: bookId,
                          title: title,
                          author: author,
                          cover: cover,
                        ),
                        onDownload: null, // UI only for now
                        onReview: () => _showAddReviewSheet(
                          context,
                          bookId,
                          title,
                          cover,
                        ),
                      ),

                      const SizedBox(height: 90),
                    ],
                  ),
                );
              },
            ),

            floatingActionButton: FloatingActionButton(
              backgroundColor: _accent,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BookChatPage(bookId: bookId),
                  ),
                );
              },
              child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // === Bottom sheet: "Add to list" ===
  void _showAddToListSheet(
      BuildContext context, {
        required String bookId,
        required String title,
        required String author,
        required String cover,
      }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddToListSheet(
        bookId: bookId,
        title: title,
        author: author,
        cover: cover,
      ),
    );
  }

  // Bottom sheet: add review
  void _showAddReviewSheet(
      BuildContext context,
      String bookId,
      String title,
      String cover,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddReviewSheet(
        bookId: bookId,
        bookTitle: title,
        bookCover: cover,
      ),
    );
  }
}

/// Row of inline actions under reviews (colors from theme)
class _InlineActionsRow extends StatelessWidget {
  final VoidCallback? onAddToList;
  final VoidCallback? onDownload;
  final VoidCallback? onReview;
  const _InlineActionsRow({
    this.onAddToList,
    this.onDownload,
    this.onReview,
  });

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
        item(Icons.download_rounded, 'تحميل الكتاب', ' ', onDownload),
        const _DividerV(),
        item(Icons.star_rate_rounded, 'أضف', 'تقييماً', onReview),
      ],
    );
  }
}

/// Thin vertical divider
class _DividerV extends StatelessWidget {
  const _DividerV();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 1,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFEEEEEE)),
      ),
    );
  }
}

/// Green pill card (for description section)
class _PillCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _PillCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _pillGreen,
        borderRadius: BorderRadius.circular(16),
      ),
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

/// Audio-style button (UI only)
class _AudioPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  const _AudioPillButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.enabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final canPress = enabled && onPressed != null;
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _pillGreen,
          foregroundColor: _primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
        onPressed: canPress ? onPressed : null,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

/// Stars widget with half-star support (rounded to nearest 0.5)
class _Stars extends StatelessWidget {
  final double rating; // 0..5 (supports fractions)
  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final int halfSteps = (rating * 2).round();

    return Row(
      children: List.generate(5, (index) {
        final int starThreshold = (index + 1) * 2;

        IconData icon;
        if (halfSteps >= starThreshold) {
          icon = Icons.star;
        } else if (halfSteps == starThreshold - 1) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }

        return Icon(
          icon,
          size: 16,
          color: Colors.amber[700],
        );
      }),
    );
  }
}

/// Overall rating row (average stars + number of reviewers)
class _AverageRatingRow extends StatelessWidget {
  final String bookId;
  const _AverageRatingRow({required this.bookId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('audiobooks')
          .doc(bookId)
          .collection('reviews')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(width: 6),
              _Stars(rating: 0.0),
            ],
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(width: 6),
              _Stars(rating: 0.0),
            ],
          );
        }

        double sum = 0;
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final r = data['rating'];
          if (r is int) {
            sum += r.toDouble();
          } else if (r is double) {
            sum += r;
          }
        }

        final avg = sum / docs.length;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 6),
            _Stars(rating: avg),
            const SizedBox(width: 6),
            Text(
              avg.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '(${docs.length})',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Reviews list (for a specific book)
class _ReviewsList extends StatelessWidget {
  final String bookId;
  const _ReviewsList({required this.bookId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

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
            final userImageUrl = (m['userImageUrl'] ?? '') as String;
            final rating = (m['rating'] ?? 0);
            final ratingDouble = rating is int
                ? rating.toDouble()
                : (rating as double? ?? 0.0);
            final text = (m['text'] ?? '') as String;
            final userId = (m['userId'] ?? '') as String;

            final bool hasImage = userImageUrl.isNotEmpty;

            final avatar = CircleAvatar(
              radius: 22,
              backgroundColor: _accent.withOpacity(0.25),
              backgroundImage: hasImage ? NetworkImage(userImageUrl) : null,
              child: !hasImage
                  ? Text(
                userName.isNotEmpty ? userName.characters.first : 'ق',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _darkGreen,
                ),
              )
                  : null,
            );

            final tappableAvatar = GestureDetector(
              onTap: () {
                if (userId.isEmpty || userId == currentUid) return;

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendDetailsPage(friendUid: userId),
                  ),
                );
              },
              child: avatar,
            );

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
                  tappableAvatar,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                userName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _Stars(rating: ratingDouble),
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

/// Bottom sheet: Add book to user's list
/// Saves in users/{uid}/library/{bookId}
class _AddToListSheet extends StatelessWidget {
  final String bookId, title, author, cover;
  const _AddToListSheet({
    required this.bookId,
    required this.title,
    required this.author,
    required this.cover,
  });

  Future<void> _setStatus(BuildContext context, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack(context, 'الرجاء تسجيل الدخول أولاً', icon: Icons.info_outline);
      return;
    }
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .doc(bookId);

    await ref.set(
      {
        'bookId': bookId,
        'status': status, // listen_now | want
        'title': title,
        'author': author,
        'coverUrl': cover,
        'addedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (context.mounted) {
      Navigator.pop(context);
      _showSnack(context, 'تمت الإضافة إلى قائمتك', icon: Icons.check_circle);
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
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'إضافة إلى أي قائمة؟',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}

/// ======= Bottom sheet: Add review =======
class _AddReviewSheet extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final String bookCover;
  const _AddReviewSheet({
    required this.bookId,
    required this.bookTitle,
    required this.bookCover,
  });

  @override
  State<_AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<_AddReviewSheet> {
  int _rating = 0;
  final _ctrl = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack(context, 'الرجاء تسجيل الدخول أولاً', icon: Icons.info_outline);
      return;
    }
    if (_ctrl.text.trim().isEmpty) {
      _showSnack(context, 'فضلاً اكتب تعليقاً مختصراً', icon: Icons.info_outline);
      return;
    }
    setState(() => _saving = true);

    String userName = user.displayName ?? 'قارئ';
    String userImageUrl = user.photoURL ?? '';

    try {
      final u = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (u.exists) {
        final data = u.data() ?? {};

        final candidateName = (data['name'] ??
            data['fullName'] ??
            data['displayName'] ??
            '') as String;
        if (candidateName.trim().isNotEmpty) {
          userName = candidateName;
        }

        final candidateImage = (data['photoUrl'] ?? '') as String;
        if (candidateImage.trim().isNotEmpty) {
          userImageUrl = candidateImage;
        }
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
      'userImageUrl': userImageUrl,
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
    _showSnack(context, 'تم إضافة تعليقك بنجاح', icon: Icons.check_circle);
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
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'إضافة تعليق',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: Colors.amber[700],
                    ),
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

/// ===============================
/// SIMPLE AUDIO PLAYER PAGE
/// ===============================
class BookAudioPlayerPage extends StatefulWidget {
  final String bookId;
  final List<String> audioUrls;
  final int initialPartIndex;
  final int initialPositionMs;

  const BookAudioPlayerPage({
    super.key,
    required this.bookId,
    required this.audioUrls,
    required this.initialPartIndex,
    required this.initialPositionMs,
  });

  @override
  State<BookAudioPlayerPage> createState() => _BookAudioPlayerPageState();
}

class _BookAudioPlayerPageState extends State<BookAudioPlayerPage> {
  late final AudioPlayer _player;
  ConcatenatingAudioSource? _playlist;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      _playlist = ConcatenatingAudioSource(
        children: widget.audioUrls.map((u) => AudioSource.uri(Uri.parse(u))).toList(),
      );

      await _player.setAudioSource(
        _playlist!,
        initialIndex: (widget.initialPartIndex < widget.audioUrls.length)
            ? widget.initialPartIndex
            : 0,
        initialPosition: Duration(milliseconds: widget.initialPositionMs),
      );

      setState(() => _loading = false);
    } catch (_) {
      setState(() => _loading = false);
      if (mounted) _showSnack(context, 'تعذّر تشغيل الصوت', icon: Icons.error_outline);
    }
  }

  Future<void> _saveProgress() async {
    try {
      final idx = _player.currentIndex ?? 0;
      final pos = _player.position.inMilliseconds;

      await FirebaseFirestore.instance
          .collection('audiobooks')
          .doc(widget.bookId)
          .set(
        {
          'lastPartIndex': idx,
          'lastPositionMs': pos,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveProgress();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/back_private.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                tooltip: 'رجوع',
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _primary,
                  size: 22,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text(
                'تشغيل الكتاب',
                style: TextStyle(color: _primary),
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _pillGreen,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StreamBuilder<int?>(
                          stream: _player.currentIndexStream,
                          builder: (context, snap) {
                            final idx = (snap.data ?? 0) + 1;
                            final total = widget.audioUrls.length;
                            return Text(
                              'الجزء $idx من $total',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _primary,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        StreamBuilder<Duration>(
                          stream: _player.positionStream,
                          builder: (context, ps) {
                            final pos = ps.data ?? Duration.zero;
                            final dur = _player.duration ?? Duration.zero;

                            double value = 0;
                            if (dur.inMilliseconds > 0) {
                              value = pos.inMilliseconds / dur.inMilliseconds;
                            }

                            return Column(
                              children: [
                                Slider(
                                  value: value.clamp(0, 1),
                                  onChanged: (v) async {
                                    final seekMs = (dur.inMilliseconds * v).round();
                                    await _player.seek(Duration(milliseconds: seekMs));
                                  },
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(pos), style: const TextStyle(color: Colors.black54)),
                                    Text(_fmt(dur), style: const TextStyle(color: Colors.black54)),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 34,
                        onPressed: () async {
                          final idx = _player.currentIndex ?? 0;
                          if (idx > 0) {
                            await _player.seek(Duration.zero, index: idx - 1);
                            await _player.play();
                          }
                        },
                        icon: const Icon(Icons.skip_previous_rounded, color: _primary),
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, s) {
                          final state = s.data;
                          final playing = state?.playing ?? false;

                          return CircleAvatar(
                            radius: 32,
                            backgroundColor: _accent,
                            child: IconButton(
                              iconSize: 34,
                              onPressed: () async {
                                if (playing) {
                                  await _saveProgress();
                                  await _player.pause();
                                } else {
                                  await _player.play();
                                }
                              },
                              icon: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 34,
                        onPressed: () async {
                          final idx = _player.currentIndex ?? 0;
                          if (idx < widget.audioUrls.length - 1) {
                            await _player.seek(Duration.zero, index: idx + 1);
                            await _player.play();
                          }
                        },
                        icon: const Icon(Icons.skip_next_rounded, color: _primary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Save progress manually (optional)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pillGreen,
                        foregroundColor: _primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        await _saveProgress();
                        if (mounted) {
                          _showSnack(context, 'تم حفظ موضع الاستماع', icon: Icons.check_circle);
                        }
                      },
                      icon: const Icon(Icons.bookmark_rounded),
                      label: const Text('حفظ موضع الاستماع'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}