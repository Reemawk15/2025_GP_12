import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';

class MyBookDetailsPage extends StatelessWidget {
  final String bookId; // id المستند داخل users/{uid}/mybooks
  const MyBookDetailsPage({super.key, required this.bookId});

  static const _primary   = Color(0xFF0E3A2C);
  static const _accent    = Color(0xFF6F8E63);
  static const _pillGreen = Color(0xFFE6F0E0);


  Future<void> _openPdf(BuildContext context, String url) async {
    if (await canLaunchUrlString(url)) {
      final ok = await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح ملف الـ PDF')),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرابط غير صالح أو لا يمكن فتحه')),
        );
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
                  return const Center(child: CircularProgressIndicator());
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

// بطاقة بسيطة: "ملف الكتاب"
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
                              child: pdfUrl.isEmpty
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

// زر بدء الاستماع (شكلي فقط حالياً)
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade400, // لون باهت ليدل أنه غير مفعل
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: null, // غير قابل للنقر حالياً
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