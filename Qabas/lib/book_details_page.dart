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

  // ✅ تعديل ضروري: تحويل القيم القادمة من Firestore بشكل آمن إلى int
  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  Future<void> _startOrGenerateAudio(
      BuildContext context, {
        required Map<String, dynamic> data,
        required String title,
        required String author,
        required String cover,
      }) async {
    final status = (data['audioStatus'] ?? 'idle').toString();
    final partsRaw = data['audioParts'];

    final bool hasParts = partsRaw is List && partsRaw.isNotEmpty;

    // ✅ لو فيه أجزاء موجودة (حتى لو processing) افتحي المشغل بكل الموجود
    if (hasParts) {
      final urls = partsRaw.map((e) => e.toString()).toList();

      // ✅ التعديل هنا فقط: كان (as int) ويسبب كراش أحياناً
      final lastPartIndex = _asInt(data['lastPartIndex'], fallback: 0);
      final lastPositionMs = _asInt(data['lastPositionMs'], fallback: 0);

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookAudioPlayerPage(
            bookId: bookId,
            bookTitle: title,
            bookAuthor: author,
            coverUrl: cover,
            audioUrls: urls,
            initialPartIndex: (lastPartIndex < urls.length) ? lastPartIndex : 0,
            initialPositionMs: lastPositionMs,
          ),
        ),
      );

      // ✅ (اختياري) إذا تبين عند الضغط وهو processing يحاول يكمل جزء واحد بالخلفية
      if (status == 'processing') {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
            final callable = functions.httpsCallable(
              'generateBookAudio',
              options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
            );
            await callable.call({'bookId': bookId, 'maxParts': 30});
          }
        } catch (_) {}
      }
      return;
    }

    // ✅ ما فيه أجزاء -> نبدأ توليد
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack(context, 'لازم تسجلين دخول أولاً', icon: Icons.info_outline);
        return;
      }

      _showSnack(context, 'جاري توليد الصوت…', icon: Icons.settings_rounded);

      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable(
        'generateBookAudio',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );

      await callable.call({'bookId': bookId, 'maxParts': 30});
      _pollUntilHasAnyPart(context);
    } on FirebaseFunctionsException catch (e) {
      _showSnack(context, 'تعذّر: ${e.code}', icon: Icons.error_outline);
      _pollUntilHasAnyPart(context);
    } catch (_) {
      _showSnack(context, 'تعذّر توليد الصوت', icon: Icons.error_outline);
    }
  }

  /// ✅ ينتظر لين يصير فيه أول جزء جاهز ثم يترك الـ StreamBuilder يحدث UI
  void _pollUntilHasAnyPart(BuildContext context) {
    int tries = 0;
    Future.doWhile(() async {
      if (!context.mounted) return false;
      await Future.delayed(const Duration(seconds: 4));
      tries++;

      final snap = await FirebaseFirestore.instance
          .collection('audiobooks')
          .doc(bookId)
          .get();

      if (!snap.exists) return false;
      final d = snap.data() as Map<String, dynamic>? ?? {};
      final parts = d['audioParts'];
      final count = (parts is List) ? parts.length : 0;

      if (count > 0) {
        _showSnack(context, 'تم تجهيز أول جزء ✅', icon: Icons.check_circle);
        return false;
      }

      if (tries >= 45) {
        _showSnack(context, 'التوليد يأخذ وقت… جربي بعد شوي', icon: Icons.info_outline);
        return false;
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back_private.png', fit: BoxFit.cover),
          ),
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
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 22),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('تفاصيل الكتاب', style: TextStyle(color: _primary)),
            ),
            body: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('audiobooks').doc(bookId).snapshots(),
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
                final partsRaw = data['audioParts'];
                final bool hasAudioParts = partsRaw is List && partsRaw.isNotEmpty;

                // ✅ هنا: لو فيه أجزاء نسمح بالاستماع حتى لو processing
                final bool isGenerating = (audioStatus == 'processing') && !hasAudioParts;
                final listenLabel = hasAudioParts
                    ? 'استمع'
                    : isGenerating
                    ? 'جاري توليد الصوت...'
                    : 'بدء الاستماع';

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                              ? Image.network(cover, fit: BoxFit.contain)
                              : const Icon(Icons.menu_book, size: 80, color: _primary),
                        ),
                      ),
                      const SizedBox(height: 16),

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

                      Center(
                        child: Text('الكاتب: $author', style: const TextStyle(color: Colors.black54)),
                      ),

                      const SizedBox(height: 18),

                      _PillCard(
                        title: 'نبذة عن الكتاب :',
                        child: Text(desc.isEmpty ? 'لا توجد نبذة متاحة حالياً.' : desc),
                      ),
                      const SizedBox(height: 12),

                      // (UI only)
                      const _AudioPillButton(
                        icon: Icons.record_voice_over,
                        label: 'ملخص عن الكتاب',
                      ),
                      const SizedBox(height: 10),

                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _pillGreen,
                            foregroundColor: _darkGreen,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: isGenerating
                              ? null
                              : () => _startOrGenerateAudio(
                            context,
                            data: data,
                            title: title,
                            author: author,
                            cover: cover,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.headphones_rounded, size: 24),
                              const SizedBox(width: 12),
                              Text(
                                listenLabel == 'بدء الاستماع' ? 'استمع' : listenLabel,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                      const SizedBox(height: 8),

                      _InlineActionsRow(
                        onAddToList: () => _showAddToListSheet(
                          context,
                          bookId: bookId,
                          title: title,
                          author: author,
                          cover: cover,
                        ),
                        onDownload: null,
                        onReview: () => _showAddReviewSheet(context, bookId, title, cover),
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
                  MaterialPageRoute(builder: (_) => BookChatPage(bookId: bookId)),
                );
              },
              child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

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

  void _showAddReviewSheet(BuildContext context, String bookId, String title, String cover) {
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

/// Row of inline actions under reviews
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

/// (UI only)
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
        ),
        onPressed: canPress ? onPressed : null,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final double rating;
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

        return Icon(icon, size: 16, color: Colors.amber[700]);
      }),
    );
  }
}

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
            children: const [SizedBox(width: 6), _Stars(rating: 0.0)],
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [SizedBox(width: 6), _Stars(rating: 0.0)],
          );
        }

        double sum = 0;
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          final r = data['rating'];
          if (r is int) sum += r.toDouble();
          else if (r is double) sum += r;
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
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        );
      },
    );
  }
}

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
            final ratingDouble = rating is int ? rating.toDouble() : (rating as double? ?? 0.0);
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
                style: const TextStyle(fontWeight: FontWeight.bold, color: _darkGreen),
              )
                  : null,
            );

            final tappableAvatar = GestureDetector(
              onTap: () {
                if (userId.isEmpty || userId == currentUid) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => FriendDetailsPage(friendUid: userId)),
                );
              },
              child: avatar,
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _chipRose, borderRadius: BorderRadius.circular(16)),
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
                              child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w700)),
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
        'status': status,
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
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
            ),
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
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: Add review
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
        final candidateName = (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '') as String;
        if (candidateName.trim().isNotEmpty) userName = candidateName;

        final candidateImage = (data['photoUrl'] ?? '') as String;
        if (candidateImage.trim().isNotEmpty) userImageUrl = candidateImage;
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
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
              ),
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

