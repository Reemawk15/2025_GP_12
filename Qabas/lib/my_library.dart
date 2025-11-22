import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'book_details_page.dart';
import 'library_tab.dart'; // fallback if there is no previous page

const Color _midGreen = Color(0xFF2F5145);
const Color _confirm    = Color(0xFF6F8E63);

// =======================
// Position/size config for the circular action button (kept for future use)
const double kCheckAlignX = 1.0; // 0 = center horizontally
const double kCheckAlignY = -1.7; // negative = above the card
const double kCheckOffsetX = 0.0;
const double kCheckOffsetY = 0.0;
// size and elevation
const double kCheckDiameter = 28.0;
const double kCheckIconSize = 18.0;
const double kCheckElevation = 2.0;
// =======================

/// Book model inside the user library
class Book {
  final String id; // real docId in collection('library')
  final String title;
  final ImageProvider? cover;
  final String status; // listen_now | want | listened
  const Book({
    required this.id,
    required this.title,
    this.cover,
    required this.status,
  });
}

class MyLibraryPage extends StatelessWidget {
  const MyLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 3,
        child: Stack(
          children: [
            // background
            Positioned.fill(
              child: Image.asset('assets/images/private2.png', fit: BoxFit.cover),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Column(
                  children: [
                    // back arrow only
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8, top: 50),
                        child: IconButton(
                          tooltip: 'رجوع',
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: _midGreen,
                            size: 20,
                          ),
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            } else {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const LibraryTab()),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // tab bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.9),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TabBar(
                          indicator: const UnderlineTabIndicator(
                            borderSide: BorderSide(width: 2),
                          ),
                          dividerColor: Colors.transparent,
                          overlayColor:
                          MaterialStateProperty.all(Colors.transparent),
                          labelColor: _midGreen,
                          unselectedLabelColor: Colors.black54,
                          labelStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          labelPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                          tabs: const [
                            Tab(text: 'أرغب بالاستماع لها'),
                            Tab(text: 'استمع لها الآن'),
                            Tab(text: 'استمعت لها'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // tab content
                    Expanded(
                      child: user == null
                          ? const Center(
                        child: Text('الرجاء تسجيل الدخول لعرض مكتبتك'),
                      )
                          : TabBarView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _LibraryShelf(status: 'want', uid: user.uid),
                          _LibraryShelf(status: 'listen_now', uid: user.uid),
                          _LibraryShelf(status: 'listened', uid: user.uid),
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

/// Single shelf tab (reads Firestore by status) — Stateful with local cache
class _LibraryShelf extends StatefulWidget {
  final String status;
  final String uid;
  const _LibraryShelf({required this.status, required this.uid});

  @override
  State<_LibraryShelf> createState() => _LibraryShelfState();
}

class _LibraryShelfState extends State<_LibraryShelf> {
  // last non-empty list to avoid sudden empty flicker
  List<Book> _lastNonEmpty = const [];
  // IDs hidden locally after optimistic move/delete
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
          // If there is an error and no cached data, show the empty-state message
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
          return Book(
            id: d.id,
            title: title.isEmpty ? 'كتاب' : title,
            cover: cover.isNotEmpty ? NetworkImage(cover) : null,
            status: status,
          );
        }).toList();

        final current =
        all.where((b) => !_locallyHidden.contains(b.id)).toList();

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

/// Represents a shelf region as fractions of the total size
class ShelfRect {
  final double leftFrac, rightFrac, topFrac, heightFrac;
  const ShelfRect({
    required this.leftFrac,
    required this.rightFrac,
    required this.topFrac,
    required this.heightFrac,
  });
}

/// Shelves layout + paged browsing
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
  static const List<ShelfRect> _shelfRects = [
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.09, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.29, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.48, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.69, heightFrac: 0.11),
  ];

  static const int _perShelf = 4;
  static const int _shelvesPerPage = 4;
  static const int _booksPerPage = _perShelf * _shelvesPerPage; // 16
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
                    final shelfBooks =
                    i < groups.length ? groups[i] : const <Book>[];

                    final left = rect.leftFrac * W;
                    final right = rect.rightFrac * W;
                    final top = rect.topFrac * H;
                    final height = rect.heightFrac * H;
                    final width = W - left - right;

                    final slots = _perShelf;
                    final totalSpacing = _spacing * (slots - 1);
                    final bookWidth =
                    ((width - totalSpacing) / slots * 0.9).clamp(40.0, 140.0);
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
                            final book =
                            slot < shelfBooks.length ? shelfBooks[slot] : null;
                            return SizedBox(
                              width: bookWidth,
                              height: bookHeight,
                              child: book == null
                                  ? const SizedBox.shrink()
                                  : _BookCard(
                                book: book,
                                uid: widget.uid,
                                onMoved: widget.onMoved,
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

        // page indicator
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

  // unified SnackBar style
  void _showSnack(BuildContext context, String message,
      {IconData icon = Icons.check_circle}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
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
      await ref.delete();
      // Optimistically hide the card locally so it disappears immediately
      onMoved(book.id);
      _showSnack(context, 'تم الحذف من قائمتك', icon: Icons.check_circle);
    } catch (e) {
      _showSnack(
        context,
        'تعذّر الحذف. حاول مجددًا',
        icon: Icons.error_outline,
      );
    }
  }

  // Move to a new status and hide locally
  Future<void> _moveToStatus(
      BuildContext sheetContext, String newStatus) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('library')
        .doc(book.id);
    try {
      await ref.set(
        {
          'status': newStatus,
          'addedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
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

  // Show options bottom sheet depending on current status
  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final List<Widget> tiles = [];

        // delete option is always available
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

        // movement options depend on the current status
        if (book.status == 'want') {
          // only "listen now" is offered from "want"
          tiles.add(
            ListTile(
              leading: const Icon(Icons.play_arrow_outlined, color: Colors.teal),
              title: const Text('نقل إلى: استمع لها الآن'),
              onTap: () => _moveToStatus(sheetContext, 'listen_now'),
            ),
          );
        } else if (book.status == 'listened') {
          tiles.add(
            ListTile(
              leading: const Icon(Icons.bookmark_border, color: Colors.teal),
              title: const Text('نقل إلى: أرغب بالاستماع لها'),
              onTap: () => _moveToStatus(sheetContext, 'want'),
            ),
          );
          tiles.add(
            ListTile(
              leading: const Icon(Icons.play_arrow_outlined, color: Colors.teal),
              title: const Text('نقل إلى: استمع لها الآن'),
              onTap: () => _moveToStatus(sheetContext, 'listen_now'),
            ),
          );
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
              leading:
              const Icon(Icons.check_circle_outline, color: Colors.teal),
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
          MaterialPageRoute(
            builder: (_) => BookDetailsPage(bookId: book.id),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // card
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
              child: book.cover != null
                  ? Image(image: book.cover!, fit: BoxFit.cover)
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

          // pink ribbon with three-dots menu icon
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
                  child: Icon(
                    Icons.more_vert,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // (previous circular green button removed)
        ],
      ),
    );
  }
}
