// community_tab.dart
import 'package:flutter/material.dart';
import 'friends_page.dart';
import 'clubs_page.dart';

// نفس ألوان الهوية المستخدمة في مكتبتك
const Color _darkGreen  = Color(0xFF0E3A2C);
const Color _midGreen   = Color(0xFF2F5145);
const Color _lightGreen = Color(0xFFC9DABF);
const _confirmColor     = Color(0xFF6F8E63);

class CommunityTab extends StatelessWidget {
  const CommunityTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية
          Positioned.fill(
            child: Image.asset(
              'assets/images/community.png', // ← عدّليه لو الاسم مختلف
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 8, // نفس شريط رفيع بدون عنوان
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionCard(
                        title: 'الأصدقاء',
                        subtitle: 'يمكنك استعراض قائمة أصدقائك أو إضافة أصدقاء جدد بالنقر على الزر أدناه',
                        buttonText: 'الأصدقاء',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const FriendsPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _ActionCard(
                        title: 'الأندية',
                        subtitle: 'يمكنك الإنضمام إلى نوادي الكتب أو إنشاء نادٍ جديد بالنقر على الزر أدناه',
                        buttonText: 'الأندية',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ClubsPage()),
                          );
                        },
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
  }
}

// ===== كرت الإجراء (نفس شكل مكتبي/إضافة كتب تمامًا) =====
class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160, // نفس الارتفاع
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.88), // نفس اللون والشفافية
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _darkGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _confirmColor, // نفس لون الزر
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                elevation: 0,
              ),
              child: Text(
                buttonText,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}