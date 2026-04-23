import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

/// =======================================================
/// ✅ نفس ألوان/ستايل صفحة الكتاب العادي
/// =======================================================
const _primary = Color(0xFF0E3A2C);
const _accent = Color(0xFF6F8E63);
const _pillGreen = Color(0xFFE6F0E0);
const _chipRose = Color(0xFFFFEFF0);
const _midPillGreen = Color(0xFFBFD6B5);
const _midDarkGreen2 = Color(0xFF2A5C4C);
const Color _darkGreen = Color(0xFF0E3A2C);

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
          Flexible(
            child: Text(
              message,
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

int _asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
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

/// =======================================================
/// ✅ MyBookDetailsPage (نفس خلفية وتصميم تفاصيل الكتاب العادي)
/// - ❌ حذف مربع "متوقف عند .. / مسح" نهائيًا
/// - ✅ زر "استمع" + زر "العلامات والملاحظات" بنفس الستايل والمسميات
/// =======================================================
class MyBookDetailsPage extends StatelessWidget {
  final String bookId; // users/{uid}/mybooks/{bookId}
  const MyBookDetailsPage({super.key, required this.bookId});

  // ===== PDF open helpers =====
  Future<String?> _normalizeUrl(String raw) async {
    String url = raw.trim();
    if (url.isEmpty) return null;

    if (url.startsWith('gs://')) {
      try {
        final ref = storage.FirebaseStorage.instance.refFromURL(url);
        final https = await ref.getDownloadURL();
        return https;
      } catch (_) {
        return null;
      }
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  Future<void> _openPdf(BuildContext context, String rawUrl) async {
    final normalized = await _normalizeUrl(rawUrl);
    if (normalized == null) {
      if (context.mounted) {
        _showSnack(
          context,
          'الرابط غير صالح أو الملف غير متاح',
          icon: Icons.error_outline,
        );
      }
      return;
    }

    final uri = Uri.parse(normalized);
    try {
      final okExternal = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!okExternal) {
        final okInApp = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (!okInApp && context.mounted) {
          _showSnack(
            context,
            'تعذّر فتح ملف الـ PDF',
            icon: Icons.error_outline,
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'تعذّر فتح ملف الـ PDF', icon: Icons.error_outline);
      }
    }
  }

  /// ===== ✅ نفس منطق كتابك: توليد -> Polling فقط (بدون انتقال تلقائي) =====
  Future<void> _startOrGenerateMyBookAudio(
    BuildContext context, {
    required Map<String, dynamic> myBookData,
    required String title,
    required String cover,
  }) async {
    final audioStatus = (myBookData['audioStatus'] ?? 'idle').toString();
    final audioUrl = (myBookData['audioUrl'] ?? '').toString();

    final partsRaw = myBookData['audioParts'];
    final hasParts = partsRaw is List && partsRaw.isNotEmpty;

    final urls = hasParts
        ? partsRaw.map((e) => e.toString()).toList()
        : (audioUrl.trim().isNotEmpty ? [audioUrl.trim()] : <String>[]);

    final lastPosMs = _asInt(myBookData['lastPositionMs'], fallback: 0);

    // ✅ لو جاهز -> افتحي المشغل عند الضغط فقط
    if (urls.isNotEmpty) {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MyBookAudioPlayerPage(
            bookId: bookId,
            bookTitle: title,
            coverUrl: cover,
            audioUrls: urls,
            initialPositionMs: lastPosMs,
          ),
        ),
      );
      return;
    }

    // ✅ لو شغال توليد -> بس polling
    if (audioStatus == 'processing') {
      _showSnack(context, 'جاري توليد الصوت…', icon: Icons.settings_rounded);
      _pollUntilHasMyBookAudio(context);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack(context, 'لازم تسجلين دخول أولاً', icon: Icons.info_outline);
      return;
    }

    try {
      _showSnack(context, 'بدأ توليد الصوت…', icon: Icons.settings_rounded);
      await user.getIdToken(true);

      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable(
        'generateMyBookAudio',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );

      await callable.call({'uid': user.uid, 'bookId': bookId});

      _pollUntilHasMyBookAudio(context);
    } on FirebaseFunctionsException catch (e) {
      _showSnack(context, 'تعذّر: ${e.code}', icon: Icons.error_outline);
      _pollUntilHasMyBookAudio(context);
    } catch (_) {
      _showSnack(context, 'تعذّر توليد الصوت', icon: Icons.error_outline);
    }
  }

  void _pollUntilHasMyBookAudio(BuildContext context) {
    int tries = 0;

    Future.doWhile(() async {
      if (!context.mounted) return false;

      await Future.delayed(const Duration(seconds: 4));
      tries++;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mybooks')
          .doc(bookId)
          .get();

      if (!snap.exists) return false;

      final d = snap.data() as Map<String, dynamic>? ?? {};
      final status = (d['audioStatus'] ?? 'idle').toString();

      final audioUrl = (d['audioUrl'] ?? '').toString();
      final partsRaw = d['audioParts'];
      final hasParts = partsRaw is List && partsRaw.isNotEmpty;

      final urls = hasParts
          ? partsRaw.map((e) => e.toString()).toList()
          : (audioUrl.trim().isNotEmpty ? [audioUrl.trim()] : <String>[]);

      if (status == 'failed') {
        final errMsg = (d['errorMessage'] ?? '').toString().trim();
        _showSnack(
          context,
          errMsg.isEmpty ? 'فشل توليد الصوت' : errMsg,
          icon: Icons.error_outline,
        );
        return false;
      }

      if (urls.isNotEmpty) {
        _showSnack(context, 'تم تجهيز الصوت ✅', icon: Icons.check_circle);
        return false;
      }

      if (tries % 3 == 0) {
        _showSnack(context, 'جاري توليد الصوت…', icon: Icons.settings_rounded);
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

  void _openMarks(
    BuildContext context, {
    required String title,
    required String cover,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MyBookMarksPage(bookId: bookId, bookTitle: title, coverUrl: cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/back_private.png', // ✅ نفس الكتاب العادي
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
              toolbarHeight: 150, // ✅ نفس العادي
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
            body: (user == null)
                ? const Center(child: Text('الرجاء تسجيل الدخول'))
                : StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('mybooks')
                        .doc(bookId)
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snap.hasData || !snap.data!.exists) {
                        return const Center(
                          child: Text('تعذّر تحميل تفاصيل الكتاب'),
                        );
                      }

                      final data =
                          (snap.data!.data() as Map<String, dynamic>? ?? {});
                      final title = (data['title'] ?? '') as String;
                      final cover = (data['coverUrl'] ?? '') as String;
                      final pdfUrl = (data['pdfUrl'] ?? '') as String;

                      final audioStatus = (data['audioStatus'] ?? 'idle')
                          .toString();
                      final audioUrl = (data['audioUrl'] ?? '').toString();
                      final partsRaw = data['audioParts'];
                      final hasAudio =
                          (partsRaw is List && partsRaw.isNotEmpty) ||
                          audioUrl.trim().isNotEmpty;

                      final bool isGenerating =
                          audioStatus == 'processing' && !hasAudio;

                      // ✅ نفس تسمية زر العادي: "استمع" + حالة توليد
                      final listenLabel = hasAudio
                          ? 'استمع'
                          : (isGenerating ? 'جاري توليد الصوت...' : 'استمع');

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          60,
                          16,
                          24,
                        ), // ✅ نفس العادي تقريبًا
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

                            Center(
                              child: Text(
                                title.isEmpty ? 'كتاب بدون عنوان' : title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: _primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ✅ PDF pill card بنفس ستايل العادي
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _pillGreen,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.picture_as_pdf,
                                    color: _primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: pdfUrl.trim().isEmpty
                                        ? const Text(
                                            'لا يوجد ملف PDF',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : InkWell(
                                            onTap: () =>
                                                _openPdf(context, pdfUrl),
                                            child: const Text(
                                              'ملف الكتاب',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: _accent,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ✅ زر الاستماع (pill) نفس العادي
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _pillGreen,
                                  foregroundColor: _primary,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                onPressed: isGenerating
                                    ? null
                                    : () => _startOrGenerateMyBookAudio(
                                        context,
                                        myBookData: data,
                                        title: title,
                                        cover: cover,
                                      ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.headphones_rounded,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      listenLabel,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ✅ زر العلامات والملاحظات (نفس زر استمع تمامًا)
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _pillGreen,
                                  foregroundColor: _primary,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                onPressed: () => _openMarks(
                                  context,
                                  title: title,
                                  cover: cover,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.bookmark_added_rounded,
                                      size: 20,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'العلامات والملاحظات',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 80),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class MyBookMarksPage extends StatelessWidget {
  final String bookId;
  final String bookTitle;
  final String coverUrl;

  const MyBookMarksPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.coverUrl,
  });

  CollectionReference<Map<String, dynamic>>? _marksRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mybooks')
        .doc(bookId)
        .collection('marks');
  }

  DocumentReference<Map<String, dynamic>>? _myBookRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mybooks')
        .doc(bookId);
  }

  Future<List<String>> _getAudioUrls(Map<String, dynamic> myBookData) async {
    final audioUrl = (myBookData['audioUrl'] ?? '').toString().trim();
    final partsRaw = myBookData['audioParts'];
    final hasParts = partsRaw is List && partsRaw.isNotEmpty;

    if (hasParts) return partsRaw.map((e) => e.toString()).toList();
    if (audioUrl.isNotEmpty) return [audioUrl];
    return [];
  }

  Future<void> _openPlayerAt(BuildContext context, int positionMs) async {
    final ref = _myBookRef();
    if (ref == null) return;

    final snap = await ref.get();
    final data = snap.data() ?? {};
    final urls = await _getAudioUrls(data);

    if (urls.isEmpty) {
      _showSnack(
        context,
        'لا يوجد صوت جاهز لهذا الكتاب',
        icon: Icons.info_outline,
      );
      return;
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyBookAudioPlayerPage(
          bookId: bookId,
          bookTitle: bookTitle,
          coverUrl: coverUrl,
          audioUrls: urls,
          initialPositionMs: positionMs,
        ),
      ),
    );
  }

  /// ✅ Dialog حذف (نفس MarksNotesPage)
  Future<bool> _confirmDelete(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'حذف العلامة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _primary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد من حذف هذه العلامة؟ لن يظهر هذا الموضع مرة أخرى.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 18),

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
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'تأكيد',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return res == true;
  }

  @override
  Widget build(BuildContext context) {
    final marks = _marksRef();

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
              toolbarHeight: 120,
              leading: Padding(
                padding: const EdgeInsets.only(top: 36),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _primary,
                    size: 22,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              title: const Padding(
                padding: EdgeInsets.only(top: 36),
                child: Text(
                  'العلامات والملاحظات',
                  style: TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            body: (marks == null)
                ? const Center(child: Text('الرجاء تسجيل الدخول أولاً'))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: marks
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(child: Text('لا توجد علامات بعد.'));
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final docId = doc.id;
                          final m = doc.data();

                          final positionMs = _asInt(
                            m['positionMs'],
                            fallback: 0,
                          );
                          final note = (m['note'] ?? '').toString();

                          // ✅ MyBook ما عنده globalMs/partIndex
                          // نخليها مثل library: نعرض الوقت من positionMs
                          final globalMs = positionMs;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _pillGreen.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _fmtMs(globalMs),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _primary,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  note.trim().isEmpty ? 'بدون ملاحظة' : note,
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(0.65),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // ✅ الصف السفلي (تشغيل + حذف) نفس MarksNotesPage
                                Row(
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _accent,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: () =>
                                          _openPlayerAt(context, positionMs),
                                      child: const Text(
                                        'تشغيل من هنا',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        color: _primary.withOpacity(0.6),
                                      ),
                                      onPressed: () async {
                                        final ok = await _confirmDelete(
                                          context,
                                        );
                                        if (!ok) return;
                                        await marks.doc(docId).delete();
                                        if (context.mounted) {
                                          _showSnack(context, 'تم حذف العلامة');
                                        }
                                      },
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
}

/// =======================================================
/// ✅ MyBook Audio Player (مثل تصميمك الحالي مع Bookmark)
/// - يحفظ lastPositionMs داخل users/{uid}/mybooks/{bookId}
/// =======================================================
class MyBookAudioPlayerPage extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final String coverUrl;

  final List<String> audioUrls;
  final int initialPositionMs;

  const MyBookAudioPlayerPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.coverUrl,
    required this.audioUrls,
    required this.initialPositionMs,
  });

  @override
  State<MyBookAudioPlayerPage> createState() => _MyBookAudioPlayerPageState();
}

class _MyBookAudioPlayerPageState extends State<MyBookAudioPlayerPage> {
  late final AudioPlayer _player;
  bool _loading = true;

  double _speed = 1.0;

  double? _dragValue;
  bool _isDragging = false;
  final List<double> _speeds = const [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  // ✅ حفظ مكان الاستماع
  Timer? _resumeTimer;

  // ✅ progress ثابت مثل كتابك العادي
  List<Duration?> _durations = [];
  bool _durationsReady = false;
  int _maxReachedMs = 0; // أعلى نقطة وصلها (global ms)
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ goal tracking
  final Stopwatch _listenWatch = Stopwatch();
  int _sessionListenedSeconds = 0;
  Timer? _statsTimer;

  bool _isBookmarked = false;

  DocumentReference<Map<String, dynamic>>? _myBookRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('mybooks')
        .doc(widget.bookId);
  }

  // =======================
  // ✅ durations + global ms
  // =======================
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

  // =======================
  // ✅ Marks
  // =======================
  Future<String?> _addMark({String note = ''}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final idx = _player.currentIndex ?? 0;
      final posMs = _player.position.inMilliseconds;
      final gMs = _globalPosMs();

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mybooks')
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
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('mybooks')
                            .doc(widget.bookId)
                            .collection('marks')
                            .doc(markId)
                            .set({
                              'note': ctrl.text.trim(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showSnack(context, 'تم حفظ الملاحظة');
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
          'تمت إضافة علامة',
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

  // =======================
  // ✅ Resume save
  // =======================
  Future<void> _autoSaveResume() async {
    try {
      final ref = _myBookRef();
      if (ref == null) return;

      final idx = _player.currentIndex ?? 0;
      final pos = _player.position.inMilliseconds;

      await ref.set({
        'lastPartIndex': idx,
        'lastPositionMs': pos,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // =======================
  // ✅ Persistent progress bar (contentMs/totalMs)
  // =======================
  Future<void> _loadContentProgress() async {
    try {
      final ref = _myBookRef();
      if (ref == null) return;

      final doc = await ref.get();
      final data = doc.data() ?? {};
      final saved = (data['contentMs'] is num)
          ? (data['contentMs'] as num).toInt()
          : 0;

      if (!mounted) return;
      setState(() => _maxReachedMs = saved);
    } catch (_) {}
  }

  Future<void> _loadAllDurationsFromUrls() async {
    try {
      // لو جاهزة مسبقًا
      if (_durations.isNotEmpty &&
          _durations.length == widget.audioUrls.length &&
          _durations.every((d) => d != null && d!.inMilliseconds > 0)) {
        if (mounted) setState(() => _durationsReady = true);
        return;
      }

      // نقرأ durations من sequence أولاً
      _durations = _player.sequence?.map((s) => s.duration).toList() ?? [];

      // ثم نتأكد عبر tmp player (زي كتابك العادي)
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

  Future<void> _ensureEstimatedTotalSaved() async {
    try {
      final ref = _myBookRef();
      if (ref == null) return;
      if (!_durationsReady) return;

      final total = _totalMs();
      if (total <= 0) return;

      await ref.set({
        'totalMs': total,
        'estimatedTotalSeconds': (total / 1000).round(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _saveBarProgress({bool force = false}) async {
    try {
      final ref = _myBookRef();
      if (ref == null) return;
      if (!_durationsReady) return;

      final now = DateTime.now();
      if (!force && now.difference(_lastWrite).inSeconds < 5) return;
      _lastWrite = now;

      final total = _totalMs();
      if (total <= 0) return;

      final gpos = _globalPosMs().clamp(0, total);

      final currentContent = (_maxReachedMs > gpos) ? _maxReachedMs : gpos;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await ref.get();
        final data = snap.data() ?? {};

        // 🚫 إذا الكتاب مكتمل → لا تحدث البار
        if ((data['status'] ?? '') == 'listened') {
          return;
        }

        final oldContent = (data['contentMs'] is num)
            ? (data['contentMs'] as num).toInt()
            : 0;
        final oldTotal = (data['totalMs'] is num)
            ? (data['totalMs'] as num).toInt()
            : 0;

        final newTotal = (oldTotal > total) ? oldTotal : total;
        final newContent = currentContent;
        // ✅ تحقق إذا وصل 100%
        final isCompleted = newContent >= newTotal && newTotal > 0;

        tx.set(ref, {
          'totalMs': newTotal,
          'contentMs': newContent,
          'updatedAt': FieldValue.serverTimestamp(),

          // ✅ إذا اكتمل → انقله لـ listened
          if (isCompleted) 'status': 'listened',
        }, SetOptions(merge: true));
      });
    } catch (_) {}
  }

  // =======================
  // ✅ Weekly goal logic (same stats path)
  // =======================
  DateTime _startOfWeek(DateTime d) {
    final start = DateTime.saturday; // 6
    final diff = (d.weekday - start + 7) % 7;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  String _weekKey(DateTime d) {
    final s = _startOfWeek(d);
    return '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
  }

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
        builder: (_) => Dialog(
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
                ],
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
      body:
          'أنت قريب من تحقيق هدفك الأسبوعي 🎖️\nاستمر… أنت على الطريق الصحيح 💚',
      seconds: 10,
    );
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

    if (weeklySeconds < goalSeconds) return;

    final thisKey = '$wk-$goalMinutes';
    final completedKey = (stats['weeklyGoalCompletedKey'] ?? '') as String;
    if (completedKey == thisKey) return;

    await statsRef.set({
      'weeklyGoalCompletedKey': thisKey,
      'weeklyGoalCompletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _showAutoDialogMessage(
      icon: Icons.emoji_events_rounded,
      title: 'مبروك! 🎉',
      body: 'تم تحقيق هدفك الأسبوعي 👏🏻\nاستمر على هذا التقدّم الجميل 💚',
      seconds: 10,
    );
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

      // أسبوع جديد -> صفّر الأسبوعي + مفاتيح الديالوق
      if (storedWeek != wk) {
        await statsRef.set({
          'weeklyKey': wk,
          'weeklyListenedSeconds': 0,
          'weeklyResetAt': FieldValue.serverTimestamp(),
          'weeklyGoalCompletedKey': '',
          'nearGoalNotifiedWeek': '',
          'nearGoalNotifiedGoalMinutes': 0,
        }, SetOptions(merge: true));
      }

      await statsRef.set({
        'weeklyKey': wk,
        'weeklyListenedSeconds': FieldValue.increment(_sessionListenedSeconds),
        'totalListenedSeconds': FieldValue.increment(_sessionListenedSeconds),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _maybeNotifyNearWeeklyGoal(wk: wk, statsRef: statsRef);
      await _maybeCelebrateWeeklyGoal(wk: wk, statsRef: statsRef);

      _sessionListenedSeconds = 0;
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

  // =======================
  // ✅ Bookmark toggle
  // =======================
  Future<void> _toggleBookmark() async {
    final ref = _myBookRef();
    if (ref == null) return;

    if (_isBookmarked) {
      await ref.set({
        'lastPartIndex': 0,
        'lastPositionMs': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isBookmarked = false);
      _showSnack(context, 'تم مسح العلامة', icon: Icons.check_circle);
    } else {
      await _autoSaveResume();
      if (!mounted) return;
      setState(() => _isBookmarked = true);
      _showSnack(context, 'تم حفظ العلامة', icon: Icons.check_circle);
    }
  }

  // =======================
  // ✅ Speed menu + seek
  // =======================
  Future<void> _showSpeedMenu(BuildContext btnContext) async {
    final RenderBox button = btnContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(btnContext).context.findRenderObject() as RenderBox;
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  Future<void> _seekBy(int seconds) async {
    final total = _totalMs();
    if (total <= 0) return;

    int target = _globalPosMs() + (seconds * 1000);
    if (target < 0) target = 0;
    if (target > total) target = total;

    await _seekGlobalMs(target);

    if (mounted) setState(() {});
  }

  // =======================
  // ✅ init
  // =======================
  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _isBookmarked = widget.initialPositionMs > 0;

    // ✅ نفس نظام الهدف: نراقب تشغيل/إيقاف
    _player.playingStream.listen((isPlaying) async {
      if (isPlaying) {
        if (!_listenWatch.isRunning) _listenWatch.start();

        _statsTimer ??= Timer.periodic(const Duration(seconds: 25), (_) async {
          await _flushListeningTick();
        });

        _resumeTimer ??= Timer.periodic(const Duration(seconds: 8), (_) async {
          await _autoSaveResume();
          await _saveBarProgress();
        });
      } else {
        _statsTimer?.cancel();
        _statsTimer = null;

        _resumeTimer?.cancel();
        _resumeTimer = null;

        await _autoSaveResume();
        await _saveBarProgress(force: true);

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
      final sources = widget.audioUrls
          .map((u) => AudioSource.uri(Uri.parse(u)))
          .toList();
      final playlist = ConcatenatingAudioSource(children: sources);

      await _player.setAudioSource(
        playlist,
        initialIndex: 0,
        initialPosition: Duration(milliseconds: widget.initialPositionMs),
      );

      await _player.setSpeed(_speed);

      // ✅ تحديث durations لو sequence تغيّرت
      _durations = _player.sequence?.map((s) => s.duration).toList() ?? [];
      _player.sequenceStream.listen((seq) {
        if (!mounted) return;
        setState(() {
          _durations = seq?.map((s) => s.duration).toList() ?? _durations;
        });
      });

      if (!mounted) return;
      setState(() => _loading = false);

      // ✅ الآن نحسب durations صح + نحمل progress القديم
      await _loadAllDurationsFromUrls();
      await _ensureEstimatedTotalSaved();
      await _loadContentProgress();

      // ✅ اكتب أول مرة حتى لو المستخدم دخل من مكان قديم
      await _saveBarProgress(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(context, 'تعذّر تشغيل الصوت', icon: Icons.error_outline);
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _resumeTimer = null;

    _statsTimer?.cancel();
    _statsTimer = null;

    _autoSaveResume();
    _saveBarProgress(force: true);

    if (_listenWatch.isRunning) {
      _listenWatch.stop();
      _sessionListenedSeconds += _listenWatch.elapsed.inSeconds;
      _listenWatch.reset();
    }
    if (_sessionListenedSeconds > 0) {
      _saveListeningStats();
    }

    _player.dispose();
    super.dispose();
  }

  // =======================
  // ✅ UI helper: mini bar % (اختياري لو تبينه مثل كتابك)
  // =======================
  Widget _playerMiniBar() {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snap) {
        final total = _totalMs();
        final localPos = snap.data ?? Duration.zero;
        final idx = _player.currentIndex ?? 0;

        if (total <= 0) return const SizedBox.shrink();

        final currentMs = (_prefixMsBefore(idx) + localPos.inMilliseconds)
            .clamp(0, total);

        final liveValue = (currentMs / total).clamp(0.0, 1.0);
        final shownValue = liveValue;
        final percent = (shownValue * 100).round();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              alignment: Alignment.center,
              children: [
                LinearProgressIndicator(
                  value: shownValue,
                  minHeight: 18,
                  backgroundColor: _pillGreen,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    _midPillGreen,
                  ),
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

                        // ✅ mini bar % (مثل كتابك العادي) - إذا ما تبينه احذفيه
                        _playerMiniBar(),
                        const SizedBox(height: 12),

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
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

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
                              final localPos = snap.data ?? Duration.zero;
                              final idx = _player.currentIndex ?? 0;

                              final currentMs =
                                  (_prefixMsBefore(idx) +
                                          localPos.inMilliseconds)
                                      .clamp(0, total > 0 ? total : 0);

                              /*if (currentMs > _maxReachedMs) {
                                _maxReachedMs = currentMs;
                              }*/

                              final liveValue = (total > 0)
                                  ? (currentMs / total)
                                  : 0.0;
                              final shownValue = _isDragging
                                  ? (_dragValue ?? liveValue)
                                  : liveValue;
                              final shownMs = (total * shownValue).round();

                              return Column(
                                children: [
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: _darkGreen,
                                      inactiveTrackColor: _pillGreen,
                                      thumbColor: _darkGreen,
                                      overlayColor: _darkGreen.withOpacity(
                                        0.15,
                                      ),
                                      trackHeight: 4,
                                    ),
                                    child: Slider(
                                      value: shownValue.clamp(0.0, 1.0),
                                      onChangeStart: total <= 0
                                          ? null
                                          : (v) {
                                              setState(() {
                                                _isDragging = true;
                                                _dragValue = v;
                                              });
                                            },
                                      onChanged: total <= 0
                                          ? null
                                          : (v) {
                                              setState(() {
                                                _isDragging = true;
                                                _dragValue = v;
                                              });
                                            },
                                      onChangeEnd: total <= 0
                                          ? null
                                          : (v) async {
                                              final target = (total * v)
                                                  .round();
                                              await _seekGlobalMs(target);

                                              if (!mounted) return;
                                              setState(() {
                                                _isDragging = false;
                                                _dragValue = null;
                                              });
                                            },
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _fmtMs(shownMs),
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        _fmtMs(total > 0 ? total : 0),
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
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
                                        await _saveBarProgress(force: true);
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
                                icon: const Icon(
                                  Icons.bookmark_add_rounded,
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
}
