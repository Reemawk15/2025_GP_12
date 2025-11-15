import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'admin_book_manager.dart';
import 'admin_community_tab.dart';

class _HomeColors {
  static const confirm    = Color(0xFF6F8E63);
  static const navBg      = Color(0xFFC9DABF);
  static const selected   = Color(0xFF0E3A2C);
  static const unselected = Color(0xFF2F5145);
}

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Future<void> _confirmLogout(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تأكيد تسجيل الخروج',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _HomeColors.selected)),
              const SizedBox(height: 10),
              const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: _HomeColors.unselected)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _HomeColors.confirm,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                  },
                  child: const Text('تأكيد', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(fontSize: 16, color: _HomeColors.selected)),
                ),
              ),
            ],
          ),
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
          // Background image covering the full screen
          Positioned.fill(
            child: Image.asset(
              'assets/images/back.png',
              fit: BoxFit.cover,
            ),
          ),

          // Transparent scaffold layered above the background
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            extendBodyBehindAppBar: true,

            // This pushes the AppBar down a bit
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(190),
              child: Padding(
                padding: const EdgeInsets.only(top: 150),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: const Text(
                    'لوحة التحكم',
                    style: TextStyle(
                      color: _HomeColors.selected,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'تسجيل الخروج',
                      icon: const Icon(Icons.logout, color: _HomeColors.selected),
                      onPressed: () => _confirmLogout(context),
                    ),
                  ],
                ),
              ),
            ),

            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 50, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'مرحبًا بك في لوحة إدارة قَبَس، يمكنك إدارة الكتب والطلبات والإحصائيات من هنا.',
                      style: TextStyle(fontSize: 14, color: _HomeColors.unselected),
                    ),
                    const SizedBox(height: 16),

                    // Card 1: Audiobooks manager
                    _ActionCard(
                      title: 'إدارة الكتب الصوتية',
                      subtitle: 'يمكنك إثراء مكتبة قَبَس بإضافة الكتب الصوتية بالضغط على الزر أدناه.',
                      buttonText: 'أضف كتاب جديد',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminBookManagerScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Card 2: Club creation requests
                    _ActionCard(
                      title: 'إدارة الطلبات',
                      subtitle: 'يمكنك متابعة طلبات إنشاء أندية الكتب بالضغط على الزر أدناه.',
                      buttonText: 'عرض الطلبات',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminCommunityTab()),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Card 3: Statistics
                    _ActionCard(
                      title: 'احصائيات قَبَس',
                      subtitle: 'يمكنك متابعة نشاط قَبَس بالضغط على الزر أدناه.',
                      buttonText: 'عرض الإحصائيات',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminStatsPage()),
                        );
                      },
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
}

// Reusable clickable card widget with a button
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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: _HomeColors.navBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: _HomeColors.selected)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: _HomeColors.unselected)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _HomeColors.confirm,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  elevation: 0,
                ),
                onPressed: onPressed,
                child: Text(buttonText, style: const TextStyle(fontSize: 14, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Statistics page template
class AdminStatsPage extends StatelessWidget {
  const AdminStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,

            // Pushes the AppBar content down slightly
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(190),
              child: Padding(
                padding: const EdgeInsets.only(top: 150),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: const Text(
                    'احصائيات قَبَس',
                    style: TextStyle(
                      color: _HomeColors.selected,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  iconTheme: const IconThemeData(color: _HomeColors.selected),
                ),
              ),
            ),
            body: const Center(
              child: Text(
                'هنا ستُعرض الإحصائيات',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: _HomeColors.selected),
              ),
            ),
          ),
        ],
      ),
    );
  }
}