import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// لو عندك صفحة الشات
import 'club_chat_page.dart';

/// =====================
/// ألوان الهوية
/// =====================
const Color _darkGreen   = Color(0xFF0E3A2C);
const Color _midGreen    = Color(0xFF2F5145);
const Color _lightGreen  = Color(0xFFC9DABF);
const Color _confirm     = Color(0xFF6F8E63);
const Color _danger      = Color(0xFFB64B4B);

/// ✅ سناك موحّد
void _showAppSnack(BuildContext context, String message, {IconData icon = Icons.check_circle}) {
  ScaffoldMessenger.of(context).showSnackBar(
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}

class FriendDetailsPage extends StatelessWidget {
  final String friendUid;
  const FriendDetailsPage({super.key, required this.friendUid});

  @override
  Widget build(BuildContext context) {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(friendUid);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 110,
            leadingWidth: 56,
            leading: Padding(
              padding: const EdgeInsets.only(top: 45, right: 8),
              child: IconButton(
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _midGreen, size: 20),
              ),
            ),
            flexibleSpace: SafeArea(child: _FriendHeader(userDoc: userDoc)),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(86),
              child: _TabbarContainer(),
            ),
          ),
          body: Stack(
            clipBehavior: Clip.none,
            children: const [
              Positioned.fill(
                child: Image(image: AssetImage('assets/images/friend.png'), fit: BoxFit.cover),
              ),
              TabBarView(
                physics: BouncingScrollPhysics(),
                children: [
                  _StatsTabWrapper(),
                  _ReviewsTabWrapper(),
                  _ClubsTabWrapper(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// Header داخل AppBar: الصورة + الاسم + @ + زر ديناميكي
/// ===============================
class _FriendHeader extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> userDoc;
  const _FriendHeader({required this.userDoc});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name     = (data['name'] ?? '') as String;
        final username = (data['username'] ?? '') as String;
        final photoUrl = (data['photoUrl'] ?? '') as String;

        final userAsTail = username.isEmpty
            ? ''
            : (username.startsWith('@') ? '${username.substring(1)}@' : '$username@');

        return Align(
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: const Offset(13, -53),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  backgroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
                  child: photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.black38) : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name.isEmpty ? 'بدون اسم' : name,
                      style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(userAsTail, style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                  ],
                ),
                const SizedBox(width: 70),
                _DynamicFriendAction(
                  friendUid: userDoc.id,
                  friendName: name.isEmpty ? 'الصديق' : name,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// زر ديناميكي: صديق/بانتظار القبول/إضافة
class _DynamicFriendAction extends StatelessWidget {
  final String friendUid;
  final String friendName;
  const _DynamicFriendAction({required this.friendUid, required this.friendName});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const SizedBox.shrink();

    final myFriendDoc = FirebaseFirestore.instance
        .collection('users').doc(me.uid)
        .collection('friends').doc(friendUid);

    final pendingReqDoc = FirebaseFirestore.instance
        .collection('users').doc(friendUid)
        .collection('friendRequests').doc(me.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myFriendDoc.snapshots(),
      builder: (context, friendSnap) {
        final isFriend = friendSnap.data?.exists == true;
        if (isFriend) {
          return _FriendBadge(
            isFollowing: true,
            onTap: () => _HeaderAndTabs._confirmUnfollow(context, friendName, friendUid),
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: pendingReqDoc.snapshots(),
          builder: (context, reqSnap) {
            final waiting = reqSnap.data?.exists == true;
            if (waiting) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: _confirm.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Text('بانتظار القبول ⏳',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _confirm)),
              );
            }
            return GestureDetector(
              onTap: () => _HeaderAndTabs.sendFriendRequest(context, friendUid),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: _confirm, borderRadius: BorderRadius.circular(12)),
                child: const Text('إضافة',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            );
          },
        );
      },
    );
  }
}

/// ===============================
/// شريط التبويبات الأبيض
/// ===============================
class _TabbarContainer extends StatelessWidget {
  const _TabbarContainer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: const _TabsOnly(),
      ),
    );
  }
}

class _TabsOnly extends StatelessWidget {
  const _TabsOnly();

