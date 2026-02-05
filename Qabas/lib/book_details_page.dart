import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:just_audio/just_audio.dart';
import 'friend_details_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'goal_notifications.dart';
import 'marks_notes_page.dart';

import 'Book_chatbot.dart';
import 'dart:async';
import 'package:confetti/confetti.dart';

// Theme colors
const _primary = Color(0xFF0E3A2C); // Dark text/icons
const _accent = Color(0xFF6F8E63); // Chat button + SnackBar
const _pillGreen = Color(0xFFE6F0E0); // Soft light backgrounds
const _chipRose = Color(0xFFFFEFF0); // Review bubbles background
const Color _softRose = Color(0xFFCD9BAB);
const Color _lightSoftRose = Color(0xFFE6B7C6);
const Color _darkGreen = Color(0xFF0E3A2C);
const Color _midDarkGreen2 = Color(0xFF2A5C4C);
const _midPillGreen = Color(0xFFBFD6B5);

/// Unified SnackBar with app style
void _showSnack(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle,
}) {
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

class BookDetailsPage extends StatelessWidget {
  final String bookId;
  const BookDetailsPage({super.key, required this.bookId});

  // ✅ تحويل القيم القادمة من Firestore بشكل آمن إلى int
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

        int? overridePartIndex,
        int? overridePositionMs,
      }) async {
    final status = (data['audioStatus'] ?? 'idle').toString();
    final partsRaw = data['audioParts'];

    final bool hasParts = partsRaw is List && partsRaw.isNotEmpty;

    // ✅ لو فيه أجزاء موجودة افتحي المشغل بكل الموجود
    if (hasParts) {
      final urls = partsRaw.map((e) => e.toString()).toList();

      // ✅ التعديل: التقدم/البوكمارك لازم يكون لكل يوزر (users/{uid}/library/{bookId})
      int lastPartIndex = 0;
      int lastPositionMs = 0;

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final progSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('library')
              .doc(bookId)
              .get();

          final p = progSnap.data() ?? {};
          lastPartIndex = _asInt(p['lastPartIndex'], fallback: 0);
          lastPositionMs = _asInt(p['lastPositionMs'], fallback: 0);
        } catch (_) {}
      }