/// AUDIO PLAYER PAGE
class BookAudioPlayerPage extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final String bookAuthor;
  final String coverUrl;

  final List<String> audioUrls;

  final int initialPartIndex;
  final int initialPositionMs;

  const BookAudioPlayerPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.coverUrl,
    required this.audioUrls,
    required this.initialPartIndex,
    required this.initialPositionMs,
  });

  @override
  State<BookAudioPlayerPage> createState() => _BookAudioPlayerPageState();
}

class _BookAudioPlayerPageState extends State<BookAudioPlayerPage> {
  late final AudioPlayer _player;

  bool _loading = true;

  double _speed = 1.0;
  final List<double> _speeds = const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  List<Duration?> _durations = [];

  bool _durationsReady = false;

  // ✅ حالة البوك مارك (معبّى/حدود)
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      final sources = widget.audioUrls.map((u) => AudioSource.uri(Uri.parse(u))).toList();
      final playlist = ConcatenatingAudioSource(children: sources);

      await _player.setAudioSource(
        playlist,
        initialIndex: widget.initialPartIndex.clamp(0, widget.audioUrls.length - 1),
        initialPosition: Duration(milliseconds: widget.initialPositionMs),
      );

      await _player.setSpeed(_speed);

      // ✅ إذا فيه موضع محفوظ من قبل نبي الزر يكون "معبّى"
      _isBookmarked = widget.initialPositionMs > 0;

