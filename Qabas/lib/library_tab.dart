import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'book_details_page.dart';
import 'my_book_details_page.dart';

const Color _darkGreen = Color(0xFF0E3A2C);
const Color _midGreen = Color(0xFF2F5145);
const Color _fillGreen = Color(0xFFC9DABF);
const Color _confirm = Color(0xFF6F8E63);

/// Main tab that shows private shelves + "My Books"
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  void _back(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    // If inside bottom navigation root, nothing happensy
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 4,
        child: Stack(
          children: [
            // Global background for all shelves (all tabs)
            Positioned.fill(
              child: Image.asset(
                'assets/images/backttt.png',
                fit: BoxFit.cover,
              ),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.endFloat,
              floatingActionButton: user == null
                  ? null
                  : Padding(
                      // Adjust this value to move the FAB up/down
                      padding: const EdgeInsets.only(bottom: 100),
                      child: FloatingActionButton(
                        mini: true, // Smaller FAB
                        backgroundColor: _confirm,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddMyBookPage(),
                            ),
                          );
                        },
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),
              body: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 42),

                    // Tab bar to switch between shelves
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      //padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.9),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const TabBar(
                          indicator: UnderlineTabIndicator(
                            borderSide: BorderSide(width: 2),
                          ),
                          dividerColor: Colors.transparent,
                          overlayColor: MaterialStatePropertyAll(
                            Colors.transparent,
                          ),
                          labelColor: _midGreen,
                          unselectedLabelColor: Colors.black54,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),

                          // 👈 هذا السطر المهم
                          indicatorPadding: const EdgeInsets.only(bottom: 6),

                          labelPadding: const EdgeInsets.only(
                            left: 1,
                            right: 1,
                            bottom: 10, // 👈 هذا يرفع الكلمات
                          ),

                          tabs: [
                            Tab(text: 'أرغب بالاستماع لها'),
                            Tab(text: 'استمع لها الآن'),
                            Tab(text: 'استمعت لها'),
                            Tab(text: 'كتبي'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Expanded(
                      child: user == null
                          ? const Center(
                              child: Text('الرجاء تسجيل الدخول لعرض مكتبتك'),
                            )
                          : TabBarView(
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _LibraryShelf(status: 'want', uid: user.uid),
                                _LibraryShelf(
                                  status: 'listen_now',
                                  uid: user.uid,
                                ),
                                _LibraryShelf(
                                  status: 'listened',
                                  uid: user.uid,
                                ),
                                _MyBooksShelfTab(uid: user.uid),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Model for a book inside users/{uid}/library
class Book {
  final String id;
  final String title;
  final ImageProvider? cover;
  final String status;
  final int listenedSeconds;
  final int estimatedTotalSeconds;
  final bool isCompleted;
  final int contentMs;
  final int totalMs;

  const Book({
    required this.id,
    required this.title,
    this.cover,
    required this.status,
    this.listenedSeconds = 0,
    this.estimatedTotalSeconds = 0,
    this.isCompleted = false,
    this.contentMs = 0,
    this.totalMs = 0,
  });
}

/// One shelf category: want / listen_now / listened
class _LibraryShelf extends StatefulWidget {
  final String status;
  final String uid;
  const _LibraryShelf({required this.status, required this.uid});

  @override
  State<_LibraryShelf> createState() => _LibraryShelfState();
}

class _LibraryShelfState extends State<_LibraryShelf> {
  List<Book> _lastNonEmpty = const [];
  final Set<String> _locallyHidden = <String>{};

  void _onMovedLocally(String docId) {
    setState(() {
      _locallyHidden.add(docId);
      _lastNonEmpty = _lastNonEmpty.where((b) => b.id != docId).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('library')
        .where('status', isEqualTo: widget.status)
        .orderBy('addedAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          // While waiting, show cache if available
          if (_lastNonEmpty.isNotEmpty) {
            return _ShelfView(
              books: _lastNonEmpty,
              uid: widget.uid,
              onMoved: _onMovedLocally,
            );
          }
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          // On error, fallback to last non-empty page if exists
          if (_lastNonEmpty.isNotEmpty) {
            return _ShelfView(
              books: _lastNonEmpty,
              uid: widget.uid,
              onMoved: _onMovedLocally,
            );
          }
          return const Center(child: Text('لا توجد كتب في هذه القائمة بعد'));
        }

        final docs = snap.data?.docs ?? [];
        final all = docs.map((d) {
          final m = d.data() as Map<String, dynamic>? ?? {};

          final title = (m['title'] ?? '') as String;
          final cover = (m['coverUrl'] ?? '') as String;
          final status = (m['status'] ?? 'want') as String;
          final listenedSeconds = (m['listenedSeconds'] as num?)?.toInt() ?? 0;
          final estimatedTotalSeconds =
              (m['estimatedTotalSeconds'] as num?)?.toInt() ?? 0;
          final isCompleted = (m['isCompleted'] as bool?) ?? false;
          final contentMs = (m['contentMs'] as num?)?.toInt() ?? 0;
          final totalMs = (m['totalMs'] as num?)?.toInt() ?? 0;

          return Book(
            id: d.id,
            title: title.isEmpty ? 'كتاب' : title,
            cover: cover.isNotEmpty ? NetworkImage(cover) : null,
            status: status,
            listenedSeconds: listenedSeconds,
            estimatedTotalSeconds: estimatedTotalSeconds,
            isCompleted: isCompleted,
            contentMs: contentMs,
            totalMs: totalMs,
          );
        }).toList();

        final current = all
            .where((b) => !_locallyHidden.contains(b.id))
            .toList();

        if (current.isNotEmpty) {
          _lastNonEmpty = current;
          return _ShelfView(
            books: current,
            uid: widget.uid,
            onMoved: _onMovedLocally,
          );
        }

        if (_lastNonEmpty.isNotEmpty) {
          return _ShelfView(
            books: _lastNonEmpty,
            uid: widget.uid,
            onMoved: _onMovedLocally,
          );
        }

        return const Center(child: Text('لا توجد كتب في هذه القائمة بعد'));
      },
    );
  }
}

/// Physical rectangle of a shelf relative to background
class ShelfRect {
  final double leftFrac, rightFrac, topFrac, heightFrac;
  const ShelfRect({
    required this.leftFrac,
    required this.rightFrac,
    required this.topFrac,
    required this.heightFrac,
  });
}

/// Grid of books on the decorative shelves (for library statuses)
class _ShelfView extends StatefulWidget {
  final List<Book> books;
  final String uid;
  final void Function(String docId) onMoved;
  const _ShelfView({
    required this.books,
    required this.uid,
    required this.onMoved,
  });

  @override
  State<_ShelfView> createState() => _ShelfViewState();
}

class _ShelfViewState extends State<_ShelfView> {
  // Physical positions of the 4 shelves on the background image
  static const List<ShelfRect> _shelfRects = [
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.09, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.29, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.50, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.70, heightFrac: 0.11),
  ];

  static const int _perShelf = 4;
  static const int _shelvesPerPage = 4;
  static const int _booksPerPage = _perShelf * _shelvesPerPage;
  static const double _spacing = 1;
  static const double _bookAspect = .25;
  static const double _bookStretch = 1.2;

  final PageController _pageController = PageController();
  late List<List<Book>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = _paginate(widget.books, _booksPerPage);
  }

  @override
  void didUpdateWidget(covariant _ShelfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books.length != widget.books.length) {
      _pages = _paginate(widget.books, _booksPerPage);
    }
  }

  List<List<Book>> _paginate(List<Book> list, int size) {
    final pages = <List<Book>>[];
    for (var i = 0; i < list.length; i += size) {
      pages.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    if (pages.isEmpty) pages.add(const []);
    return pages;
  }

  List<List<Book>> _chunk(List<Book> list, int size) {
    final chunks = <List<Book>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    return chunks;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          itemCount: pages.length,
          itemBuilder: (context, pageIndex) {
            final pageBooks = pages[pageIndex];
            final groups = _chunk(pageBooks, _perShelf);

            return LayoutBuilder(
              builder: (context, c) {
                final W = c.maxWidth;
                final H = c.maxHeight;

                return Stack(
                  children: List.generate(_shelfRects.length, (i) {
                    final rect = _shelfRects[i];
                    final shelfBooks = i < groups.length
                        ? groups[i]
                        : const <Book>[];

                    final left = rect.leftFrac * W;
                    final right = rect.rightFrac * W;
                    final top = rect.topFrac * H;
                    final height = rect.heightFrac * H;
                    final width = W - left - right;

                    final slots = _perShelf;
                    final totalSpacing = _spacing * (slots - 1);
                    final bookWidth = ((width - totalSpacing) / slots * 0.80)
                        .clamp(40.0, 140.0);
                    final bookHeight = (bookWidth / _bookAspect * _bookStretch);

                    return Positioned(
                      left: left,
                      right: right,
                      top: top,
                      height: height,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(slots, (slot) {
                            final book = slot < shelfBooks.length
                                ? shelfBooks[slot]
                                : null;
                            return SizedBox(
                              width: bookWidth,
                              height: bookHeight,
                              child: book == null
                                  ? const SizedBox.shrink()
                                  : Align(
                                      alignment: Alignment.topCenter,
                                      child: _BookCard(
                                        book: book,
                                        uid: widget.uid,
                                        onMoved: widget.onMoved,
                                      ),
                                    ),
                            );
                          }),
                        ),
                      ),
                    );
                  }),
                );
              },
            );
          },
        ),

        // Page indicator for shelves
        Positioned(
          bottom: 25,
          right: 0,
          left: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                final current = _pageController.hasClients
                    ? (_pageController.page ?? 0).round()
                    : 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(pages.length, (i) {
                    final active = i == current;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFE26AA2)
                            : Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// retuer the weeklyGoal from database
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

Future<int> _getWeeklyListenedSecondsForMe() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('stats')
      .doc('main')
      .get();

  final data = doc.data() ?? {};
  final v = data['weeklyListenedSeconds'] ?? data['weeklyListenedSeconds'];

  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
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
      final weeklySec =
          (data['weeklyListenedSeconds'] as num?)?.toInt() ??
          (data['weeklyListenedSeconds'] as num?)?.toInt() ??
          0;

      return FutureBuilder<int>(
        future: _getWeeklyGoalMinutesForMe(),
        builder: (context, g) {
          final goalMinutes = g.data ?? 60;
          final minutes = (weeklySec / 60).floor();
          final progress = (goalMinutes <= 0)
              ? 0.0
              : (minutes / goalMinutes).clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: const Color(0xFFDCE7D6), // أخضر فاتح
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF88A07D), // أخضر أغمق (التعبئة)
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // num under bar
                Text(
                  '$minutes / $goalMinutes د',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E3A2C),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Single book card used inside library shelves
class _BookCard extends StatelessWidget {
  final Book book;
  final String uid;
  final void Function(String docId) onMoved;
  const _BookCard({
    required this.book,
    required this.uid,
    required this.onMoved,
  });

  static const Map<String, String> _arabicStatus = {
    'want': 'أرغب بالاستماع لها',
    'listen_now': 'استمع لها الآن',
    'listened': 'استمعت لها',
  };

  void _showSnack(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
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

  Future<void> _removeFromList(BuildContext context) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('library')
        .doc(book.id);

    try {
      await ref.set({
        'inLibrary': false, // ✅ نخفيه فقط
        'removedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      onMoved(book.id);
      _showSnack(context, 'تمت الحذف من قائمتك', icon: Icons.check_circle);
    } catch (e) {
      _showSnack(
        context,
        'تعذّر الحذف. حاول مجددًا',
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _moveToStatus(
    BuildContext sheetContext,
    String newStatus,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('library')
        .doc(book.id);
    try {
      await ref.set({
        'inLibrary': true,
        'status': newStatus,
        'addedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      onMoved(book.id);
      Navigator.pop(sheetContext);
      _showSnack(
        sheetContext,
        'نُقل إلى "${_arabicStatus[newStatus] ?? newStatus}"',
        icon: Icons.check_circle,
      );
    } catch (e) {
      _showSnack(
        sheetContext,
        'تعذّر النقل. حاول مجددًا',
        icon: Icons.error_outline,
      );
    }
  }


  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final List<Widget> tiles = [];

        tiles.add(
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('حذف من القائمة'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _removeFromList(context);
            },
          ),
        );
        tiles.add(const Divider(height: 0));

        if (book.status == 'want') {
          tiles.add(
            ListTile(
              leading: const Icon(
                Icons.play_arrow_outlined,
                color: Colors.teal,
              ),
              title: const Text('نقل إلى: استمع لها الآن'),
              onTap: () => _moveToStatus(sheetContext, 'listen_now'),
            ),
          );
        } else if (book.status == 'listened') {
          // ✅ إذا في "استمعت لها" ما نعرض أي نقل (بس حذف)
        } else if (book.status == 'listen_now') {
          tiles.add(
            ListTile(
              leading: const Icon(Icons.bookmark_border, color: Colors.teal),
              title: const Text('نقل إلى: أرغب بالاستماع لها'),
              onTap: () => _moveToStatus(sheetContext, 'want'),
            ),
          );
          tiles.add(
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: Colors.teal,
              ),
              title: const Text('نقل إلى: استمعت لها'),
              onTap: () => _moveToStatus(sheetContext, 'listened'),
            ),
          );
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                ...tiles,
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BookDetailsPage(bookId: book.id)),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),

            child: ClipRRect(
              borderRadius: radius,
              child: Column(
                children: [
                  Expanded(
                    child: book.cover != null
                        ? Image(
                            image: book.cover!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          )
                        : Container(
                            width: double.infinity,
                            color: const Color(0xFFF6F2F7),
                            padding: const EdgeInsets.all(8),
                            alignment: Alignment.center,
                            child: Text(
                              book.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, height: 1.2),
                            ),
                          ),
                  ),

                ],
              ),
            ),

            // end change reema
          ),
          Positioned(
            top: -2,
            left: 8,
            child: GestureDetector(
              onTap: () => _showOptionsMenu(context),
              child: Container(
                width: 18,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFE26AA2),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.more_vert, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final int contentMs;
  final int totalMs;

  const _MiniProgressBar({required this.contentMs, required this.totalMs});

  @override
  Widget build(BuildContext context) {
    if (totalMs <= 0) {
      return const SizedBox(height: 6);
    }

    final p = (contentMs / totalMs).clamp(0.0, 1.0);
    final remainingMs = (totalMs - contentMs).clamp(0, totalMs);

    final remainingMin = (remainingMs / 60000).ceil();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      color: Colors.white,
      child: Column(
        children: [
          LinearProgressIndicator(
            value: p,
            minHeight: 4,
            backgroundColor: const Color(0xFFEAEAEA),
            valueColor: const AlwaysStoppedAnimation<Color>(_confirm),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

/// Model for a book uploaded by the user (users/{uid}/mybooks)
class MyBook {
  final String id;
  final String title;
  final String coverUrl;
  MyBook({required this.id, required this.title, required this.coverUrl});
}

/// Tab that shows "My Books" grid from users/{uid}/mybooks
class _MyBooksShelfTab extends StatelessWidget {
  final String uid;
  const _MyBooksShelfTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('mybooks')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_midGreen),
                ),
              );
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return const Center(child: Text('لا توجد كتب مضافة حتى الآن'));
            }

            final docs = snap.data!.docs;
            final books = docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final title = (data['title'] ?? '') as String;
              final coverUrl = (data['coverUrl'] ?? '') as String? ?? '';
              return MyBook(
                id: doc.id,
                title: title.isEmpty ? 'كتاب بدون عنوان' : title,
                coverUrl: coverUrl,
              );
            }).toList();

            return _MyShelfView(books: books, uid: uid);
          },
        ),
      ),
    );
  }
}

/// Physical rectangle for "My Books" shelves
class _ShelfRect {
  final double leftFrac, rightFrac, topFrac, heightFrac;
  const _ShelfRect({
    required this.leftFrac,
    required this.rightFrac,
    required this.topFrac,
    required this.heightFrac,
  });
}

/// Grid of books on the decorative shelves (for My Books)
class _MyShelfView extends StatefulWidget {
  final List<MyBook> books;
  final String uid;
  const _MyShelfView({required this.books, required this.uid});

  @override
  State<_MyShelfView> createState() => _MyShelfViewState();
}

class _MyShelfViewState extends State<_MyShelfView> {
  // Physical positions of the 4 shelves on the "My Books" background
  static const List<_ShelfRect> _shelfRects = [
    _ShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.09,
      heightFrac: 0.14,
    ),
    _ShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.29,
      heightFrac: 0.14,
    ),
    _ShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.49,
      heightFrac: 0.14,
    ),
    _ShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.69,
      heightFrac: 0.14,
    ),
  ];

  static const int _perShelf = 4;
  static const int _shelvesPerPage = 4;
  static const int _booksPerPage = _perShelf * _shelvesPerPage;
  static const double _spacing = 1;
  static const double _bookAspect = .25;
  static const double _bookStretch = 1.5;

  final PageController _pageController = PageController();
  late List<List<MyBook>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = _paginate(widget.books, _booksPerPage);
  }

  @override
  void didUpdateWidget(covariant _MyShelfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books.length != widget.books.length) {
      _pages = _paginate(widget.books, _booksPerPage);
    }
  }

  List<List<MyBook>> _paginate(List<MyBook> list, int size) {
    final pages = <List<MyBook>>[];
    for (var i = 0; i < list.length; i += size) {
      pages.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    if (pages.isEmpty) pages.add(const []);
    return pages;
  }

  List<List<MyBook>> _chunk(List<MyBook> list, int size) {
    final chunks = <List<MyBook>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    return chunks;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          itemCount: pages.length,
          itemBuilder: (context, pageIndex) {
            final pageBooks = pages[pageIndex];
            final groups = _chunk(pageBooks, _perShelf);

            return LayoutBuilder(
              builder: (context, c) {
                final W = c.maxWidth;
                final H = c.maxHeight;

                return Stack(
                  children: List.generate(_shelfRects.length, (i) {
                    final rect = _shelfRects[i];
                    final shelfBooks = i < groups.length
                        ? groups[i]
                        : const <MyBook>[];

                    final left = rect.leftFrac * W;
                    final right = rect.rightFrac * W;
                    final top = rect.topFrac * H;
                    final height = rect.heightFrac * H;
                    final width = W - left - right;

                    final slots = _perShelf;
                    final totalSpacing = _spacing * (slots - 1);
                    final bookWidth = ((width - totalSpacing) / slots * 0.95)
                        .clamp(40.0, 170.0);
                    final bookHeight = (bookWidth / _bookAspect * _bookStretch);

                    return Positioned(
                      left: left,
                      right: right,
                      top: top,
                      height: height,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(slots, (slot) {
                            final book = slot < shelfBooks.length
                                ? shelfBooks[slot]
                                : null;
                            return SizedBox(
                              width: bookWidth,
                              height: bookHeight,
                              child: book == null
                                  ? const SizedBox.shrink()
                                  : _MyBookCard(book: book, uid: widget.uid),
                            );
                          }),
                        ),
                      ),
                    );
                  }),
                );
              },
            );
          },
        ),

        // Page indicator for "My Books"
        Positioned(
          bottom: 25,
          right: 0,
          left: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                final current = _pageController.hasClients
                    ? (_pageController.page ?? 0).round()
                    : 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(pages.length, (i) {
                    final active = i == current;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFE26AA2)
                            : Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Single book card used inside "My Books"
class _MyBookCard extends StatelessWidget {
  final MyBook book;
  final String uid;
  const _MyBookCard({required this.book, required this.uid});

  void _showSnack(
    BuildContext context,
    String message, {
    IconData icon = Icons.check_circle,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
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

  Future<void> _deleteMyBook(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تأكيد حذف الكتاب',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد أنك تريد حذف هذا الكتاب من مكتبتك؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirm,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'تأكيد',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontSize: 16, color: _darkGreen),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;

    try {
      final storage = FirebaseStorage.instance;
      final baseRef = storage.ref('users/$uid/mybooks/${book.id}');

      await Future.wait([
        baseRef.child('book.pdf').delete().catchError((_) {}),
        baseRef.child('cover.jpg').delete().catchError((_) {}),
      ]);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('mybooks')
          .doc(book.id)
          .delete();

      _showSnack(context, 'تم حذف الكتاب', icon: Icons.check_circle);
    } catch (e) {
      _showSnack(context, 'تعذّر الحذف: $e', icon: Icons.error_outline);
    }
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('حذف الكتاب'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _deleteMyBook(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MyBookDetailsPage(bookId: book.id),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: book.coverUrl.isNotEmpty
                  ? Image.network(
                      book.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          color: const Color(0xFFF6F2F7),
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.center,
                          child: Text(
                            book.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, height: 1.2),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: const Color(0xFFF6F2F7),
                      padding: const EdgeInsets.all(8),
                      alignment: Alignment.center,
                      child: Text(
                        book.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, height: 1.2),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: -2,
            left: 8,
            child: GestureDetector(
              onTap: () => _showOptionsMenu(context),
              child: Container(
                width: 18,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFE26AA2),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.more_vert, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBarOnly extends StatelessWidget {
  final int contentMs;
  final int totalMs;
  final bool isCompleted;

  const _MiniBarOnly({
    required this.contentMs,
    required this.totalMs,
    required this.isCompleted,
  });
  // Bar under book style
  @override
  Widget build(BuildContext context) {
    final safeTotal = totalMs <= 0 ? 1 : totalMs;
    final p = isCompleted ? 1.0 : (contentMs / safeTotal).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      color: Colors.white,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LinearProgressIndicator(
          value: p,
          minHeight: 6,
          backgroundColor: const Color(0xFFC9DABF), // أخضر فاتح
          valueColor: const AlwaysStoppedAnimation<Color>(_confirm),
        ),
      ),
    );
  }
}

/// Full-screen form to add a new book (PDF + optional cover)
class AddMyBookPage extends StatefulWidget {
  const AddMyBookPage({super.key});

  @override
  State<AddMyBookPage> createState() => _AddMyBookPageState();
}

class _AddMyBookPageState extends State<AddMyBookPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  File? _pdfFile;
  File? _coverFile;
  bool _saving = false;
  bool _forceValidate = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  bool get _isReadyToSave =>
      _titleCtrl.text.trim().isNotEmpty && _pdfFile != null && !_saving;

  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
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

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: false,
    );
    if (!mounted) return;
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pdfFile = File(result.files.single.path!);
        _forceValidate = true;
      });
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (!mounted) return;
    if (x != null) {
      setState(() => _coverFile = File(x.path));
    }
  }

  Future<void> _saveBook() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('الرجاء تسجيل الدخول لإضافة كتاب', icon: Icons.login_rounded);
      return;
    }
    if (_titleCtrl.text.trim().isEmpty || _pdfFile == null) {
      setState(() => _forceValidate = true);
    }
    if (_titleCtrl.text.trim().isEmpty || _pdfFile == null) {
      _showSnack(_missingFriendlyMessage(), icon: Icons.info_outline);
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _showSnack('فضلاً أكمل الحقول المطلوبة', icon: Icons.info_outline);
      return;
    }
    try {
      setState(() => _saving = true);
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('mybooks')
          .doc();
      final storage = FirebaseStorage.instance;
      final baseRef = storage.ref('users/${user.uid}/mybooks/${docRef.id}');
      final pdfRef = baseRef.child('book.pdf');
      final pdfTask = await pdfRef.putFile(_pdfFile!);
      final pdfUrl = await pdfTask.ref.getDownloadURL();

      String? coverUrl;
      if (_coverFile != null) {
        final coverRef = baseRef.child('cover.jpg');
        final coverTask = await coverRef.putFile(_coverFile!);
        coverUrl = await coverTask.ref.getDownloadURL();
      }
      await docRef.set({
        'title': _titleCtrl.text.trim(),
        'pdfUrl': pdfUrl,
        'coverUrl': coverUrl,
        'ownerUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      // Return back to library after adding the book
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _showSnack('حدث خطأ أثناء الحفظ: $e', icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _missingFriendlyMessage() {
    final nameMissing = _titleCtrl.text.trim().isEmpty;
    final pdfMissing = _pdfFile == null;
    if (nameMissing && pdfMissing) {
      return 'أضيف اسم الكتاب واختار ملف PDF أولاً ';
    } else if (nameMissing) {
      return 'أضيف اسم الكتاب أولاً ✍';
    } else {
      return 'اختار ملف الكتاب (PDF) أولاً ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final nameMissing = _titleCtrl.text.trim().isEmpty;
    final pdfMissing = _pdfFile == null;
    final showPdfValidation =
        _forceValidate || _titleCtrl.text.trim().isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              // Increase this to align with the background design
              toolbarHeight: 160,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _midGreen,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              centerTitle: true,
              title: const Text('', style: TextStyle(color: _darkGreen)),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: Opacity(
                    opacity: _saving ? 0.6 : 1,
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _forceValidate
                          ? AutovalidateMode.always
                          : AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'الحقول المشار إليها بـ * مطلوبة',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _fieldContainer(
                            isError: _forceValidate && nameMissing,
                            child: TextFormField(
                              controller: _titleCtrl,
                              textAlign: TextAlign.right,
                              decoration: const InputDecoration(
                                labelText: 'اسم الكتاب *',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                labelStyle: TextStyle(color: _darkGreen),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'تنبيه: يدعم النظام معالجة ملفات PDF العربية فقط. الملفات المكتوبة بلغات أخرى لن تظهر لها نتائج.',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),

                          const SizedBox(height: 6),
                          _fileButton(
                            text: _pdfFile == null
                                ? 'اختيار ملف PDF *'
                                : 'تم اختيار: ${_pdfFile!.path.split('/').last}',
                            icon: Icons.picture_as_pdf,
                            onPressed: _pickPdf,
                            required: true,
                            isMissing: showPdfValidation && pdfMissing,
                          ),
                          const SizedBox(height: 14),
                          _fileButton(
                            text: _coverFile == null
                                ? 'اختيار صورة الغلاف (اختياري)'
                                : 'تم اختيار الغلاف',
                            icon: Icons.image_outlined,
                            onPressed: _pickCover,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isReadyToSave ? _saveBook : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _confirm,
                                disabledBackgroundColor: _confirm.withOpacity(
                                  0.45,
                                ),
                                disabledForegroundColor: Colors.white70,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _saving ? 'جارٍ الحفظ...' : 'حفظ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// Shared UI helpers

Widget _fieldContainer({required Widget child, bool isError = false}) {
  return Container(
    decoration: BoxDecoration(
      color: _fillGreen,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

Widget _fileButton({
  required String text,
  required IconData icon,
  required VoidCallback onPressed,
  bool required = false,
  bool isMissing = false,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, color: _darkGreen),
    label: Text(text, style: const TextStyle(color: _darkGreen)),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: _darkGreen),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: _fillGreen,
    ),
  );
}