  @override
  Widget build(BuildContext context) {
    return const TabBar(
      labelColor: _darkGreen,
      unselectedLabelColor: Colors.black54,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(width: 4, color: _darkGreen),
        insets: EdgeInsets.symmetric(horizontal: 24),
      ),
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      tabs: [
        Tab(text: 'الإحصائيات'),
        Tab(text: 'التقييمات'),
        Tab(text: 'الأندية'),
      ],
    );
  }
}

/// ===============================
/// عمليات إرسال/إلغاء الصداقة
/// ===============================
class _HeaderAndTabs {
  static Future<void> sendFriendRequest(BuildContext context, String friendUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final reqRef = FirebaseFirestore.instance
        .collection('users').doc(friendUid)
        .collection('friendRequests').doc(me.uid);

    try {
      await reqRef.set({'fromUid': me.uid, 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      _showAppSnack(context, 'تم إرسال الطلب ✅');
    } catch (e) {
      _showAppSnack(context, 'تعذّر الإرسال: $e', icon: Icons.error_outline);
    }
  }

  static Future<void> _confirmUnfollow(BuildContext context, String friendName, String friendUid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('إلغاء المتابعة', textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: _darkGreen)),
          content: Text('هل أنت متأكد من إلغاء متابعة $friendName؟',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            SizedBox(
              width: 130,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _danger, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('نعم، ألغِ'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 130,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: _lightGreen, foregroundColor: _darkGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع'),
              ),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _unfriend(me.uid, friendUid);
      if (!context.mounted) return;
      _showAppSnack(context, 'تم إلغاء المتابعة');
      Navigator.of(context).maybePop();
    }
  }

  static Future<void> _unfriend(String myUid, String friendUid) async {
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();

    final myFriend   = fs.collection('users').doc(myUid).collection('friends').doc(friendUid);
    final hisFriend  = fs.collection('users').doc(friendUid).collection('friends').doc(myUid);

    final reqHimHasFromMe = fs.collection('users').doc(friendUid).collection('friendRequests').doc(myUid);
    final reqMeHasFromHim = fs.collection('users').doc(myUid).collection('friendRequests').doc(friendUid);

    batch.delete(myFriend);
    batch.delete(hisFriend);
    batch.delete(reqHimHasFromMe);
    batch.delete(reqMeHasFromHim);

    await batch.commit();
  }
}

/// ===============================
/// تبويب الإحصاءات
/// ===============================
class _StatsTabWrapper extends StatelessWidget {
  const _StatsTabWrapper();

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorWidgetOfExactType<FriendDetailsPage>()!;
    return _StatsTab(friendUid: parent.friendUid);
  }
}

class _StatsTab extends StatelessWidget {
  final String friendUid;
  const _StatsTab({required this.friendUid});

  static const Color _card = Color(0xFFE6F0E0);

  @override
  Widget build(BuildContext context) {
    final statsRef = FirebaseFirestore.instance
        .collection('users').doc(friendUid)
        .collection('stats').doc('main');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: statsRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final best     = data?['bestStreak']    ?? 0;
        final current  = data?['currentStreak'] ?? 0;
        final listened = data?['listenedCount'] ?? 0;

        final items = [
          _StatRow(icon: '🏅', text: 'أفضل مداومة: $best يوم'),
          _StatRow(icon: '🔥', text: 'المداومة الحالية: $current يوم'),
          _StatRow(icon: '📚', text: 'الكتب المسموعة: $listened كتاب'),
        ];

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 300, 16, 24),
          itemBuilder: (_, i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: _card, borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(items[i].icon, style: const TextStyle(fontSize: 22)),
                Expanded(
                  child: Text(
                    items[i].text,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _darkGreen),
                  ),
                ),
              ],
            ),
          ),
          separatorBuilder: (_, __) => const SizedBox(height: 32),
          itemCount: items.length,
        );
      },
    );
  }
}

class _StatRow {
  final String icon;
  final String text;
  const _StatRow({required this.icon, required this.text});
}

/// ===============================
/// تبويب التقييمات
/// ===============================
class _ReviewsTabWrapper extends StatelessWidget {
  const _ReviewsTabWrapper();

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorWidgetOfExactType<FriendDetailsPage>()!;
    return _FriendReviewsTab(friendUid: parent.friendUid);
  }
}

