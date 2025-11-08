import 'dart:async'; // لإدارة الاشتراكات إن وُجدت
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'community_tab.dart';
import 'library_tab.dart';
import 'profile_tab.dart';
import 'book_details_page.dart';

class _HomeColors {
  static const confirm = Color(0xFF6F8E63);
  static const navBg = Color(0xFFC9DABF);
  static const selected = Color(0xFF0E3A2C);
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
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? _HomeColors.selected
        : _HomeColors.unselected.withOpacity(0.55);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 28,
              child: Icon(item.icon, size: 24, color: color),
            ),
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
  const QabasBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

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
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(items.length, (i) {
              final isSelected = i == currentIndex;
              return _NavButton(
                item: items[i],
                selected: isSelected,
                onPressed: () => onTap(i),
              );
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
  String? _displayName;

  /// تحكّم سريع
  double _topSpacingUnderHeader = 130; // مسافة نزول المحتوى تحت التعرّجات
  double coverW = 120; // عرض الغلاف
  double coverH = 140; // ارتفاع الغلاف
  double coverGap = 12; // المسافة بين الأغلفة
  int visibleCount = 3; // كم غلاف يظهر بالنص معًا

  final _items = const [
    BottomNavItem(Icons.home, 'الرئيسية'),
    BottomNavItem(Icons.group, 'المجتمع'),
    BottomNavItem(Icons.menu_book, 'المكتبة'),
    BottomNavItem(Icons.person, 'الملف'),
  ];

  List<String> _selectedCategories = [];

  /// ✅ الكاتقورير الجديدة
  final List<String> _categories = const [
    'الأدب والشعر',
    'التاريخ والجغرافيا',
    'التقنية والكمبيوتر',
    'القصة والرواية',
    'الكتب الإسلامية والدينية',
    'كتب الأطفال',
    'معلومات عامة',
    'تطوير الذات',
  ];

  // (اختياري) كان عندنا اشتراك؛ نحتفظ به إن وُجد
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  @override
  void initState() {
    super.initState();
    _loadDisplayName();

    // اشتراك حي
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _profileSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((doc) {
        String? name;
        if (doc.exists) {
          final data = doc.data() ?? {};
          name =
          (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '')
          as String?;
          if ((name ?? '').trim().isEmpty) name = null;
        }
        name ??= user.displayName;
        if (mounted) {
          setState(() => _displayName = name);
        }
      }, onError: (_) {});
    }
  }

  Future<void> _loadDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String? name;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        name =
        (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '')
        as String;
        if (name.trim().isEmpty) name = null;
      }
    } catch (_) {}
    name ??= user.displayName;
    setState(() => _displayName = name);
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  // ✅ ستريم اسم المستخدم مباشرة من Firestore (يُستخدم في الترحيب)
  Stream<String?> _userNameStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(null);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((doc) {
      final data = doc.data();
      String? name =
      (data?['name'] ?? data?['fullName'] ?? data?['displayName'])
      as String?;
      if ((name ?? '').trim().isEmpty) name = null;
      return name;
    });
  }

  // part for Search
  String _searchQuery = '';

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _booksStream() {
    final col = FirebaseFirestore.instance.collection('audiobooks');

    return col.orderBy('createdAt', descending: true).snapshots().map((snap) {
      var books = snap.docs;

      // 🔍 فلترة البحث بالاسم
      if (_searchQuery.isNotEmpty) {
        final queryLower = _searchQuery.toLowerCase();
        books = books.where((doc) {
          final data = doc.data();
          final title = (data['title'] ?? '').toString().toLowerCase();
          return title.contains(queryLower);
        }).toList();
      }

      // 🎧 فلترة الفئة (category)
      if (_selectedCategories.isNotEmpty) {
        books = books.where((doc) {
          final data = doc.data();
          final category = (data['category'] ?? '').toString();
          return _selectedCategories.contains(category);
        }).toList();
      }

      // ✅ ترجع النتيجة النهائية بعد تطبيق البحث والفئة معًا
      return books;
    });
  }

  // سطر الأغلفة بالمنتصف
  Widget _centeredCoversRail() {
    final cardW = coverW;
    final cardH = coverH;
    final gap = coverGap;
    final count = visibleCount;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final visibleWidth = cardW * count + gap * (count - 1);
        final double sidePad =
        ((w - visibleWidth) / 2).clamp(0.0, double.infinity).toDouble();

        return SizedBox(
          height: cardH + 30.0, // double
          child: StreamBuilder<
              List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: _booksStream(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData || snap.data!.isEmpty) {
                return const Center(child: Text('لا توجد نتائج مطابقة'));
              }
              final docs = snap.data!;

              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: sidePad),
                itemCount: docs.length,
                separatorBuilder: (_, __) => SizedBox(width: gap),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>? ?? {};
                  final cover = (data['coverUrl'] ?? '') as String;
                  final title = (data['title'] ?? '') as String;

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookDetailsPage(bookId: d.id),
                        ),
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: cardW,
                          height: cardH,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 12,
                                offset: Offset(0, 6),
                              ),
                            ],
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: cover.isNotEmpty
                              ? Image.network(cover, fit: BoxFit.cover)
                              : const Icon(
                            Icons.menu_book,
                            size: 48,
                            color: _HomeColors.unselected,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: cardW,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _homeContent() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // خلفيتك
          Positioned.fill(
            child: Image.asset(
              'assets/images/back.png', // عدّل المسار إذا لزم
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // المحتوى فوق الخلفية
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            children: [
              // مسافة تحت التعرّجات
              SizedBox(height: _topSpacingUnderHeader),

              // ✅ الترحيب — يُحدَّث لحظيًا من Firestore
              StreamBuilder<String?>(
                stream: _userNameStream(),
                builder: (context, snap) {
                  final liveName = snap.data;
                  final fallbackName =
                      _displayName ??
                          FirebaseAuth.instance.currentUser?.displayName ??
                          'صديقي';
                  final name = (liveName == null || liveName.trim().isEmpty)
                      ? fallbackName
                      : liveName;

                  return Transform.translate(
                    offset: const Offset(0, -11), // بالسالب = يرفع النص للأعلى
                    child: Text(
                      'مساؤك سعيد $name',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _HomeColors.selected,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 26),

              // ✅ مربع البحث المعدل
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: _HomeColors.unselected),
                    const SizedBox(width: 8),

                    // TextField للبحث
                    Expanded(
                      child: TextField(
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن كتاب بالاسم',
                          border: InputBorder.none,
                          isDense: true,
                          hintStyle: TextStyle(color: _HomeColors.unselected),
                        ),
                        style: const TextStyle(color: _HomeColors.selected),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value.trim();
                          });
                        },
                      ),
                    ),

                    GestureDetector(
                      onTap: _openFilterSheet,
                      child: const Icon(
                        Icons.tune,
                        color: _HomeColors.unselected,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // البانر
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBEF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: const [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الرياض تقرأ، وقبس يروي الحكاية',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'استمع إلى أبرز إصدارات معرض الرياض الدولي للكتاب',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.headset_mic,
                      color: _HomeColors.selected,
                      size: 32,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // العنوان يمين
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'جديد قبس',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),

              // سطر الأغلفة (بالوسط)
              _centeredCoversRail(),

              const SizedBox(height: 24),

              // عنوان يمين
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'اختيارات قبس لك',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),

              // مكان كروت التوصيات…
            ],
          ),
        ],
      ),
    );
  }

  final _community = const CommunityTab();
  final _library = const LibraryTab();
  final _profile = const ProfileTab();

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[_homeContent(), _community, _library, _profile];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        extendBody: true,
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: QabasBottomNav(
          items: _items,
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      ),
    );
  }

  // ==== ورقة الفلتر (نصف الشاشة + خلفية بيضاء + بوكسات متساوية + أزرار متماثلة) ====
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, // خلفية بيضاء
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return FractionallySizedBox(
              heightFactor: 0.6, // 👈 نصف الشاشة
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  children: [
                    // مقبض سحب صغير
                    Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _HomeColors.unselected.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),

                    // العنوان + عدّاد المختار
                    const Text(
                      'اختر عالمك القرائي المفضل',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _HomeColors.selected,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedCategories.isEmpty
                          ? 'لم يتم اختيار أي فئة بعد'
                          : 'تم اختيار ${_selectedCategories.length} فئات',
                      style: TextStyle(
                        fontSize: 12,
                        color: _HomeColors.unselected.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // شبكة بوكسات متساوية
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, // عمودان
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 3.2, // نسبة العرض للارتفاع
                        ),
                        itemCount: _categories.length,
                        itemBuilder: (context, i) {
                          final cat = _categories[i];
                          final selected = _selectedCategories.contains(cat);
                          return _CategoryBox(
                            title: cat,
                            selected: selected,
                            onTap: () {
                              setStateSheet(() {
                                if (selected) {
                                  _selectedCategories.remove(cat);
                                } else {
                                  _selectedCategories.add(cat);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),

                    // أزرار بنفس الحجم بالضبط
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setStateSheet(() => _selectedCategories.clear());
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('مسح الكل'),
                            style: OutlinedButton.styleFrom(
                              minimumSize:
                              const Size.fromHeight(48), // نفس الارتفاع
                              foregroundColor: _HomeColors.selected,
                              side: BorderSide(
                                color: _HomeColors.selected.withOpacity(0.6),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() {}); // لتحديث الفلترة في الصفحة
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('تطبيق التصفية'),
                            style: ElevatedButton.styleFrom(
                              minimumSize:
                              const Size.fromHeight(48), // نفس الارتفاع
                              backgroundColor: _HomeColors.selected,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // نفس قائمة الكاتقورير لو احتجتها في مكان آخر
  final List<String> _categoriess = [
    'الأدب والشعر',
    'التاريخ والجغرافيا',
    'التقنية والكمبيوتر',
    'القصة والرواية',
    'الكتب الإسلامية والدينية',
    'كتب الأطفال',
    'معلومات عامة',
    'تطوير الذات',
  ];
}

// ====== ويدجت البوكس المتساوي ======
class _CategoryBox extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryBox({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _HomeColors.selected : const Color(0xFFDDE9CD),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: selected ? Colors.white : _HomeColors.selected,
            ),
          ),
        ),
      ),
    );
  }
}