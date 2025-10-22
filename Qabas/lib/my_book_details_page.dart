import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;

class MyBookDetailsPage extends StatelessWidget {
  final String bookId; // id المستند داخل users/{uid}/mybooks
  const MyBookDetailsPage({super.key, required this.bookId});

  static const _primary   = Color(0xFF0E3A2C);
  static const _accent    = Color(0xFF6F8E63);
  static const _pillGreen = Color(0xFFE6F0E0);

  // ✅ SnackBar موحّد بنفس الستايل، وبألوان الملف فقط
  void _showSnack(BuildContext context, String message, {IconData icon = Icons.check_circle}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _accent,                       // خلفية خضراء من ألوان الملف
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Color(0xFFE7C4DA)),       // وردي فاتح ثابت
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

  // 1) تحويل الروابط إلى https صالح
  Future<String?> _normalizeUrl(String raw) async {
    String url = (raw).trim();
    if (url.isEmpty) return null;

    // gs://bucket/path/file.pdf  -> https download URL
    if (url.startsWith('gs://')) {
      try {
        final ref = storage.FirebaseStorage.instance.refFromURL(url);
        final https = await ref.getDownloadURL();
        return https;
      } catch (_) {
        return null;
      }
    }

    // روابط درايف — نحولها إلى direct download
    if (url.contains('drive.google.com')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        String? id;
        if (uri.pathSegments.length >= 3 && uri.pathSegments[0] == 'file' && uri.pathSegments[1] == 'd') {
          id = uri.pathSegments[2];
        } else if (uri.queryParameters['id'] != null) {
          id = uri.queryParameters['id'];
        }
        if (id != null && id.isNotEmpty) {
          return 'https://drive.google.com/uc?export=download&id=$id';
        }
      }
    }

    // إذا ما فيه scheme نضيف https://
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    return url;
  }

  Future<void> _openPdf(BuildContext context, String rawUrl) async {
    final normalized = await _normalizeUrl(rawUrl);
    if (normalized == null) {
      if (context.mounted) {
        _showSnack(context, 'الرابط غير صالح أو الملف غير متاح', icon: Icons.error_outline);
      }
      return;
    }

    final uri = Uri.parse(normalized);

    try {
      final okExternal = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!okExternal) {
        final okInApp = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (!okInApp && context.mounted) {
          _showSnack(context, 'تعذّر فتح ملف الـ PDF', icon: Icons.error_outline);
        }
      }
    } catch (_) {
      try {
        final okInApp = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (!okInApp && context.mounted) {
          _showSnack(context, 'تعذّر فتح ملف الـ PDF', icon: Icons.error_outline);
        }
      } catch (e) {
        if (context.mounted) {
          _showSnack(context, 'الرابط غير صالح أو لا يمكن فتحه', icon: Icons.error_outline);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية الخاصة
          Positioned.fill(
            child: Image.asset('assets/images/back_private2.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leadingWidth: 56,
              toolbarHeight: 120,
              leading: SafeArea(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, top: 64),
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 22),
                  ),
                ),
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
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_primary), // لون التحميل من ألوان الملف
                    ),
                  );
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return const Center(child: Text('تعذّر تحميل تفاصيل الكتاب'));
                }

                final data = (snap.data!.data() as Map<String, dynamic>? ?? {});
                final title   = (data['title'] ?? '') as String;
                final cover   = (data['coverUrl'] ?? '') as String;
                final pdfUrl  = (data['pdfUrl'] ?? '') as String;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 170, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // الغلاف (اختياري)
                      Center(
                        child: Container(
                          width: 200,
                          height: 270,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))
                            ],
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: cover.isNotEmpty
                              ? Image.network(cover, fit: BoxFit.cover)
                              : const Icon(Icons.menu_book, size: 80, color: _primary),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // العنوان
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
                      const SizedBox(height: 18),

                      // بطاقة "ملف الكتاب"
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _pillGreen,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.picture_as_pdf, color: _primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: pdfUrl.trim().isEmpty
                                  ? const Text('لا يوجد ملف PDF', style: TextStyle(fontWeight: FontWeight.w600))
                                  : InkWell(
                                onTap: () => _openPdf(context, pdfUrl),
                                child: const Text(
                                  'ملف الكتاب',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _accent,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // زر بدء الاستماع (غير مفعل)
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('بدء الاستماع'),
                        ),
                      ),
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