class _FriendReviewsTab extends StatelessWidget {
  final String friendUid;
  const _FriendReviewsTab({required this.friendUid});

  @override
  Widget build(BuildContext context) {
    final reviewsQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('reviews')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: reviewsQuery.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _friendLoadingSkeleton();
        }
        if (snap.hasError) {
          return _friendErrorBox('حدث خطأ أثناء جلب تقييمات الصديق.');
        }

        final docs = snap.data?.docs ?? const [];
        final reviews = docs.map((d) => _FriendReview.fromDoc(d.id, d.data())).toList();

        if (reviews.isEmpty) {
          return _friendEmptyBox();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 280, 16, 24),
          itemCount: reviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = reviews[i];
            return _FriendReviewTile(
              title: r.bookTitle ?? 'كتاب بدون عنوان',
              stars: (r.rating >= 0 && r.rating <= 5) ? r.rating : 0,
              date: r.formattedDate,
              review: r.text,
              coverUrl: r.bookCover,
            );
          },
        );
      },
    );
  }

  Widget _friendEmptyBox() {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 280, 16, 24),
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: const Text('لا توجد تقييمات بعد 📭',
          style: TextStyle(color: Colors.black54, fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _friendErrorBox(String msg) {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 280, 16, 24),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          border: Border.all(color: Colors.red.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendLoadingSkeleton() {
    Widget bone() => Container(
      height: 84,
      decoration: BoxDecoration(color: _lightGreen.withOpacity(0.6), borderRadius: BorderRadius.circular(16)),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 280, 16, 24),
      children: [bone(), const SizedBox(height: 10), bone(), const SizedBox(height: 10), bone()],
    );
  }
}

class _FriendReview {
  final String id;
  final String? bookTitle;
  final String? bookCover;
  final String? text;
  final int rating;
  final DateTime? createdAt;

  _FriendReview({
    required this.id,
    required this.bookTitle,
    required this.bookCover,
    required this.text,
    required this.rating,
    required this.createdAt,
  });

  factory _FriendReview.fromDoc(String id, Map<String, dynamic> data) {
    DateTime? created;
    final raw = data['createdAt'];
    if (raw is Timestamp) created = raw.toDate();
    else if (raw is String) { try { created = DateTime.tryParse(raw); } catch (_) {} }

    final title   = (data['bookTitle'] ?? data['title']) as String?;
    final cover   = (data['bookCover'] ?? data['coverUrl']) as String?;
    final content = (data['text'] ?? data['snippet']) as String?;

    final ratingVal = (() {
      final v = data['rating'];
      if (v is num) return v.toInt();
      if (v is String) { final p = int.tryParse(v); if (p != null) return p; }
      return 0;
    })();

    return _FriendReview(
      id: id,
      bookTitle: title?.trim(),
      bookCover: cover?.trim(),
      text: content?.trim(),
      rating: ratingVal,
      createdAt: created,
    );
  }

  String get formattedDate {
    if (createdAt == null) return '';
    final y = createdAt!.year.toString().padLeft(4, '0');
    final m = createdAt!.month.toString().padLeft(2, '0');
    final d = createdAt!.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _FriendReviewTile extends StatelessWidget {
  final String title;
  final int stars;
  final String date;
  final String? review;
  final String? coverUrl;

  const _FriendReviewTile({
    required this.title,
    required this.stars,
    required this.date,
    this.review,
    this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: _lightGreen, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (coverUrl != null && coverUrl!.isNotEmpty)
                ? Image.network(coverUrl!, width: 56, height: 72, fit: BoxFit.cover)
                : Container(width: 56, height: 72, color: Colors.white.withOpacity(0.6),
                child: const Icon(Icons.menu_book, color: _darkGreen)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _darkGreen),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(date, style: const TextStyle(fontSize: 12, color: _darkGreen)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: List.generate(5, (i) {
                    final filled = i < stars;
                    return Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(filled ? Icons.star : Icons.star_border, size: 18, color: _darkGreen),
                    );
                  }),
                ),
                if (review != null && review!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      review!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13.5, height: 1.35, color: _darkGreen),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// تبويب الأندية — يعرض أندية الصديق فقط، مع زر حالتك أنتِ
/// ===============================
class _ClubsTabWrapper extends StatelessWidget {
  const _ClubsTabWrapper();

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorWidgetOfExactType<FriendDetailsPage>()!;
    return _ClubsTab(friendUid: parent.friendUid);
  }
}

class _ClubsTab extends StatelessWidget {
  final String friendUid;
  const _ClubsTab({required this.friendUid});

  static const Color _card = Color(0xFFE6F0E0);

  @override
  Widget build(BuildContext context) {
    final clubsRef = FirebaseFirestore.instance.collection('clubs');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: clubsRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final clubs = snap.data?.docs ?? const [];

        if (clubs.isEmpty) {
          return const Center(child: Text('لا توجد أندية', style: TextStyle(color: Colors.black54)));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 280, 16, 24),
          itemCount: clubs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final clubDoc = clubs[i];
            final clubId  = clubDoc.id;
            final data    = clubDoc.data();
            final title   = (data['title'] ?? 'نادي بدون اسم') as String;
            final desc    = (data['description'] ?? '') as String?;
            final cat     = (data['category'] ?? '') as String?;

            // نعرض النادي فقط إذا كان الصديق عضواً فيه
            final friendMemberDoc = FirebaseFirestore.instance
                .collection('clubs').doc(clubId)
                .collection('members').doc(friendUid)
                .snapshots();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: friendMemberDoc,
              builder: (context, friendSnap) {
                final friendIsMember = friendSnap.data?.exists == true;
                if (!friendIsMember) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: _darkGreen, fontSize: 18, fontWeight: FontWeight.w900)),
                      if (desc != null && desc.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(desc, style: const TextStyle(color: Colors.black87, height: 1.35)),
                      ],
                      if (cat != null && cat.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('الفئة: $cat',
                            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd, // يسار في RTL
                        child: _JoinOrOpenButtonFD(clubId: clubId, clubTitle: title),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// زر الانضمام/فتح الشات داخل تبويب صديق
class _JoinOrOpenButtonFD extends StatefulWidget {
  final String clubId;
  final String clubTitle;
  const _JoinOrOpenButtonFD({required this.clubId, required this.clubTitle});

  @override
  State<_JoinOrOpenButtonFD> createState() => _JoinOrOpenButtonFDState();
}

class _JoinOrOpenButtonFDState extends State<_JoinOrOpenButtonFD> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const SizedBox.shrink();

    final myMemberDocStream = FirebaseFirestore.instance
        .collection('clubs').doc(widget.clubId)
        .collection('members').doc(me.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myMemberDocStream,
      builder: (context, snap) {
        final isMember = snap.data?.exists == true;

        final String label = isMember ? 'أنت جزء من النادي' : 'انضم';
        final Color bg      = isMember ? Colors.white : _confirm;
        final BorderSide side =
        isMember ? const BorderSide(color: _darkGreen, width: 1.2) : BorderSide.none;

        return SizedBox(
          height: 36,
          child: TextButton(
            onPressed: _busy
                ? null
                : () async {
              setState(() => _busy = true);
              try {
                if (!isMember) {
                  await FirebaseFirestore.instance
                      .collection('clubs').doc(widget.clubId)
                      .collection('members').doc(me.uid)
                      .set({'joinedAt': FieldValue.serverTimestamp()});
                }
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ClubChatPage(
                        clubId: widget.clubId,
                        clubTitle: widget.clubTitle,
                      ),
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: _darkGreen, // النص داكن في الحالتين
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: side,
              ),
            ),
            child: _busy
                ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_darkGreen),
              ),
            )
                : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        );
      },
    );
  }
}

class _FriendBadge extends StatelessWidget {
  final bool isFollowing;
  final VoidCallback onTap;
  const _FriendBadge({required this.isFollowing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: _confirm.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: const [
            Icon(Icons.verified, size: 18, color: _confirm),
            SizedBox(width: 6),
            Text('صديق', style: TextStyle(fontWeight: FontWeight.w700, color: _confirm)),
          ],
        ),
      ),
    );
  }
}