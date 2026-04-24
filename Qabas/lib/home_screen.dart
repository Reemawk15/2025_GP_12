import 'dart:async'; // Manage subscriptions if any
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'weekly_goal_page.dart';
import 'community_tab.dart';
import 'library_tab.dart';
import 'profile_tab.dart';
import 'book_details_page.dart';
import 'podcast_details_page.dart';

class _HomeColors {
  static const confirm = Color(0xFF6F8E63);
  static const navBg = Color(0xFFC9DABF);
  static const selected = Color(0xFF0E3A2C);
  static const unselected = Color(0xFF2F5145);
}

Future<int> _getWeeklyGoalMinutesForMe() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;

  final doc =
  await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

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
          final progress =
          (goalMinutes <= 0) ? 0.0 : (minutes / goalMinutes).clamp(0.0, 1.0);

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
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color:
                    progress >= 1.0 ? _HomeColors.confirm : _HomeColors.selected,
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
    final color =
    selected ? _HomeColors.selected : _HomeColors.unselected.withOpacity(0.55);
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

/* =========================================================
   Recommendations: model + fetch + widget
   ========================================================= */

class RecommendedItem {
  final String id;
  final String title;
  final String coverUrl;
  final String type; // "book" | "podcast"

  RecommendedItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.type,
  });

  factory RecommendedItem.fromMap(Map<String, dynamic> m) {
    final t = (m['type'] ?? 'book').toString().toLowerCase().trim();
    return RecommendedItem(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      coverUrl: (m['coverUrl'] ?? '').toString(),
      type: (t == 'podcast') ? 'podcast' : 'book',
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

  // Recommendations
  Future<List<RecommendedItem>> _recsFuture = Future.value(<RecommendedItem>[]);
  String? _recsUid;
  StreamSubscription<User?>? _authSub;

  // ✅ NEW: auto-refresh when user's library changes
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _libSub;
  Timer? _recsDebounce;

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

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  /// Scroll controller for the horizontal books list
  final ScrollController _booksScrollController = ScrollController();
  final ScrollController _podcastsScrollController = ScrollController();
  final ScrollController _recommendedScrollController = ScrollController();
  @override
  void initState() {
    super.initState();
    _loadDisplayName();

    // Initial load
    _recsFuture = _fetchRecommendations();
    _recsUid = FirebaseAuth.instance.currentUser?.uid;

    // ✅ NEW: listen to library changes for current user
    _listenToLibraryChanges();

    // Refresh recommendations when auth user changes (fixes logout/login losing results)
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      final uid = u?.uid;

      if (uid == null) {
        setState(() {
          _recsUid = null;
          _recsFuture = Future.value(<RecommendedItem>[]);
        });
        _libSub?.cancel();
        return;
      }

      if (uid != _recsUid) {
        setState(() {
          _recsUid = uid;
          _recsFuture = _fetchRecommendations();
        });
        _listenToLibraryChanges(); // ✅ rebind on user change
      }
    });

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
          name = (data['name'] ??
              data['fullName'] ??
              data['displayName'] ??
              '') as String?;
          if ((name ?? '').trim().isEmpty) name = null;
        }
        name ??= user.displayName;
        if (mounted) {
          setState(() => _displayName = name);
        }
      }, onError: (_) {});
    }
  }

  // ✅ NEW: listens for any change in latest library item, then refresh recs automatically
  void _listenToLibraryChanges() {
    final user = FirebaseAuth.instance.currentUser;

    _libSub?.cancel();
    _recsDebounce?.cancel();

    if (user == null) return;

    final libRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('library');

    _libSub = libRef
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((_) {
      _recsDebounce?.cancel();
      _recsDebounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _refreshRecs();
      });
    }, onError: (_) {});
  }

  Future<List<RecommendedItem>> _fetchRecommendations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = functions.httpsCallable('getPersonalizedRecommendations');


    final bookRes = await callable.call({'limit': 14, 'type': 'book'});
    final podRes  = await callable.call({'limit': 6,  'type': 'podcast'});

    List<RecommendedItem> parse(dynamic res) {
      final data = (res as Map?) ?? {};
      final items = (data['items'] as List?) ?? [];
      return items
          .map((e) => RecommendedItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((x) => x.id.isNotEmpty)
          .toList();
    }

    final books = parse(bookRes.data);
    final pods  = parse(podRes.data);
    print('books=${books.length} pods=${pods.length}');

    final seen = <String>{};
    final merged = <RecommendedItem>[];
    for (final it in [...books, ...pods]) {
      final key = '${it.type}:${it.id}';
      if (seen.add(key)) merged.add(it);
    }
    return merged;
  }
  void _refreshRecs() {
    setState(() {
      _recsFuture = _fetchRecommendations();
    });
  }

  Future<void> _loadDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String? name;
    try {
      final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        name = (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '')
        as String;
        if (name.trim().isEmpty) name = null;
      }
    } catch (_) {}
    name ??= user.displayName;
    if (mounted) setState(() => _displayName = name);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    _libSub?.cancel();
    _recsDebounce?.cancel();
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
      (data?['name'] ?? data?['fullName'] ?? data?['displayName']) as String?;
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

      if (_searchQuery.isNotEmpty) {
        final queryLower = _searchQuery.toLowerCase();
        books = books.where((doc) {
          final data = doc.data();
          final title = (data['title'] ?? '').toString().toLowerCase();
          return title.contains(queryLower);
        }).toList();
      }

      if (_selectedCategories.isNotEmpty) {
        books = books.where((doc) {
          final data = doc.data();
          final category = (data['category'] ?? '').toString();
          return _selectedCategories.contains(category);
        }).toList();
      }

      return books;
    });
  }

  /// Podcasts stream with local filtering (search + category)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _podcastsStream() {
    final col = FirebaseFirestore.instance.collection('podcasts');

    return col.orderBy('createdAt', descending: true).snapshots().map((snap) {
      var pods = snap.docs;

      if (_searchQuery.isNotEmpty) {
        final queryLower = _searchQuery.toLowerCase();
        pods = pods.where((doc) {
          final data = doc.data();
          final title = (data['title'] ?? '').toString().toLowerCase();
          return title.contains(queryLower);
        }).toList();
      }

      if (_selectedCategories.isNotEmpty) {
        pods = pods.where((doc) {
          final data = doc.data();
          final category = (data['category'] ?? '').toString();
          return _selectedCategories.contains(category);
        }).toList();
      }

      return pods;
    });
  }

  /// Scroll books horizontally when arrow is pressed
  void _scrollByController({
    required ScrollController controller,
    required bool forward,
  }) {
    if (!controller.hasClients) return;

    final double delta = coverW * visibleCount + coverGap * (visibleCount - 1);
    final double target = controller.offset + (forward ? delta : -delta);

    controller.animateTo(
      target.clamp(0.0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Small overlay arrow button used on top of the books rail
  Widget _railArrow({
    required bool isLeft,
    required ScrollController controller,
  }) {
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
        onPressed: () => _scrollByController(
          controller: controller,
          forward: isLeft,
        ),
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
        final double sidePad =
        ((w - visibleWidth) / 2).clamp(0.0, double.infinity).toDouble();

        return SizedBox(
          height: cardH + 30.0,
          child: Stack(
            children: [
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
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) => BookDetailsPage(bookId: d.id),
                            ),
                          )
                              .then((_) {
                            _refreshRecs();
                          });
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: cardW,
                              height: cardH,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: cover.isNotEmpty
                                  ? Image.network(cover, fit: BoxFit.contain)
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
              Align(
                alignment: Alignment.centerRight,
                child: _railArrow(
                  isLeft: false,
                  controller: _booksScrollController,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _railArrow(
                  isLeft: true,
                  controller: _booksScrollController,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _podcastsRail() {
    final double cardW = coverW;
    final double cardH = coverH;
    final double gap = coverGap;
    final int count = visibleCount;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final visibleWidth = cardW * count + gap * (count - 1);
        final double sidePad =
        ((w - visibleWidth) / 2).clamp(0.0, double.infinity).toDouble();

        return SizedBox(
          height: cardH + 30.0,
          child: Stack(
            children: [
              StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: _podcastsStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snap.hasData || snap.data!.isEmpty) {
                    return Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'لا توجد نتائج مطابقة'
                            : 'لا توجد بودكاستات مضافة',
                      ),
                    );
                  }

                  final docs = snap.data!;

                  return ListView.separated(
                    controller: _podcastsScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: sidePad),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => SizedBox(width: gap),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data();
                      final cover = (data['coverUrl'] ?? '').toString();
                      final title = (data['title'] ?? '').toString();

                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) => PodcastDetailsPage(podcastId: d.id),
                            ),
                          )
                              .then((_) {
                            _refreshRecs();
                          });
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: cardW,
                              height: cardH,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: cover.isNotEmpty
                                  ? Image.network(cover, fit: BoxFit.contain)
                                  : const Icon(
                                Icons.podcasts,
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
              Align(
                alignment: Alignment.centerRight,
                child: _railArrow(
                  isLeft: false,
                  controller: _podcastsScrollController,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _railArrow(
                  isLeft: true,
                  controller: _podcastsScrollController,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Recommendations UI rail
  Widget _recommendedRail() {
    final double cardW = coverW;
    final double cardH = coverH;
    final double gap = coverGap;
    final int count = visibleCount;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final visibleWidth = cardW * count + gap * (count - 1);
        final double sidePad =
        ((w - visibleWidth) / 2).clamp(0.0, double.infinity).toDouble();

        return FutureBuilder<List<RecommendedItem>>(
          future: _recsFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'تعذر جلب الاقتراحات حالياً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }

            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'لا توجد كتب مقترحة لك حاليًا.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }

            return SizedBox(
              height: cardH + 30.0,
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _recommendedScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: sidePad),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => SizedBox(width: gap),
                    itemBuilder: (context, i) {
                      final it = items[i];

                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                              builder: (_) => (it.type == 'podcast')
                                  ? PodcastDetailsPage(podcastId: it.id)
                                  : BookDetailsPage(bookId: it.id),
                            ),
                          )
                              .then((_) {
                            _refreshRecs();
                          });
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: cardW,
                              height: cardH,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.white,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: it.coverUrl.isNotEmpty
                                  ? Image.network(it.coverUrl, fit: BoxFit.contain)
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
                                it.title,
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
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _railArrow(
                      isLeft: false,
                      controller: _recommendedScrollController,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _railArrow(
                      isLeft: true,
                      controller: _recommendedScrollController,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  Widget _homeContent() {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    const navH = kBottomNavigationBarHeight;
    const navExtra = 24.0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/back.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      SizedBox(height: _topSpacingUnderHeader),
                      StreamBuilder<String?>(
                        stream: _userNameStream(),
                        builder: (context, snap) {
                          final liveName = snap.data;
                          final fallbackName = _displayName ??
                              FirebaseAuth.instance.currentUser?.displayName ??
                              'صديقي';
                          final name = (liveName == null || liveName.trim().isEmpty)
                              ? fallbackName
                              : liveName;

                          final hour = DateTime.now().hour;
                          final greeting =
                          (hour < 12) ? "صباحك سعيد" : "مساؤك سعيد";

                          return Transform.translate(
                            offset: const Offset(0, -11),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '$greeting $name',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _HomeColors.selected,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
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
                            const Icon(Icons.search,
                                color: _HomeColors.unselected),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                textAlign: TextAlign.right,
                                decoration: const InputDecoration(
                                  hintText: 'ابحث',
                                  border: InputBorder.none,
                                  isDense: true,
                                  hintStyle:
                                  TextStyle(color: _HomeColors.unselected),
                                ),
                                style:
                                const TextStyle(color: _HomeColors.selected),
                                onChanged: (value) {
                                  setState(() => _searchQuery = value.trim());
                                },
                              ),
                            ),
                            GestureDetector(
                              onTap: _openFilterSheet,
                              child: const Icon(Icons.tune,
                                  color: _HomeColors.unselected),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const WeeklyGoalPage()),
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
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      navH + navExtra + bottomSafe + 16,
                    ),
                    children: [
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'جديد قبس',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _centeredCoversRail(),
                      const SizedBox(height: 20),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'بودكاست قبس',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _podcastsRail(),
                      const SizedBox(height: 24),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'اختيارات قبس لك',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _recommendedRail(),
                    ],
                  ),
                ),
              ],
            ),
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
          onTap: (i) {
            setState(() => _index = i);
            //  optional extra: refresh when user comes back to home tab
            if (i == 0) _refreshRecs();
          },
        ),
      ),
    );
  }

  // ==== Filter bottom sheet (half-screen) ====
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return FractionallySizedBox(
              heightFactor: 0.6,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _HomeColors.unselected.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
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
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setStateSheet(() => _selectedCategories.clear());
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                            label: const Text('مسح الكل'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
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
                              setState(() {});
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('تطبيق التصفية'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
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