import 'dart:async'; // Manage subscriptions if any
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'weekly_goal_page.dart';
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

Future<int> _getWeeklyGoalMinutesForMe() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();

  final data = doc.data() ?? {};
  final weeklyGoal = data['weeklyGoal'];
  if (weeklyGoal is! Map) return 0;

  final v = weeklyGoal['minutes'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

// ====== Weekly goal helpers ======
String? _goalMotivationText(double progress) {
  if (progress >= 1.0) {
    return ' تم تحقيق هدفك الأسبوعي بنجاح🎉';
  }
  if (progress >= 0.75) {
    return ' تقدّم جميل، اقتربت من تحقيق هدفك الأسبوعي✨';
  }
  return null;
}


Widget _weeklyGoalBar() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const SizedBox.shrink();

  final statsRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('stats')
      .doc('main');

  return StreamBuilder<DocumentSnapshot>(
    stream: statsRef.snapshots(),
    builder: (context, snap) {
      final data = snap.data?.data() as Map<String, dynamic>? ?? {};
      final weeklySec = (data['weeklyListenedSeconds'] as num?)?.toInt() ?? 0;

      return FutureBuilder<int>(
        future: _getWeeklyGoalMinutesForMe(),
        builder: (context, g) {
          final goalMinutes = g.data ?? 0;
          final minutes = (weeklySec / 60).floor();
          final progress = (goalMinutes <= 0)
              ? 0.0
              : (minutes / goalMinutes).clamp(0.0, 1.0);

          if (goalMinutes <= 0) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Text(
                'حدد هدفك الأسبوعي الآن',
                style: TextStyle(
                  color: _HomeColors.unselected.withOpacity(0.8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          final message = _goalMotivationText(progress);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 24,
                      backgroundColor: const Color(0xFFE6F0E0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFBFD6B5),
                      ),
                    ),
                    Text(
                      '$minutes / $goalMinutes د',
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0E3A2C),
                      ),
                    ),
                  ],
                ),
              ),

              // ===== رسالة التحفيز =====
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: progress >= 1.0
                        ? _HomeColors.confirm       // أخضر إنجاز
                        : _HomeColors.selected,     // أخضر داكن تحفيزي
                  ),
                ),
              ],
            ],
          );
        },
      );
    },
  );
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

  /// Quick controls
  double _topSpacingUnderHeader = 130; // Content spacing under header curves
  double coverW = 120; // Cover width
  double coverH = 140; // Cover height
  double coverGap = 12; // Gap between covers
  int visibleCount = 3; // How many covers are centered at once

  String _timeGreeting() {
  final hour = DateTime.now().hour;

  if (hour >= 0 && hour < 12) {
  // من 12 بالليل إلى 11:59 صباحاً
  return 'صباحك سعيد';
  } else {
  // من 12 الظهر إلى 11:59 مساءً
  return 'مساؤك سعيد';
  }
  }

  final _items = const [
    BottomNavItem(Icons.home, 'الرئيسية'),
    BottomNavItem(Icons.group, 'المجتمع'),
    BottomNavItem(Icons.menu_book, 'المكتبة'),
    BottomNavItem(Icons.person, 'الملف'),
  ];

  List<String> _selectedCategories = [];

  /// Categories list
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

  // Optional: keep a live subscription if needed
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  /// Scroll controller for the horizontal books list
  final ScrollController _booksScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDisplayName();

    // Live subscription to user profile
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
                  (data['name'] ??
                          data['fullName'] ??
                          data['displayName'] ??
                          '')
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
    _booksScrollController.dispose();
    super.dispose();
  }

  /// Live user name stream (used in greeting)
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

  // Search state
  String _searchQuery = '';

  /// Books stream with local filtering (search + category)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _booksStream() {
    final col = FirebaseFirestore.instance.collection('audiobooks');

    return col.orderBy('createdAt', descending: true).snapshots().map((snap) {
      var books = snap.docs;

      // Title search filter
      if (_searchQuery.isNotEmpty) {
        final queryLower = _searchQuery.toLowerCase();
        books = books.where((doc) {
          final data = doc.data();
          final title = (data['title'] ?? '').toString().toLowerCase();
          return title.contains(queryLower);
        }).toList();
      }

      // Category filter
      if (_selectedCategories.isNotEmpty) {
        books = books.where((doc) {
          final data = doc.data();
          final category = (data['category'] ?? '').toString();
          return _selectedCategories.contains(category);
        }).toList();
      }

      // Final filtered result
      return books;
    });
  }

  /// Scroll books horizontally when arrow is pressed
  void _scrollBooks({required bool forward}) {
    if (!_booksScrollController.hasClients) return;

    // Move by one "page" of visible covers
    final double delta = coverW * visibleCount + coverGap * (visibleCount - 1);

    // In RTL UI we still treat forward as increasing offset
    final double target =
        _booksScrollController.offset + (forward ? delta : -delta);

    _booksScrollController.animateTo(
      target.clamp(0.0, _booksScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Small overlay arrow button used on top of the books rail
  Widget _booksArrow({required bool isLeft}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        onPressed: () => _scrollBooks(forward: isLeft),
        icon: Icon(
          isLeft
              ? Icons.keyboard_double_arrow_left
              : Icons.keyboard_double_arrow_right,
          color: _HomeColors.unselected,
        ),
      ),
    );
  }

  /// Centered horizontal list of covers with left/right arrows on top
  Widget _centeredCoversRail() {
    final cardW = coverW;
    final cardH = coverH;
    final gap = coverGap;
    final count = visibleCount;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final visibleWidth = cardW * count + gap * (count - 1);
        final double sidePad = ((w - visibleWidth) / 2)
            .clamp(0.0, double.infinity)
            .toDouble();

        return SizedBox(
          height: cardH + 30.0,
          child: Stack(
            children: [
              // Books horizontal list
              StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
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
                    controller: _booksScrollController,
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
                                color: Colors.white, // No shadow here
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: cover.isNotEmpty
                                  ? Image.network(
                                      cover,
                                      fit: BoxFit
                                          .contain, // Show full cover without cropping
                                    )
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

              // Right arrow (start of list)
              Align(
                alignment: Alignment.centerRight,
                child: _booksArrow(isLeft: false),
              ),

              // Left arrow (more books)
              Align(
                alignment: Alignment.centerLeft,
                child: _booksArrow(isLeft: true),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Home content stack (background + list)
  Widget _homeContent() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/back.png', // Adjust path if needed
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // Foreground content
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            children: [
              // Spacing under header curves
              SizedBox(height: _topSpacingUnderHeader),

              // Greeting (live from Firestore)
              /*
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
                    offset: const Offset(0, -11),
                    child: Text(
                      '${_timeGreeting()} $name',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _HomeColors.selected,
                      ),
                    ),
                  );
                },
              ),
              */
              // New update
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

                  final hour = DateTime.now().hour;
                  final greeting = (hour < 12) ? "صباحك سعيد" : "مساؤك سعيد";

                  return Transform.translate(
                    offset: const Offset(0, -11),
                    child: Text(
                      '$greeting $name',
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

              // Search box
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

                    // Title search field
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

                    // Filter button
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

              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WeeklyGoalPage()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBEF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'هدفك الأسبوعي',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: _HomeColors.selected,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _weeklyGoalBar(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Section title (new)
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'جديد قبس',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),

              // Centered covers rail with overlay arrows
              _centeredCoversRail(),

              const SizedBox(height: 24),

              // Section title (recommendations placeholder)
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'اختيارات قبس لك',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),

              // Recommendations area placeholder (message only for now)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: const Text(
                  'لا توجد كتب مقترحة لك حاليًا.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
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

  // ==== Filter bottom sheet (half-screen) ====
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white, // White background
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return FractionallySizedBox(
              heightFactor: 0.6, // Half of the screen
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _HomeColors.unselected.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),

                    // Title + selected count
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

                    // Equal-sized category boxes
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 3.2,
                            ),
                        itemCount: _categories.length,
                        itemBuilder: (context, i) {
                          final cat = _categories[i];
                          final selected = _selectedCategories.contains(cat);
                          return _CategoryBox(
                            title: cat,
                            selected: selected,
                            onTap: () {
                              // Local update for sheet visuals
                              setStateSheet(() {
                                if (selected) {
                                  _selectedCategories.remove(cat);
                                } else {
                                  _selectedCategories.add(cat);
                                }
                              });
                              // Optional: if you want live filtering while toggling,
                              // uncomment the next line to propagate to parent instantly.
                              // if (mounted) setState(() {});
                            },
                          );
                        },
                      ),
                    ),

                    // Buttons with equal sizes
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              // Clear all selected categories in the sheet
                              setStateSheet(() => _selectedCategories.clear());
                              // IMPORTANT: Immediately refresh the parent to show all books
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('مسح الكل'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                48,
                              ), // Same height
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
                              setState(() {}); // Apply filters on page
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('تطبيق التصفية'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(
                                48,
                              ), // Same height
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

  // Same categories list if needed elsewhere
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

// ====== Equal-sized category box widget ======
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
