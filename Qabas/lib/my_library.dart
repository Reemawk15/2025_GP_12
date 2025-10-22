import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'book_details_page.dart';
import 'library_tab.dart'; // للرجوع لو ما فيه صفحة قبل

const Color _midGreen = Color(0xFF2F5145);

// =======================
// ⬅ تحكم بالأرقام لموضع/حجم الزر الدائري أعلى الكرت
// -1 يسار/أعلى .. +1 يمين/أسفل بالنسبة لحدود الكرت
const double kCheckAlignX   = 1.0;     // 0 = منتصف أفقيًا
const double kCheckAlignY   = -1.7;    // سالب = فوق الكرت
// إزاحة إضافية بالبكسل (بعد المحاذاة)
const double kCheckOffsetX  = 0.0;
const double kCheckOffsetY  = 0.0;
// الحجم والشكل
const double kCheckDiameter = 28.0;    // قطر الدائرة
const double kCheckIconSize = 18.0;    // حجم أيقونة الصح
const double kCheckElevation = 2.0;    // ظل بسيط
// =======================

/// نموذج الكتاب داخل مكتبة المستخدم
class Book {
  final String id;                 // 👈 docId الحقيقي في collection('library')
  final String title;
  final ImageProvider? cover;
  final String status;             // listen_now | want | listened
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
            // الخلفية
            Positioned.fill(
              child: Image.asset('assets/images/private2.png', fit: BoxFit.cover),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Column(
                  children: [
                    // 🔙 سهم رجوع فقط
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8, top: 50),
                        child: IconButton(
                          tooltip: 'رجوع',
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _midGreen, size: 20),
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

                    // شريط التبويبات
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.9),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TabBar(
                          // ✅ بدون خلفية أو حبة ملوّنة
                          indicator: const UnderlineTabIndicator(
                            borderSide: BorderSide(width: 2),
                          ),
                          dividerColor: Colors.transparent,   // يخفي الخط الفاصل السفلي
                          overlayColor: MaterialStateProperty.all(Colors.transparent), // يلغي وميض الضغط

                          // شكل النص المختار/غير المختار
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

                          // مسافات لطيفة حول العناوين
                          labelPadding: const EdgeInsets.symmetric(horizontal: 12),

                          tabs: const [
                            Tab(text: 'استمع لها الآن'),
                            Tab(text: 'أرغب بالاستماع لها'),
                            Tab(text: 'استمعت لها'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // محتوى التبويبات
                    Expanded(
                      child: user == null
                          ? const Center(child: Text('الرجاء تسجيل الدخول لعرض مكتبتك'))
                          : TabBarView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _LibraryShelf(status: 'listen_now', uid: user.uid),
                          _LibraryShelf(status: 'want',       uid: user.uid),
                          _LibraryShelf(status: 'listened',   uid: user.uid),
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

/// تبويب واحد (يقرأ من Firestore حسب الحالة) — Stateful مع كاش + إخفاء تفاؤلي
class _LibraryShelf extends StatefulWidget {
  final String status;
  final String uid;
  const _LibraryShelf({required this.status, required this.uid});

  @override
  State<_LibraryShelf> createState() => _LibraryShelfState();
}

class _LibraryShelfState extends State<_LibraryShelf> {
  // آخر قائمة غير فاضية لمنع اختفاء مفاجئ
  List<Book> _lastNonEmpty = const [];
  // 👇 عناصر نخفيها محليًا مباشرة بعد النقل (optimistic)
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
        .collection('users').doc(widget.uid)
        .collection('library')
        .where('status', isEqualTo: widget.status)
        .orderBy('addedAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          if (_lastNonEmpty.isNotEmpty) {
            return _ShelfView(books: _lastNonEmpty, uid: widget.uid, onMoved: _onMovedLocally);
          }
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          if (_lastNonEmpty.isNotEmpty) {
            return _ShelfView(books: _lastNonEmpty, uid: widget.uid, onMoved: _onMovedLocally);
          }
          return const Center(child: Text('تعذّر تحميل المكتبة'));
        }

        final docs = snap.data?.docs ?? [];
        final all = docs.map((d) {
          final m = d.data() as Map<String, dynamic>? ?? {};
          final title  = (m['title'] ?? '') as String;
          final cover  = (m['coverUrl'] ?? '') as String;
          final status = (m['status'] ?? 'want') as String;
          return Book(
            id: d.id, // 👈 docId الحقيقي
            title: title.isEmpty ? 'كتاب' : title,
            cover: cover.isNotEmpty ? NetworkImage(cover) : null,
            status: status,
          );
        }).toList();

        final current = all.where((b) => !_locallyHidden.contains(b.id)).toList();

        if (current.isNotEmpty) {
          _lastNonEmpty = current;
          return _ShelfView(books: current, uid: widget.uid, onMoved: _onMovedLocally);
        }

        if (_lastNonEmpty.isNotEmpty) {
          return _ShelfView(books: _lastNonEmpty, uid: widget.uid, onMoved: _onMovedLocally);
        }

        return const Center(child: Text('لا توجد كتب في هذه القائمة بعد'));
      },
    );
  }
}

/// يحدد منطقة رف كنِسَب نسبةً للحجم
class ShelfRect {
  final double leftFrac, rightFrac, topFrac, heightFrac;
  const ShelfRect({
    required this.leftFrac,
    required this.rightFrac,
    required this.topFrac,
    required this.heightFrac,
  });
}

/// شبكة الرفوف + التصفّح الصفحي
class _ShelfView extends StatefulWidget {
  final List<Book> books;
  final String uid;
  final void Function(String docId) onMoved; // 👈 نمرّر كولباك للإخفاء الفوري
  const _ShelfView({required this.books, required this.uid, required this.onMoved});

  @override
  State<_ShelfView> createState() => _ShelfViewState();
}

class _ShelfViewState extends State<_ShelfView> {
  static const List<ShelfRect> _shelfRects = [
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.10, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.30, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.50, heightFrac: 0.11),
    ShelfRect(leftFrac: 0.18, rightFrac: 0.18, topFrac: 0.70, heightFrac: 0.11),
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
      pages.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    if (pages.isEmpty) pages.add(const []);
    return pages;
  }

  List<List<Book>> _chunk(List<Book> list, int size) {
    final chunks = <List<Book>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
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

            return LayoutBuilder(builder: (context, c) {
              final W = c.maxWidth;
              final H = c.maxHeight;

              return Stack(
                children: List.generate(_shelfRects.length, (i) {
                  final rect = _shelfRects[i];
                  final shelfBooks = i < groups.length ? groups[i] : const <Book>[];

                  final left = rect.leftFrac * W;
                  final right = rect.rightFrac * W;
                  final top = rect.topFrac * H;
                  final height = rect.heightFrac * H;
                  final width = W - left - right;

                  final slots = _perShelf;
                  final totalSpacing = _spacing * (slots - 1);
                  final bookWidth = ((width - totalSpacing) / slots * 0.9).clamp(40.0, 140.0);
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
                          final book = slot < shelfBooks.length ? shelfBooks[slot] : null;
                          return SizedBox(
                            width: bookWidth,
                            height: bookHeight,
                            child: book == null
                                ? const SizedBox.shrink()
                                : _BookCard(book: book, uid: widget.uid, onMoved: widget.onMoved),
                          );
                        }),
                      ),
                    ),
                  );
                }),
              );
            });
          },
        ),

        // مؤشّر الصفحات
        Positioned(
          bottom: 25,
          right: 0,
          left: 0,
          child: Center(
            child: AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                final current = _pageController.hasClients ? (_pageController.page ?? 0).round() : 0;
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
                        color: active ? const Color(0xFFE26AA2) : Colors.black26,
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
  final void Function(String docId) onMoved; // 👈 نستدعيه بعد النجاح
  const _BookCard({required this.book, required this.uid, required this.onMoved});

  static const Map<String, String> _arabicStatus = {
    'listen_now': 'استمع لها الآن',
    'want'      : 'أرغب بالاستماع لها',
    'listened'  : 'استمعت لها',
  };

  static const Map<String, String> _other1 = {
    'listen_now': 'want',
    'want'      : 'listen_now',
    'listened'  : 'listen_now',
  };
  static const Map<String, String> _other2 = {
    'listen_now': 'listened',
    'want'      : 'listened',
    'listened'  : 'want',
  };

  // ✅ نفس تصميم SnackBar الموحد
  void _showSnack(BuildContext context, String message, {IconData icon = Icons.check_circle}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: _midGreen,
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
        .collection('users').doc(uid)
        .collection('library').doc(book.id);
    await ref.delete();
    _showSnack(context, 'تم الحذف من قائمتك', icon: Icons.check_circle);
  }

  // دالة النقل — تستخدم docId الحقيقي + إخفاء تفاؤلي
  Future<void> _moveToStatus(BuildContext context, String newStatus, {bool shouldPop = true}) async {
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('library').doc(book.id); // book.id هو docId
    try {
      await ref.set(
        {'status': newStatus, 'addedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      onMoved(book.id); // 👈 أخفِ البطاقة فورًا محليًا

      if (shouldPop) {
        Navigator.pop(context); // إغلاق الـBottomSheet فقط
      }
      _showSnack(context, 'نُقل إلى "${_arabicStatus[newStatus] ?? newStatus}"', icon: Icons.check_circle);
    } catch (e) {
      _showSnack(context, 'تعذّر النقل. حاول مجددًا', icon: Icons.error_outline);
    }
  }

  void _showLongPressMenu(BuildContext context) {
    final dst1 = _other1[book.status]!;
    final dst2 = _other2[book.status]!;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(height: 4, width: 42, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('حذف من القائمة'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _removeFromList(context);
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline, color: Colors.teal),
                  title: Text('نقل إلى: ${_arabicStatus[dst1]}'),
                  onTap: () => _moveToStatus(context, dst1), // يغلق الـSheet
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_rtl_outlined, color: Colors.teal),
                  title: Text('نقل إلى: ${_arabicStatus[dst2]}'),
                  onTap: () => _moveToStatus(context, dst2), // يغلق الـSheet
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
          MaterialPageRoute(builder: (_) => BookDetailsPage(bookId: book.id)),
        );
      },
      onLongPress: () => _showLongPressMenu(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // الكرت
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3))],
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

          // الشريطة العلوية كما هي
          const Positioned(
            top: -2,
            left: 8,
            child: SizedBox(
              width: 14,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFE26AA2),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),

          // ✅ زر دائري "صح" فوق الكرت — بدون نص
          if (book.status == 'listen_now')
            Positioned.fill(
              child: Align(
                alignment: Alignment(kCheckAlignX, kCheckAlignY),
                child: Transform.translate(
                  offset: Offset(kCheckOffsetX, kCheckOffsetY),
                  child: Material(
                    color: const Color(0xFF6F8E63),
                    shape: const CircleBorder(),
                    elevation: kCheckElevation,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _moveToStatus(context, 'listened', shouldPop: false),
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: kCheckDiameter,
                        height: kCheckDiameter,
                        child: const Center(
                          child: Icon(Icons.check, color: Colors.white, size: kCheckIconSize),
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