      // ✅ أول مرة: durations قد تكون null، نسمع sequenceStream للتحديث
      _durations = _player.sequence?.map((s) => s.duration).toList() ?? [];

      _player.sequenceStream.listen((seq) {
        if (!mounted) return;
        setState(() {
          _durations = seq?.map((s) => s.duration).toList() ?? _durations;
        });
      });

      setState(() => _loading = false);

      // ✅ احسب مدة كل جزء من الروابط عشان مجموع الكتاب يطلع صح
      await _loadAllDurationsFromUrls();
    } catch (_) {
      setState(() => _loading = false);
      if (mounted) _showSnack(context, 'تعذّر تشغيل الصوت', icon: Icons.error_outline);
    }
  }

  Future<void> _loadAllDurationsFromUrls() async {
    try {
      if (_durations.isNotEmpty &&
          _durations.length == widget.audioUrls.length &&
          _durations.every((d) => d != null && d!.inMilliseconds > 0)) {
        if (mounted) setState(() => _durationsReady = true);
        return;
      }

      final tmp = AudioPlayer();
      final List<Duration?> result = [];

      for (final url in widget.audioUrls) {
        try {
          final d = await tmp.setUrl(url);
          result.add(d);
        } catch (_) {
          result.add(null);
        }
      }

      await tmp.dispose();

      if (!mounted) return;
      setState(() {
        _durations = result;
        _durationsReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _durationsReady = true);
    }
  }

  int _totalMs() {
    if (_durations.isEmpty) return 0;
    return _durations.fold<int>(0, (sum, d) => sum + (d?.inMilliseconds ?? 0));
  }

  int _prefixMsBefore(int index) {
    if (_durations.isEmpty) return 0;
    int sum = 0;
    for (int i = 0; i < index; i++) {
      sum += (_durations[i]?.inMilliseconds ?? 0);
    }
    return sum;
  }

  int _globalPosMs() {
    final idx = _player.currentIndex ?? 0;
    final local = _player.position.inMilliseconds;
    return _prefixMsBefore(idx) + local;
  }

  Future<void> _seekGlobalMs(int targetMs) async {
    if (_durations.isEmpty) return;

    int acc = 0;
    for (int i = 0; i < _durations.length; i++) {
      final d = _durations[i]?.inMilliseconds ?? 0;
      if (d <= 0) continue;
      if (targetMs < acc + d) {
        final inside = targetMs - acc;
        await _player.seek(Duration(milliseconds: inside), index: i);
        return;
      }
      acc += d;
    }

    final lastIndex = (_durations.length - 1).clamp(0, _durations.length - 1);
    final lastDur = _durations[lastIndex]?.inMilliseconds ?? 0;
    await _player.seek(Duration(milliseconds: lastDur > 0 ? lastDur : 0), index: lastIndex);
  }

  Future<void> _saveProgress() async {
    try {
      final idx = _player.currentIndex ?? 0;
      final pos = _player.position.inMilliseconds;

      await FirebaseFirestore.instance.collection('audiobooks').doc(widget.bookId).set(
        {
          'lastPartIndex': idx,
          'lastPositionMs': pos,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  // ✅ Toggle للبوكمارك (هو اللي يحفظ/يلغي الحفظ)
  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      // إلغاء الحفظ (يرجع من البداية لاحقاً)
      try {
        await FirebaseFirestore.instance.collection('audiobooks').doc(widget.bookId).set(
          {
            'lastPartIndex': FieldValue.delete(),
            'lastPositionMs': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isBookmarked = false);
    } else {
      // حفظ الموضع
      await _saveProgress();
      if (!mounted) return;
      setState(() => _isBookmarked = true);
    }
  }

  Future<void> _seekBy(int seconds) async {
    final total = _totalMs();
    if (total <= 0) return;

    int target = _globalPosMs() + (seconds * 1000);
    if (target < 0) target = 0;
    if (target > total) target = total;

    await _seekGlobalMs(target);
  }

  Future<void> _toggleSpeed() async {
    final idx = _speeds.indexOf(_speed);
    final next = _speeds[(idx + 1) % _speeds.length];
    setState(() => _speed = next);
    await _player.setSpeed(next);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final whiteCard = Colors.white.withOpacity(0.70);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back_private.png', fit: BoxFit.cover),
          ),
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
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 22),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('تشغيل الكتاب', style: TextStyle(color: _primary)),
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                children: [
                  const SizedBox(height: 45),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: whiteCard,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 190,
                          height: 235,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: widget.coverUrl.isNotEmpty
                              ? Image.network(widget.coverUrl, fit: BoxFit.contain)
                              : const Icon(Icons.menu_book, size: 70, color: _primary),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.bookTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.bookAuthor,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 2),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: whiteCard,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, snap) {
                        final total = _totalMs();
                        final gpos = _globalPosMs();

                        final leftMs = gpos < 0 ? 0 : gpos;
                        final rightMs = total > 0 ? total : 0;

                        final value = (total > 0) ? (leftMs / total) : 0.0;

                        return Column(
                          children: [
                            Slider(
                              value: value.clamp(0, 1),
                              onChanged: total <= 0
                                  ? null
                                  : (v) async {
                                final target = (total * v).round();
                                await _seekGlobalMs(target);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_fmtMs(leftMs), style: const TextStyle(color: Colors.black54)),
                                Text(_fmtMs(rightMs), style: const TextStyle(color: Colors.black54)),
                              ],
                            ),
                            if (!_durationsReady)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('جاري حساب مدة الكتاب...', style: TextStyle(color: Colors.black54)),
                              ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 42,
                        onPressed: () => _seekBy(-10),
                        icon: const Icon(Icons.replay_10_rounded, color: _primary),
                      ),
                      const SizedBox(width: 16),
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, s) {
                          final playing = s.data?.playing ?? false;
                          return CircleAvatar(
                            radius: 34,
                            backgroundColor: _accent,
                            child: IconButton(
                              iconSize: 40,
                              onPressed: () async {
                                if (playing) {
                                  // ❌ لا نحفظ عند الإيقاف
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
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 42,
                        onPressed: () => _seekBy(10),
                        icon: const Icon(Icons.forward_10_rounded, color: _primary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 64,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: whiteCard,
                            foregroundColor: _primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _toggleBookmark,
                          icon: Icon(
                            _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: _primary,
                            size: 26,
                          ),
                          label: const Text(
                            'حفظ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 64,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: whiteCard,
                            foregroundColor: _primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _toggleSpeed,
                          icon: const Icon(
                            Icons.speed_rounded,
                            size: 26,
                          ),
                          label: Text(
                            '${_speed.toStringAsFixed(2)}x',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtMs(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}