// ✅ بعد Firestore، نغلبه لو جايين من علامة
      if (overridePartIndex != null && overridePositionMs != null) {
        lastPartIndex = overridePartIndex;
        lastPositionMs = overridePositionMs;
      }

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
          if (user != null) {
            final functions = FirebaseFunctions.instanceFor(
              region: 'us-central1',
            );
            final callable = functions.httpsCallable(
              'generateBookAudio',
              options: HttpsCallableOptions(
                timeout: const Duration(minutes: 9),
              ),
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
        _showSnack(
          context,
          'التوليد يأخذ وقت… جربي بعد شوي',
          icon: Icons.info_outline,
        );
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
                final partsRaw = data['audioParts'];
                final bool hasAudioParts =
                    partsRaw is List && partsRaw.isNotEmpty;

                // ✅ هنا: لو فيه أجزاء نسمح بالاستماع حتى لو processing
                final bool isGenerating =
                    (audioStatus == 'processing') && !hasAudioParts;
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
                              : const Icon(
                                  Icons.menu_book,
                                  size: 80,
                                  color: _primary,
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _pillGreen,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              category.isEmpty ? 'غير مصنّف' : category,
                            ),
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
                        child: Text(
                          'الكاتب: $author',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),

                      const SizedBox(height: 18),

                      _PillCard(
                        title: 'نبذة عن الكتاب :',
                        child: Text(
                          desc.isEmpty ? 'لا توجد نبذة متاحة حالياً.' : desc,
                        ),
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
                                listenLabel == 'بدء الاستماع'
                                    ? 'استمع'
                                    : listenLabel,
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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

                        onMarks: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MarksNotesPage(bookId: bookId),
                            ),
                          );

                          if (result is Map && result['partIndex'] is int && result['positionMs'] is int) {
                            final partIndex = result['partIndex'] as int;
                            final positionMs = result['positionMs'] as int;

                            // ✅ افتحي المشغل مباشرة عند الموضع
                            await _startOrGenerateAudio(
                              context,
                              data: data,
                              title: title,
                              author: author,
                              cover: cover,
                              overridePartIndex: partIndex,
                              overridePositionMs: positionMs,
                            );
                          }
                        },
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

  void _showAddReviewSheet(
      BuildContext context,
      String bookId,
      String title,
      String cover,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

  final VoidCallback? onMarks;

  const _InlineActionsRow({
    this.onAddToList,
    this.onDownload,
    this.onReview,
    this.onMarks,
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
        item(Icons.download_rounded, 'تحميل', 'الكتاب', onDownload),
        const _DividerV(),
        item(Icons.star_rate_rounded, 'أضف', 'تقييماً', onReview),
        const _DividerV(),
        item(Icons.bookmark_added_rounded, 'العلامات', 'والملاحظات', onMarks),
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
      child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFFEEEEEE))),
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
          if (r is int)
            sum += r.toDouble();
          else if (r is double)
            sum += r;
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
                  ),
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
      _showSnack(
        context,
        'الرجاء تسجيل الدخول أولاً',
        icon: Icons.info_outline,
      );
      return;
    }

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .doc(bookId);

    await ref.set({
      'bookId': bookId,
      'status': status,
      'title': title,
      'author': author,
      'coverUrl': cover,
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
    if (_rating == 0) {
      _showSnack(context, 'اختاري عدد النجوم أولاً', icon: Icons.info_outline);
      return;
    }
    if (_ctrl.text.trim().isEmpty) {
      _showSnack(context, 'فضلاً اكتبي تعليقاً مختصراً', icon: Icons.info_outline);
      return;
    }

    setState(() => _saving = true);

    String userName = user.displayName ?? 'قارئ';
    String userImageUrl = user.photoURL ?? '';

    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (u.exists) {
        final data = u.data() ?? {};
        final candidateName =
        (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '') as String;
        if (candidateName.trim().isNotEmpty) userName = candidateName;

        final candidateImage = (data['photoUrl'] ?? '') as String;
        if (candidateImage.trim().isNotEmpty) userImageUrl = candidateImage;
      }
    } catch (_) {}

    try {
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
      _showSnack(context, 'تم حفظ تعليقك بنجاح', icon: Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      _showSnack(context, 'تعذّر حفظ التعليق', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _pillGreen.withOpacity(0.96), // ✅ نفس الملاحظة
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Handle زي اللي بالملاحظات/التعليق
              Center(
                child: Container(
                  height: 4,
                  width: 44,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              const Text(
                'إضافة تعليق',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 10),

              // ⭐ النجوم
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _rating;
                    return IconButton(
                      onPressed: _saving ? null : () => setState(() => _rating = i + 1),
                      icon: Icon(
                        filled ? Icons.star : Icons.star_border,
                        color: Colors.amber[700],
                      ),
                    );
                  }),
                ),
              ),

              TextField(
                controller: _ctrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب رأيك حول الكتاب...',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent, // ✅ نفس زر الملاحظة الأخضر
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving ? 'جارٍ الحفظ...' : 'حفظ التعليق',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
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
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  final Stopwatch _listenWatch = Stopwatch();
  int _sessionListenedSeconds = 0;
  late final ConfettiController _confettiController;

  bool _loading = true;

  double _speed = 1.0;
  final List<double> _speeds = const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _movedToListened = false;

  List<Duration?> _durations = [];

  bool _durationsReady = false;

  bool _isBookmarked = false;

  int _maxReachedMs = 0;

  Timer? _statsTimer;

  Timer? _resumeTimer;

  Future<void> _autoSaveResume() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idx = _player.currentIndex ?? 0;
      final pos = _player.position.inMilliseconds;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.bookId)
          .set({
        'lastPartIndex': idx,
        'lastPositionMs': pos,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _flushListeningTick() async {
    if (!_listenWatch.isRunning) return;

    final sec = _listenWatch.elapsed.inSeconds;
    if (sec <= 0) return;

    _listenWatch.reset();              // ✅ نصفر ونكمل يعد من جديد
    _sessionListenedSeconds += sec;    // ✅ نجمعها مثل نظامك الحالي
    await _saveListeningStats();       // ✅ هنا يصير فحص الهدف + الديالوق
  }

  Future<void> _loadContentProgress() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.bookId)
          .get();

      final data = doc.data() ?? {};
      final savedContent = (data['contentMs'] is num)
          ? (data['contentMs'] as num).toInt()
          : 0;

      if (!mounted) return;
      setState(() {
        _maxReachedMs = savedContent; // ✅ هذا اللي يخلي البار الأخضر ما يتصفر
      });
    } catch (_) {}
  }
  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    _player.playingStream.listen((isPlaying) async {
      if (isPlaying) {
        if (!_listenWatch.isRunning) _listenWatch.start();

        _statsTimer ??= Timer.periodic(const Duration(seconds: 25), (_) async {
          await _flushListeningTick();
        });

        // ✅ NEW: حفظ مكان الاستماع تلقائيًا
        _resumeTimer ??= Timer.periodic(const Duration(seconds: 8), (_) async {
          await _autoSaveResume();
        });

      } else {
        _statsTimer?.cancel();
        _statsTimer = null;

        // ✅ NEW: أول ما يوقف احفظ مرة
        _resumeTimer?.cancel();
        _resumeTimer = null;
        await _autoSaveResume();

        if (_listenWatch.isRunning) {
          _listenWatch.stop();
          _sessionListenedSeconds += _listenWatch.elapsed.inSeconds;
          _listenWatch.reset();
          await _saveListeningStats();
        }
      }
    });

    _init();
  }

  Future<void> _init() async {
    try {
      final sources =
      widget.audioUrls.map((u) => AudioSource.uri(Uri.parse(u))).toList();
      final playlist = ConcatenatingAudioSource(children: sources);

      await _player.setAudioSource(
        playlist,
        initialIndex:
        widget.initialPartIndex.clamp(0, widget.audioUrls.length - 1),
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

      // ✅ اكتمل الكتاب -> نحفظ "مكتمل" + إجمالي المدة + التقدم للنهاية
      _player.processingStateStream.listen((state) async {
        if (state == ProcessingState.completed) {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          final total = _totalMs();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('library')
              .doc(widget.bookId)
              .set({
            'inLibrary': true,
            'status': 'listened', // ✅ هنا النقل لتبويب استمعت لها
            'isCompleted': true,
            'completedAt': FieldValue.serverTimestamp(),
            'totalMs': total,
            'contentMs': total,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });

      await _loadAllDurationsFromUrls();
      await _ensureEstimatedTotalSaved();
      await _loadContentProgress();
      await _saveBarProgress(force: true);
    } catch (_) {
      setState(() => _loading = false);
      if (mounted) {
        _showSnack(context, 'تعذّر تشغيل الصوت', icon: Icons.error_outline);
      }
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
    await _player.seek(
      Duration(milliseconds: lastDur > 0 ? lastDur : 0),
      index: lastIndex,
    );
  }

  Future<String?> _addMark({String note = ''}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final idx = _player.currentIndex ?? 0;
      final posMs = _player.position.inMilliseconds;
      final gMs = _globalPosMs(); // عندك جاهزة

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.bookId)
          .collection('marks')
          .doc();

      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'partIndex': idx,
        'positionMs': posMs,
        'globalMs': gMs,
        'note': note,
      });

      return ref.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showAddNoteSheet({required String markId}) async {
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _pillGreen.withOpacity(0.96),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إضافة ملاحظة',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'اكتب ملاحظة عن هذا الموضع...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('library')
                            .doc(widget.bookId)
                            .collection('marks')
                            .doc(markId)
                            .set({
                          'note': ctrl.text.trim(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        if (ctx.mounted) Navigator.pop(ctx);

                        if (mounted) {
                          _showSnack(context, 'تم حفظ الملاحظة ');
                        }
                      },
                      child: const Text(
                        'حفظ الملاحظة',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onMarkPressed() async {
    final id = await _addMark(); // يضيف علامة بدون ملاحظة
    if (!mounted) return;

    if (id == null) {
      _showSnack(context, 'تعذّر إضافة علامة', icon: Icons.error_outline);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: const Text(
          'تمت إضافة علامة ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        action: SnackBarAction(
          label: 'إضافة ملاحظة',
          textColor: Colors.white,
          onPressed: () => _showAddNoteSheet(markId: id),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ✅ التعديل: حفظ التقدم لكل يوزر (users/{uid}/library/{bookId})
  Future<void> _saveProgress() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idx = _player.currentIndex ?? 0;
      final pos = _player.position.inMilliseconds;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.bookId)
          .set({
            'lastPartIndex': idx,
            'lastPositionMs': pos,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _saveBarProgress({bool force = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (!_durationsReady) return;

      final now = DateTime.now();
      if (!force && now.difference(_lastWrite).inSeconds < 5) return;
      _lastWrite = now;

      final total = _totalMs();
      if (total <= 0) return;

      final gpos = _globalPosMs().clamp(0, total);
      final currentContent = (_maxReachedMs > gpos ? _maxReachedMs : gpos);

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.bookId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() as Map<String, dynamic>? ?? {};

        final oldContent = (data['contentMs'] is num)
            ? (data['contentMs'] as num).toInt()
            : 0;
        final oldTotal = (data['totalMs'] is num)
            ? (data['totalMs'] as num).toInt()
            : 0;
        final oldCompleted = (data['isCompleted'] == true);

        final newTotal = (oldTotal > total) ? oldTotal : total;
        final newContent = (oldContent > currentContent) ? oldContent : currentContent;

        final finalCompleted =
            oldCompleted || (newTotal > 0 && newContent >= newTotal);

        tx.set(ref, {
          'totalMs': newTotal,
          'contentMs': finalCompleted ? newTotal : newContent,
          'isCompleted': finalCompleted,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      // ✅ NEW: إذا وصل 100% انقلي الكتاب إلى "استمعت لها" مرة واحدة فقط
      final reachedEnd = currentContent >= total;
      if (reachedEnd && !_movedToListened) {
        _movedToListened = true;

        await ref.set({
          'bookId': widget.bookId,
          'inLibrary': true,

          // ✅ بيانات عشان يظهر في المكتبة بشكل صحيح حتى لو ما كان مضاف
          'title': widget.bookTitle,
          'author': widget.bookAuthor,
          'coverUrl': widget.coverUrl,
          'addedAt': FieldValue.serverTimestamp(),

          // ✅ النقل
          'status': 'listened',
          'isCompleted': true,
          'completedAt': FieldValue.serverTimestamp(),
          'contentMs': total,
          'totalMs': total,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  DateTime _startOfWeek(DateTime d) {
    // Saturday = 6 in Dart (Mon=1..Sun=7)
    final start = DateTime.saturday; // 6
    final diff = (d.weekday - start + 7) % 7; // 0..6
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  String _weekKey(DateTime d) {
    final s = _startOfWeek(d);
    return '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveListeningStats() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (_sessionListenedSeconds < 1) return;

      final statsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('stats')
          .doc('main');

      // ✅ تحقق من الأسبوع وصفّر إذا أسبوع جديد
      final now = DateTime.now();
      final wk = _weekKey(now);

      final statsSnap = await statsRef.get();
      final stats = statsSnap.data() ?? {};
      final storedWeek = (stats['weeklyKey'] ?? '') as String;

      // ✅ لو أسبوع جديد -> صفّر weeklyListenedSeconds
      if (storedWeek != wk) {
        await statsRef.set({
          'weeklyKey': wk,
          'weeklyListenedSeconds': 0,
          'weeklyResetAt': FieldValue.serverTimestamp(),

          // ✅ تنظيف جدولة نهاية الأسبوع للأسبوع الجديد
          'endWeekNudgeScheduledKey': '',
          'weeklyGoalCompletedKey': '',

          // ✅ NEW: تصفير إشعار 75% للأسبوع الجديد
          'nearGoalNotifiedWeek': '',
          'nearGoalNotifiedGoalMinutes': 0,
        }, SetOptions(merge: true));

        await GoalNotifications.instance.cancel(4001);
        await GoalNotifications.instance.cancel(4002);
      }

      // ✅ زيدي الأسبوعي + الإجمالي
      await statsRef.set({
        'weeklyKey': wk,
        'weeklyListenedSeconds': FieldValue.increment(_sessionListenedSeconds),
        'totalListenedSeconds': FieldValue.increment(_sessionListenedSeconds),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _maybeNotifyNearWeeklyGoal(wk: wk, statsRef: statsRef);
      await _maybeHandleEndOfWeekLowProgress(wk: wk, statsRef: statsRef);
      await _maybeCelebrateWeeklyGoal(wk: wk, statsRef: statsRef);

      _sessionListenedSeconds = 0;
    } catch (_) {}
  }

  // الحاله الثاني هي اشعار اذا قربت للهدف
  Future<int> _getWeeklyGoalMinutesForMe() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 60;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data() ?? {};

    final weeklyGoal = data['weeklyGoal'];
    if (weeklyGoal is Map) {
      final v = weeklyGoal['minutes'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 60;
    }
    return 60;
  }

  void _showAutoDialogMessage({
    required IconData icon,
    required String title,
    required String body,
    int seconds = 10,
  }) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1.0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            final o = scale.clamp(0.0, 1.0);
            return Opacity(
              opacity: o,
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 22),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              decoration: BoxDecoration(
                color: _pillGreen,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: _accent, size: 56),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      Future.delayed(Duration(seconds: seconds), () {
        if (!mounted) return;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      });
    });
  }

  Future<void> _maybeNotifyNearWeeklyGoal({
    required String wk,
    required DocumentReference<Map<String, dynamic>> statsRef,
  }) async {
    final goalMinutes = await _getWeeklyGoalMinutesForMe();
    final goalSeconds = goalMinutes * 60;
    if (goalSeconds <= 0) return;

    final snap = await statsRef.get();
    final stats = snap.data() ?? {};
    final weeklySeconds = (stats['weeklyListenedSeconds'] is num)
        ? (stats['weeklyListenedSeconds'] as num).toInt()
        : 0;

    const nearRatio = 0.75;
    final reachedNear = weeklySeconds >= (goalSeconds * nearRatio).floor();
    if (!reachedNear) return;

    // ✅ الجديد: مرة واحدة فقط لكل أسبوع (على أول هدف)
    final notifiedWeek = (stats['nearGoalNotifiedWeek'] ?? '') as String;
    if (notifiedWeek == wk) return;

    await statsRef.set({
      'nearGoalNotifiedWeek': wk,
      // نخزن أول هدف انحط هذا الأسبوع (للتتبع فقط)
      'nearGoalNotifiedGoalMinutes': goalMinutes,
      'nearGoalNotifiedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _showAutoDialogMessage(
      icon: Icons.trending_up_rounded,
      title: 'أحسنت التقدّم 👏🏻',
      body: 'أنت قريب من تحقيق هدفك الأسبوعي 🎖️\nاستمر… أنت على الطريق الصحيح 💚',
      seconds: 10,
    );
  }

  //الحاله الثالثه و هي اذا تاخر عن الهدف
  Future<void> _maybeHandleEndOfWeekLowProgress({
    required String wk,
    required DocumentReference<Map<String, dynamic>> statsRef,
  }) async {
    // 1) نجيب الهدف
    final goalMinutes = await _getWeeklyGoalMinutesForMe();
    final goalSeconds = goalMinutes * 60;
    if (goalSeconds <= 0) return;

    // 2) نجيب الاستماع الأسبوعي الحالي
    final snap = await statsRef.get();
    final stats = snap.data() ?? {};
    final weeklySeconds = (stats['weeklyListenedSeconds'] is num)
        ? (stats['weeklyListenedSeconds'] as num).toInt()
        : 0;

    // 3) شرط "ضعيف جدًا" (مثال: أقل من 25%)
    const lowRatio = 0.25;
    final isLow = weeklySeconds < (goalSeconds * lowRatio);

    // نخزن مفتاح الأسبوع عشان ما نعيد الجدولة كل مرة
    final scheduledKey = (stats['endWeekNudgeScheduledKey'] ?? '') as String;

    // IDs ثابتة
    const thuId = 4001;
    const friId = 4002;

    if (!isLow) {
      // تحسن -> نلغي إشعارات نهاية الأسبوع (لو كانت مجدولة)
      await GoalNotifications.instance.cancel(thuId);
      await GoalNotifications.instance.cancel(friId);

      // (اختياري) نثبت إننا مو محتاجينها هذا الأسبوع
      await statsRef.set({
        'endWeekNudgeScheduledKey': '',
      }, SetOptions(merge: true));

      return;
    }

    // لو ضعيف + مو مجدول لهذا الأسبوع -> جدوله مرة واحدة فقط
    if (scheduledKey == wk) return;

    // 4) جدولة تذكير الخميس 8 مساء
    await GoalNotifications.instance.scheduleEndOfWeekReminder(
      id: thuId,
      weekday: DateTime.thursday,
      hour: 20,
      minute: 0,
      title: 'لا تدعي الأسبوع يفوتك',
      body: 'خطوة بسيطة اليوم قد تقرّبك من هدفك… استمعي قليلًا وابدئي من جديد.',
    );

    // 5) جدولة تذكير الجمعة 8 مساء
    await GoalNotifications.instance.scheduleEndOfWeekReminder(
      id: friId,
      weekday: DateTime.friday,
      hour: 20,
      minute: 0,
      title: 'فرصة أخيرة هذا الأسبوع',
      body: 'ما زال بإمكانك التقدّم… دقائق قليلة الآن تصنع فرقًا جميلًا.',
    );

    await statsRef.set({
      'endWeekNudgeScheduledKey': wk,
      'endWeekNudgeScheduledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  //الحاله الرابعه و الخامسه في حال اكتمال الهدف سوا وسط الاسبوع او نهايه الاسبوع
  Future<void> _maybeCelebrateWeeklyGoal({
    required String wk,
    required DocumentReference<Map<String, dynamic>> statsRef,
  }) async {
    final goalMinutes = await _getWeeklyGoalMinutesForMe();
    final goalSeconds = goalMinutes * 60;
    if (goalSeconds <= 0) return;

    final snap = await statsRef.get();
    final stats = snap.data() ?? {};
    final weeklySeconds = (stats['weeklyListenedSeconds'] is num)
        ? (stats['weeklyListenedSeconds'] as num).toInt()
        : 0;

    final reached = weeklySeconds >= goalSeconds;
    if (!reached) return;

    // ✅ منع التكرار: مرة واحدة لكل (أسبوع + هدف)
    final thisKey = '$wk-$goalMinutes';
    final completedKey = (stats['weeklyGoalCompletedKey'] ?? '') as String;
    if (completedKey == thisKey) return;

    await statsRef.set({
      'weeklyGoalCompletedKey': thisKey,
      'weeklyGoalCompletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    // ✅ مهم جدًا عشان يطلع الديالوق حتى لو الاستدعاء جاء من Timer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _confettiController.play();

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => Stack(
          alignment: Alignment.topCenter,
          children: [
            // 🎉 Confetti
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 25,
              gravity: 0.25,
              shouldLoop: false,
              colors: const [
                _accent,
                _midPillGreen,
                _softRose,
                _lightSoftRose,
              ],
            ),

            // 💬 Dialog مع أنيميشن
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1.0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                final o = scale.clamp(0.0, 1.0);
                return Opacity(
                  opacity: o,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  decoration: BoxDecoration(
                    color: _pillGreen,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.emoji_events_rounded,
                          color: _accent,
                          size: 56,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'مبروك! 🎉',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'تم تحقيق هدفك الأسبوعي 👏🏻\nاستمر على هذا التقدّم الجميل ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      // ⏱️ إغلاق تلقائي بعد 10 ثواني
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted) return;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      });
    });
  }

  Future<void> _ensureEstimatedTotalSaved() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (!_durationsReady) return;

      final totalSeconds = (_totalMs() / 1000).round();
      if (totalSeconds <= 0) return;

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.bookId);

      await ref.set({
        'estimatedTotalSeconds': totalSeconds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .doc(widget.bookId);

    if (_isBookmarked) {
      await ref.set({
        'lastPartIndex': FieldValue.delete(),
        'lastPositionMs': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isBookmarked = false);
    } else {
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

  Future<void> _showSpeedMenu(BuildContext btnContext) async {
    final RenderBox button = btnContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
    Overlay.of(btnContext).context.findRenderObject() as RenderBox;

    final Offset pos = button.localToGlobal(Offset.zero, ancestor: overlay);

    // ✅ تقدير عرض القائمة (صغير)
    const double menuW = 140;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(
        // ✅ يسار الزر (RTL أفضل)
        (pos.dx - menuW + 6).clamp(0.0, overlay.size.width - menuW),
        pos.dy + 4,
        menuW,
        button.size.height,
      ),
      Offset.zero & overlay.size,
    );

    final picked = await showMenu<double>(
      context: btnContext,
      position: position,
      elevation: 0,
      // ✅ لون pillGreen مع شفافية
      color: _pillGreen.withOpacity(0.75),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      items: _speeds.reversed.map((s) {
        final selected = s == _speed;
        final label = '${s.toStringAsFixed(s % 1 == 0 ? 0 : 2)}x';

        return PopupMenuItem<double>(
          value: s,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _primary, // ✅ صار غامق عشان خلفية فاتحة
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (selected)
                const Icon(Icons.check, color: _primary, size: 18)
              else
                const SizedBox(width: 18),
            ],
          ),
        );
      }).toList(),
    );

    if (picked == null) return;

    setState(() => _speed = picked);
    await _player.setSpeed(picked);
  }

  Future<void> _openMarks() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarksNotesPage(bookId: widget.bookId),
      ),
    );

    if (!mounted) return;

    if (result is Map && result['globalMs'] is int) {
      final ms = result['globalMs'] as int;
      await _seekGlobalMs(ms);
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _resumeTimer = null;

    _autoSaveResume();          // ✅ آخر حفظ للمكان
    _saveBarProgress(force: true);

    _statsTimer?.cancel();
    _statsTimer = null;

    if (_listenWatch.isRunning) {
      _listenWatch.stop();
      _sessionListenedSeconds += _listenWatch.elapsed.inSeconds;
      _listenWatch.reset();
    }
    if (_sessionListenedSeconds > 0) _saveListeningStats();

    _confettiController.dispose();
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
              toolbarHeight: 130,
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        const SizedBox(height: 15),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: whiteCard,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [

                              _playerMiniBar(),
                              const SizedBox(height:45),

                              Container(
                                width: 190,
                                height: 235,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: widget.coverUrl.isNotEmpty
                                    ? Image.network(
                                        widget.coverUrl,
                                        fit: BoxFit.contain,
                                      )
                                    : const Icon(
                                        Icons.menu_book,
                                        size: 70,
                                        color: _primary,
                                      ),
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
                          child: Column(
                            children: [

                              StreamBuilder<Duration>(
                                stream: _player.positionStream,
                                builder: (context, snap) {
                                  final total = _totalMs();
                                  final gpos = _globalPosMs();
                                  final currentMs = gpos.clamp(0, total > 0 ? total : 0);

                                  if (currentMs > _maxReachedMs) _maxReachedMs = currentMs;

                                  final value = (total > 0) ? (currentMs / total) : 0.0;

                                  final leftMs = currentMs;
                                  final rightMs = total > 0 ? total : 0;

                                  return Column(
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: _darkGreen,
                                          inactiveTrackColor: _pillGreen,
                                          thumbColor: _darkGreen,
                                          overlayColor: _darkGreen.withOpacity(0.15),
                                          trackHeight: 4,
                                        ),
                                        child: Slider(
                                          value: value.clamp(0.0, 1.0),
                                          onChanged: total <= 0
                                              ? null
                                              : (v) async {
                                            final target = (total * v).round();
                                            await _seekGlobalMs(target);
                                          },
                                        ),
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
                                          child: Text(
                                            'جاري حساب مدة الكتاب...',
                                            style: TextStyle(color: Colors.black54),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              iconSize: 42,
                              onPressed: () => _seekBy(-10),
                              icon: const Icon(
                                Icons.replay_10_rounded,
                                color: _midDarkGreen2,
                              ),
                            ),
                            const SizedBox(width: 16),
                            StreamBuilder<PlayerState>(
                              stream: _player.playerStateStream,
                              builder: (context, s) {
                                final playing = s.data?.playing ?? false;
                                return CircleAvatar(
                                  radius: 34,
                                  backgroundColor: _midPillGreen,
                                  child: IconButton(
                                    iconSize: 40,
                                    onPressed: () async {
                                      if (playing) {
                                        await _saveBarProgress(
                                          force: true,
                                        );
                                        await _player.pause();
                                      } else {
                                        await _player.play();
                                      }
                                    },
                                    icon: Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
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
                              icon: const Icon(
                                Icons.forward_10_rounded,
                                color: _midDarkGreen2,
                              ),
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
                                onPressed: _onMarkPressed,
                                icon: const Icon(Icons.bookmark_add_rounded,
                                  color: _midDarkGreen2,
                                  size: 26,
                                ),
                                label: const Text(
                                  'علامة',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: _midDarkGreen2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Builder(
                              builder: (btnContext) {
                                return SizedBox(
                                  height: 64,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: whiteCard,
                                      foregroundColor: _midDarkGreen2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _showSpeedMenu(btnContext),
                                    icon: const Icon(Icons.speed_rounded, size: 26),
                                    label: Text(
                                      '${_speed.toStringAsFixed(2)}x',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              },
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

  Widget _playerMiniBar() {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final total = _totalMs();
        final current = _globalPosMs();

        if (total <= 0) return const SizedBox.shrink();

        final currentMs = current.clamp(0, total);

        if (currentMs > _maxReachedMs) _maxReachedMs = currentMs;

        final p = (_maxReachedMs / total).clamp(0.0, 1.0);
        final percent = (p * 100).round();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              alignment: Alignment.center,
              children: [
                LinearProgressIndicator(
                  value: p,
                  minHeight: 18,
                  backgroundColor: _pillGreen,
                  valueColor: const AlwaysStoppedAnimation<Color>(_midPillGreen),
                ),

                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _darkGreen,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
