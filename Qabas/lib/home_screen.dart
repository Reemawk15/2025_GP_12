import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ✅ الاستيراد مباشرة من lib (بدون مجلد screens)
import 'community_tab.dart';
import 'library_tab.dart';
import 'profile_tab.dart';

class _HomeColors {
  static const confirm    = Color(0xFF6F8E63);
  static const navBg      = Color(0xFFC9DABF);
  static const selected   = Color(0xFF0E3A2C);
  static const unselected = Color(0xFF2F5145);
}

class BottomNavItem {
  final IconData icon;
  final String label;
  const BottomNavItem(this.icon, this.label);
}

class _NavButton extends StatelessWidget {
  final BottomNavItem item;
  final bool selected;
  final VoidCallback onPressed;
  const _NavButton({required this.item, required this.selected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _HomeColors.selected : _HomeColors.unselected.withOpacity(0.55);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 28, child: Icon(item.icon, size: 24, color: color)),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: selected ? 10 : 0,
              width: selected ? 26 : 0,
              decoration: BoxDecoration(
                color: _HomeColors.selected,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QabasBottomNav extends StatelessWidget {
  final List<BottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const QabasBottomNav({super.key, required this.items, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: _HomeColors.navBg,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 10))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(items.length, (i) {
              final isSelected = i == currentIndex;
              return _NavButton(item: items[i], selected: isSelected, onPressed: () => onTap(i));
            }),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final _items = const [
    BottomNavItem(Icons.home, 'الرئيسية'),
    BottomNavItem(Icons.group, 'المجتمع'),
    BottomNavItem(Icons.menu_book, 'المكتبة'),
    BottomNavItem(Icons.person, 'الملف'),
  ];

  Widget _homeContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/qabas_logo.png', height: 160, fit: BoxFit.contain),
          const SizedBox(height: 16),
          const Text('تم تسجيل الدخول بنجاح ✨'),
        ],
      ),
    );
  }

  final _community = const CommunityTab();
  final _library   = const LibraryTab();
  final _profile   = const ProfileTab();

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _homeContent(),
      _community,
      _library,
      _profile,
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white, // ⬅️ لون خلفية الصفحة بالكامل
        extendBody: true,              // ← مهم عشان البار يطفو فوق الخلفية



        body: IndexedStack(index: _index, children: pages),

        bottomNavigationBar: QabasBottomNav(
          items: _items,
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}