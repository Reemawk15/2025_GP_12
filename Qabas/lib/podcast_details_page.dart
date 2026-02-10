// podcast_details_page.dart
// ✅ نسخة “نفس كل شي” لكن كبودكاست (ملف صوت واحد):
// 1) كل النصوص: "كتاب" -> "بودكاست"
// 2) حذف: (ملخص) + (الكاتب) + (الشات بوت)
// 3) باقي كل شيء كما هو: التقييمات/التعليقات/الإضافة للقائمة/العلامات/المشغل/الأهداف…
//
// ✅ تعديل مهم: تشغيل من ملف الأدمن فقط (audioUrl) بدون توليد وبدون Cloud Functions

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import 'friend_details_page.dart';
import 'goal_notifications.dart';
import 'marks_notes_page.dart';

import 'dart:async';
import 'package:confetti/confetti.dart';

// Theme colors
const _primary = Color(0xFF0E3A2C); // Dark text/icons
const _accent = Color(0xFF6F8E63); // SnackBar + buttons
const _pillGreen = Color(0xFFE6F0E0); // Soft background
const _chipRose = Color(0xFFFFEFF0); // Review bubble bg
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

class PodcastDetailsPage extends StatelessWidget {
  final String podcastId;
  const PodcastDetailsPage({super.key, required this.podcastId});

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// ✅ تشغيل فقط من ملف الأدمن (audioUrl)
  Future<void> _startAudioOnly(
      BuildContext context, {
        required String audioUrl,
        required String title,
        required String cover,
        int? overridePositionMs,
      }) async {
    final url = audioUrl.trim();
    if (url.isEmpty) {
      _showSnack(
        context,
        'لا يوجد ملف صوت مرفوع لهذا البودكاست',
        icon: Icons.info_outline,
      );
      return;
    }

    int lastPositionMs = 0;
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        final progSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('library')
            .doc(podcastId)
            .get();

        final p = progSnap.data() ?? {};
        lastPositionMs = _asInt(p['lastPositionMs'], fallback: 0);
      } catch (_) {}
    }

    // ✅ لو جاية من علامة/ملاحظة: نغلبها
    if (overridePositionMs != null) {
      lastPositionMs = overridePositionMs;
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PodcastAudioPlayerPage(
          podcastId: podcastId,
          podcastTitle: title,
          coverUrl: cover,
          audioUrl: url, // 🎧 ملف واحد
          initialPositionMs: lastPositionMs,
        ),
      ),
    );
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
                'تفاصيل البودكاست',
                style: TextStyle(color: _primary),
              ),
            ),
            body: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('podcasts')
                  .doc(podcastId)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return const Center(child: Text('تعذّر تحميل تفاصيل البودكاست'));
                }

                final data = snap.data!.data() as Map<String, dynamic>? ?? {};
                final title = (data['title'] ?? '').toString();
                final cover = (data['coverUrl'] ?? '').toString();
                final category = (data['category'] ?? '').toString();
                final desc = (data['description'] ?? '').toString();

                final audioUrl = (data['audioUrl'] ?? '').toString().trim();
                final hasAudio = audioUrl.isNotEmpty;

                final listenLabel = hasAudio ? 'استمع' : 'لا يوجد ملف صوت';

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
                            Icons.podcasts_rounded,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

                      _AverageRatingRow(podcastId: podcastId),
                      const SizedBox(height: 18),

                      _PillCard(
                        title: 'نبذة عن البودكاست :',
                        child: Text(
                          desc.isEmpty ? 'لا توجد نبذة متاحة حالياً.' : desc,
                        ),
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
                          onPressed: hasAudio
                              ? () => _startAudioOnly(
                            context,
                            audioUrl: audioUrl,
                            title: title,
                            cover: cover,
                          )
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.headphones_rounded, size: 24),
                              const SizedBox(width: 12),
                              Text(
                                listenLabel,
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
                        'التعليقات حول البودكاست:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ReviewsList(podcastId: podcastId),

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      _InlineActionsRow(
                        onAddToList: () => _showAddToListSheet(
                          context,
                          podcastId: podcastId,
                          title: title,
                          cover: cover,
                        ),
                        onDownload: null,
                        onReview: () => _showAddReviewSheet(context, podcastId, title, cover),
                        onMarks: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MarksNotesPage(bookId: podcastId),
                            ),
                          );

                          if (result is Map && result['positionMs'] is int) {
                            final positionMs = result['positionMs'] as int;

                            await _startAudioOnly(
                              context,
                              audioUrl: audioUrl,
                              title: title,
                              cover: cover,
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
            floatingActionButton: null,
          ),
        ],
      ),
    );
  }

  void _showAddToListSheet(
      BuildContext context, {
        required String podcastId,
        required String title,
        required String cover,
      }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddToListSheet(
        podcastId: podcastId,
        title: title,
        cover: cover,
      ),
    );
  }

  void _showAddReviewSheet(
      BuildContext context,
      String podcastId,
      String title,
      String cover,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddReviewSheet(
        podcastId: podcastId,
        podcastTitle: title,
        podcastCover: cover,
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
        item(Icons.download_rounded, 'تحميل', 'البودكاست', onDownload),
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
  final String podcastId;
  const _AverageRatingRow({required this.podcastId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('podcasts')
          .doc(podcastId)
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
  final String podcastId;
  const _ReviewsList({required this.podcastId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('podcasts')
          .doc(podcastId)
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
            child: Text('لا توجد تعليقات بعد. كن أول من يقيّم هذا البودكاست!'),
          );
        }

        return Column(
          children: items.map((d) {
            final m = d.data() as Map<String, dynamic>? ?? {};
            final userName = (m['userName'] ?? 'مستمع').toString();
            final userImageUrl = (m['userImageUrl'] ?? '').toString();
            final rating = (m['rating'] ?? 0);
            final ratingDouble = rating is int ? rating.toDouble() : (rating as double? ?? 0.0);
            final text = (m['text'] ?? '').toString();
            final userId = (m['userId'] ?? '').toString();

            final bool hasImage = userImageUrl.isNotEmpty;

            final avatar = CircleAvatar(
              radius: 22,
              backgroundColor: _accent.withOpacity(0.25),
              backgroundImage: hasImage ? NetworkImage(userImageUrl) : null,
              child: !hasImage
                  ? Text(
                userName.isNotEmpty ? userName.characters.first : 'م',
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
                                style: const TextStyle(fontWeight: FontWeight.w700),
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

/// Bottom sheet: Add podcast to user's list
class _AddToListSheet extends StatelessWidget {
  final String podcastId, title, cover;
  const _AddToListSheet({
    required this.podcastId,
    required this.title,
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
        .doc(podcastId);

    await ref.set({
      'bookId': podcastId, // ✅ نخليها bookId إذا ملفاتك تعتمد عليه
      'status': status,
      'title': title,
      'coverUrl': cover,
      'addedAt': FieldValue.serverTimestamp(),
      'type': 'podcast',
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
              title: const Text('استمع الآن'),
              onTap: () => _setStatus(context, 'listen_now'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: _primary),
              title: const Text('أرغب بالاستماع'),
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
  final String podcastId;
  final String podcastTitle;
  final String podcastCover;

  const _AddReviewSheet({
    required this.podcastId,
    required this.podcastTitle,
    required this.podcastCover,
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

    String userName = user.displayName ?? 'مستمع';
    String userImageUrl = user.photoURL ?? '';

    try {
      final u = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (u.exists) {
        final data = u.data() ?? {};
        final candidateName =
        (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '').toString();
        if (candidateName.trim().isNotEmpty) userName = candidateName;

        final candidateImage = (data['photoUrl'] ?? '').toString();
        if (candidateImage.trim().isNotEmpty) userImageUrl = candidateImage;
      }
    } catch (_) {}

    try {
      final batch = FirebaseFirestore.instance.batch();

      final podcastReviewRef = FirebaseFirestore.instance
          .collection('podcasts')
          .doc(widget.podcastId)
          .collection('reviews')
          .doc();

      final userReviewRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('reviews')
          .doc(podcastReviewRef.id);

      final payload = {
        'userId': user.uid,
        'userName': userName,
        'userImageUrl': userImageUrl,
        'podcastId': widget.podcastId,
        'podcastTitle': widget.podcastTitle,
        'podcastCover': widget.podcastCover,
        'rating': _rating,
        'text': _ctrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'podcast',
      };

      batch.set(podcastReviewRef, payload);
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
            color: _pillGreen.withOpacity(0.96),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  hintText: 'اكتب رأيك حول البودكاست...',
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

/// AUDIO PLAYER PAGE (بودكاست) — ✅ ملف واحد فقط
class PodcastAudioPlayerPage extends StatefulWidget {
  final String podcastId;
  final String podcastTitle;
  final String coverUrl;

  final String audioUrl; // ✅ ملف واحد
  final int initialPositionMs;

  const PodcastAudioPlayerPage({
    super.key,
    required this.podcastId,
    required this.podcastTitle,
    required this.coverUrl,
    required this.audioUrl,
    required this.initialPositionMs,
  });

  @override
  State<PodcastAudioPlayerPage> createState() => _PodcastAudioPlayerPageState();
}

class _PodcastAudioPlayerPageState extends State<PodcastAudioPlayerPage> {
  late final AudioPlayer _player;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  final Stopwatch _listenWatch = Stopwatch();
  int _sessionListenedSeconds = 0;
  late final ConfettiController _confettiController;

  bool _loading = true;

  double _speed = 1.0;
  final List<double> _speeds = const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  bool _movedToListened = false;

  Duration? _duration;
  bool _durationReady = false;

  bool _isBookmarked = false;
  int _maxReachedMs = 0;

  Timer? _statsTimer;
  Timer? _resumeTimer;

  Future<void> _autoSaveResume() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final pos = _player.position.inMilliseconds;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.podcastId)
          .set({
        'lastPositionMs': pos,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _flushListeningTick() async {
    if (!_listenWatch.isRunning) return;

    final sec = _listenWatch.elapsed.inSeconds;
    if (sec <= 0) return;

    _listenWatch.reset();
    _sessionListenedSeconds += sec;
    await _saveListeningStats();
  }

  Future<void> _loadContentProgress() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.podcastId)
          .get();

      final data = doc.data() ?? {};
      final savedContent = (data['contentMs'] is num) ? (data['contentMs'] as num).toInt() : 0;

      if (!mounted) return;
      setState(() {
        _maxReachedMs = savedContent;
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

        _resumeTimer ??= Timer.periodic(const Duration(seconds: 8), (_) async {
          await _autoSaveResume();
        });
      } else {
        _statsTimer?.cancel();
        _statsTimer = null;

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
      final d = await _player.setUrl(widget.audioUrl);

      final startPos = Duration(milliseconds: widget.initialPositionMs.clamp(0, 1 << 30));
      await _player.seek(startPos);

      await _player.setSpeed(_speed);

      _isBookmarked = widget.initialPositionMs > 0;

      _duration = d;
      _durationReady = (d != null && d.inMilliseconds > 0);

      if (mounted) setState(() => _loading = false);

      _player.processingStateStream.listen((state) async {
        if (state == ProcessingState.completed) {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;

          final total = _totalMs();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('library')
              .doc(widget.podcastId)
              .set({
            'inLibrary': true,
            'status': 'listened',
            'isCompleted': true,
            'completedAt': FieldValue.serverTimestamp(),
            'totalMs': total,
            'contentMs': total,
            'updatedAt': FieldValue.serverTimestamp(),
            'type': 'podcast',
            'title': widget.podcastTitle,
            'coverUrl': widget.coverUrl,
          }, SetOptions(merge: true));
        }
      });

      await _ensureEstimatedTotalSaved();
      await _loadContentProgress();
      await _saveBarProgress(force: true);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        _showSnack(context, 'تعذّر تشغيل الصوت', icon: Icons.error_outline);
      }
    }
  }

  int _totalMs() => _duration?.inMilliseconds ?? 0;
  int _globalPosMs() => _player.position.inMilliseconds;

  Future<void> _seekGlobalMs(int targetMs) async {
    final total = _totalMs();
    final t = (total > 0) ? targetMs.clamp(0, total) : targetMs;
    await _player.seek(Duration(milliseconds: t));
  }

  Future<void> _seekBy(int seconds) async {
    final total = _totalMs();
    if (total <= 0) return;

    int target = _globalPosMs() + (seconds * 1000);
    if (target < 0) target = 0;
    if (target > total) target = total;

    await _seekGlobalMs(target);
  }

  Future<String?> _addMark({String note = ''}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final posMs = _player.position.inMilliseconds;

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.podcastId)
          .collection('marks')
          .doc();

      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'positionMs': posMs,
        'globalMs': posMs, // ✅ نفس الموضع لأنه ملف واحد
        'note': note,
        'type': 'podcast',
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
                            .doc(widget.podcastId)
                            .collection('marks')
                            .doc(markId)
                            .set({
                          'note': ctrl.text.trim(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showSnack(context, 'تم حفظ الملاحظة ');
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
    final id = await _addMark();
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

  Future<void> _saveProgress() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final pos = _player.position.inMilliseconds;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.podcastId)
          .set({
        'lastPositionMs': pos,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _saveBarProgress({bool force = false}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (!_durationReady) return;

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
          .doc(widget.podcastId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() as Map<String, dynamic>? ?? {};

        final oldContent = (data['contentMs'] is num) ? (data['contentMs'] as num).toInt() : 0;
        final oldTotal = (data['totalMs'] is num) ? (data['totalMs'] as num).toInt() : 0;
        final oldCompleted = (data['isCompleted'] == true);

        final newTotal = (oldTotal > total) ? oldTotal : total;
        final newContent = (oldContent > currentContent) ? oldContent : currentContent;

        final finalCompleted = oldCompleted || (newTotal > 0 && newContent >= newTotal);

        tx.set(ref, {
          'totalMs': newTotal,
          'contentMs': finalCompleted ? newTotal : newContent,
          'isCompleted': finalCompleted,
          'updatedAt': FieldValue.serverTimestamp(),
          'type': 'podcast',
          'title': widget.podcastTitle,
          'coverUrl': widget.coverUrl,
          'inLibrary': true,
        }, SetOptions(merge: true));
      });

      final reachedEnd = currentContent >= total;
      if (reachedEnd && !_movedToListened) {
        _movedToListened = true;
        await ref.set({
          'status': 'listened',
          'isCompleted': true,
          'completedAt': FieldValue.serverTimestamp(),
          'contentMs': total,
          'totalMs': total,
          'updatedAt': FieldValue.serverTimestamp(),
          'type': 'podcast',
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  DateTime _startOfWeek(DateTime d) {
    final start = DateTime.saturday;
    final diff = (d.weekday - start + 7) % 7;
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

      final now = DateTime.now();
      final wk = _weekKey(now);

      final statsSnap = await statsRef.get();
      final stats = statsSnap.data() ?? {};
      final storedWeek = (stats['weeklyKey'] ?? '') as String;

      if (storedWeek != wk) {
        await statsRef.set({
          'weeklyKey': wk,
          'weeklyListenedSeconds': 0,
          'weeklyResetAt': FieldValue.serverTimestamp(),
          'endWeekNudgeScheduledKey': '',
          'weeklyGoalCompletedKey': '',
          'nearGoalNotifiedWeek': '',
          'nearGoalNotifiedGoalMinutes': 0,
        }, SetOptions(merge: true));

        await GoalNotifications.instance.cancel(4001);
        await GoalNotifications.instance.cancel(4002);
      }

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

  Future<int> _getWeeklyGoalMinutesForMe() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 60;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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

    final notifiedWeek = (stats['nearGoalNotifiedWeek'] ?? '') as String;
    if (notifiedWeek == wk) return;

    await statsRef.set({
      'nearGoalNotifiedWeek': wk,
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

  Future<void> _maybeHandleEndOfWeekLowProgress({
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

    const lowRatio = 0.25;
    final isLow = weeklySeconds < (goalSeconds * lowRatio);

    final scheduledKey = (stats['endWeekNudgeScheduledKey'] ?? '') as String;

    const thuId = 4001;
    const friId = 4002;

    if (!isLow) {
      await GoalNotifications.instance.cancel(thuId);
      await GoalNotifications.instance.cancel(friId);

      await statsRef.set({
        'endWeekNudgeScheduledKey': '',
      }, SetOptions(merge: true));

      return;
    }

    if (scheduledKey == wk) return;

    await GoalNotifications.instance.scheduleEndOfWeekReminder(
      id: thuId,
      weekday: DateTime.thursday,
      hour: 20,
      minute: 0,
      title: 'لا تدعي الأسبوع يفوتك',
      body: 'خطوة بسيطة اليوم قد تقرّبك من هدفك… استمعي قليلًا وابدئي من جديد.',
    );

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

    final thisKey = '$wk-$goalMinutes';
    final completedKey = (stats['weeklyGoalCompletedKey'] ?? '') as String;
    if (completedKey == thisKey) return;

    await statsRef.set({
      'weeklyGoalCompletedKey': thisKey,
      'weeklyGoalCompletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _confettiController.play();

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => Stack(
          alignment: Alignment.topCenter,
          children: [
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
                        Icon(Icons.emoji_events_rounded, color: _accent, size: 56),
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

      if (!_durationReady) return;

      final totalSeconds = (_totalMs() / 1000).round();
      if (totalSeconds <= 0) return;

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(widget.podcastId);

      await ref.set({
        'estimatedTotalSeconds': totalSeconds,
        'updatedAt': FieldValue.serverTimestamp(),
        'type': 'podcast',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _showSpeedMenu(BuildContext btnContext) async {
    final RenderBox button = btnContext.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(btnContext).context.findRenderObject() as RenderBox;

    final Offset pos = button.localToGlobal(Offset.zero, ancestor: overlay);

    const double menuW = 140;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(
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
                  color: _primary,
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

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _resumeTimer = null;

    _autoSaveResume();
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
                'تشغيل البودكاست',
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
                        const SizedBox(height: 45),
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
                              : const Icon(Icons.podcasts_rounded, size: 70, color: _primary),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.podcastTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _primary,
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
                            final currentMs = _globalPosMs().clamp(0, total > 0 ? total : 0);

                            if (currentMs > _maxReachedMs) _maxReachedMs = currentMs;

                            final value = (total > 0) ? (currentMs / total) : 0.0;

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
                                    Text(_fmtMs(currentMs),
                                        style: const TextStyle(color: Colors.black54)),
                                    Text(_fmtMs(total),
                                        style: const TextStyle(color: Colors.black54)),
                                  ],
                                ),
                                if (!_durationReady)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                      'جاري حساب مدة البودكاست...',
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
                        icon: const Icon(Icons.replay_10_rounded, color: _midDarkGreen2),
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
                                  await _saveBarProgress(force: true);
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
                        icon: const Icon(Icons.forward_10_rounded, color: _midDarkGreen2),
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
                                borderRadius: BorderRadius.circular(24)),
                            elevation: 0,
                          ),
                          onPressed: _onMarkPressed,
                          icon: const Icon(Icons.bookmark_add_rounded,
                              color: _midDarkGreen2, size: 26),
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
                                    borderRadius: BorderRadius.circular(24)),
                                elevation: 0,
                              ),
                              onPressed: () => _showSpeedMenu(btnContext),
                              icon: const Icon(Icons.speed_rounded, size: 26),
                              label: Text(
                                '${_speed.toStringAsFixed(2)}x',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700),
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
        if (total <= 0) return const SizedBox.shrink();

        final currentMs = _globalPosMs().clamp(0, total);
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
