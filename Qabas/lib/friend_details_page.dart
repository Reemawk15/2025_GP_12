import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'club_chat_page.dart';
import 'book_details_page.dart';
import 'podcast_details_page.dart';

/// =====================
/// Brand colors
/// =====================
const Color _darkGreen = Color(0xFF0E3A2C);
const Color _midGreen = Color(0xFF2F5145);
const Color _lightGreen = Color(0xFFC9DABF);
const Color _confirm = Color(0xFF6F8E63);
const Color _danger = Color(0xFFB64B4B);

/// Unified snack bar helper
void _showAppSnack(
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

class FriendDetailsPage extends StatelessWidget {
  final String friendUid;
  const FriendDetailsPage({super.key, required this.friendUid});

  @override
  Widget build(BuildContext context) {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(friendUid);
    final me = FirebaseAuth.instance.currentUser;

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
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _midGreen,
                  size: 20,
                ),
              ),
            ),
            flexibleSpace: SafeArea(child: _FriendHeader(userDoc: userDoc)),
            bottom: me == null
                ? null
                : PreferredSize(
              preferredSize: const Size.fromHeight(86),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: userDoc.snapshots(),
                builder: (context, userSnap) {
                  final userData = userSnap.data?.data() ?? {};
                  final isPrivate = (userData['isPrivate'] as bool?) ?? false;

                  final myFriendDoc = FirebaseFirestore.instance
                      .collection('users')
                      .doc(me.uid)
                      .collection('friends')
                      .doc(friendUid);

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: myFriendDoc.snapshots(),
                    builder: (context, friendSnap) {
                      final isFriend = friendSnap.data?.exists == true;
                      final shouldLock = isPrivate && !isFriend;

                      if (shouldLock) {
                        return const SizedBox(height: 86);
                      }

                      return const _TabbarContainer();
                    },
                  );
                },
              ),
            ),
          ),
          body: me == null
              ? const Center(child: Text('الرجاء تسجيل الدخول.'))
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userDoc.snapshots(),
            builder: (context, userSnap) {
              final userData = userSnap.data?.data() ?? {};
              final isPrivate = (userData['isPrivate'] as bool?) ?? false;

              final myFriendDoc = FirebaseFirestore.instance
                  .collection('users')
                  .doc(me.uid)
                  .collection('friends')
                  .doc(friendUid);

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: myFriendDoc.snapshots(),
                builder: (context, friendSnap) {
                  final isFriend = friendSnap.data?.exists == true;
                  final shouldLock = isPrivate && !isFriend;

                  if (shouldLock) {
                    return const Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Image(
                            image: AssetImage('assets/images/friend.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                        _PrivateAccountView(),
                      ],
                    );
                  }

                  return const Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Image(
                          image: AssetImage('assets/images/friend.png'),
                          fit: BoxFit.cover,
                        ),
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
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// Header inside AppBar: avatar + name + username + dynamic friend button
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
        final name = (data['name'] ?? '') as String;
        final username = (data['username'] ?? '') as String;
        final photoUrl = (data['photoUrl'] ?? '') as String;

        final userAsTail = username.isEmpty
            ? ''
            : (username.startsWith('@')
            ? '${username.substring(1)}@'
            : '$username@');

        return Align(
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: const Offset(13, -53),
            child: SizedBox(
              width: 257,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    backgroundImage:
                    photoUrl.isEmpty ? null : NetworkImage(photoUrl),
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, color: Colors.black38)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name.isEmpty ? 'بدون اسم' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _darkGreen,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          userAsTail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _DynamicFriendAction(
                    friendUid: userDoc.id,
                    friendName: name.isEmpty ? 'الصديق' : name,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// ===============================
/// Dynamic friend button: friend / pending / add
/// ===============================
class _DynamicFriendAction extends StatelessWidget {
  final String friendUid;
  final String friendName;
  const _DynamicFriendAction({
    required this.friendUid,
    required this.friendName,
  });

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return const SizedBox.shrink();

    final myFriendDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(me.uid)
        .collection('friends')
        .doc(friendUid);

    final pendingReqDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('friendRequests')
        .doc(me.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myFriendDoc.snapshots(),
      builder: (context, friendSnap) {
        final isFriend = friendSnap.data?.exists == true;
        if (isFriend) {
          return _FriendBadge(
            isFollowing: true,
            onTap: () =>
                _HeaderAndTabs._confirmUnfollow(context, friendName, friendUid),
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: pendingReqDoc.snapshots(),
          builder: (context, reqSnap) {
            final waiting = reqSnap.data?.exists == true;
            if (waiting) {
              return InkWell(
                onTap: () => _HeaderAndTabs.confirmCancelPendingRequest(
                  context,
                  friendUid,
                ),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _confirm.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'بانتظار القبول ⏳',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _confirm,
                    ),
                  ),
                ),
              );
            }
            return GestureDetector(
              onTap: () => _HeaderAndTabs.sendFriendRequest(context, friendUid),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _confirm,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'إضافة',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// ===============================
/// White tab bar shell
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
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
        insets: EdgeInsets.symmetric(horizontal: 1),
      ),
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      tabs: [
        Tab(text: 'الإحصائيات'),
        Tab(text: 'التقييمات'),
        Tab(text: 'الأندية'),
      ],
    );
  }
}

/// ===============================
/// Private account locked view
/// ===============================
class _PrivateAccountView extends StatelessWidget {
  const _PrivateAccountView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 280, 24, 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 42, color: _darkGreen),
              SizedBox(height: 12),
              Text(
                'هذا الحساب خاص',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _darkGreen,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'أرسل طلب إضافة وانتظر القبول حتى تتمكن من مشاهدة الملف الشخصي.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// Friend operations (send request / unfriend / cancel pending)
/// ===============================
class _HeaderAndTabs {
  static Future<void> sendFriendRequest(
      BuildContext context,
      String friendUid,
      ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final reqRef = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('friendRequests')
        .doc(me.uid);

    try {
      await reqRef.set({
        'fromUid': me.uid,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _showAppSnack(context, 'تم إرسال الطلب');
    } catch (e) {
      _showAppSnack(context, 'تعذّر الإرسال: $e', icon: Icons.error_outline);
    }
  }

  static Future<void> _confirmUnfollow(
      BuildContext context,
      String friendName,
      String friendUid,
      ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

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
                Text(
                  ' تأكيد إلغاء متابعة $friendName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'هل أنت متأكد أنك تريد إزالة $friendName من قائمة أصدقائك؟',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
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
                      backgroundColor: Color(0xFFF2F2F2),
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

    final myFriend = fs
        .collection('users')
        .doc(myUid)
        .collection('friends')
        .doc(friendUid);
    final hisFriend = fs
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(myUid);

    final reqHimHasFromMe = fs
        .collection('users')
        .doc(friendUid)
        .collection('friendRequests')
        .doc(myUid);
    final reqMeHasFromHim = fs
        .collection('users')
        .doc(myUid)
        .collection('friendRequests')
        .doc(friendUid);

    batch.delete(myFriend);
    batch.delete(hisFriend);
    batch.delete(reqHimHasFromMe);
    batch.delete(reqMeHasFromHim);

    await batch.commit();
  }

  static Future<void> confirmCancelPendingRequest(
      BuildContext context,
      String friendUid,
      ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

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
                  'تأكيد إلغاء طلب الإضافة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد أنك تريد إلغاء طلب الإضافة؟',
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
                      backgroundColor: Color(0xFFF2F2F2),
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

    if (ok == true) {
      await _cancelPendingRequest(me.uid, friendUid);
      if (!context.mounted) return;
      _showAppSnack(context, 'تم إلغاء طلب الإضافة');
    }
  }

  static Future<void> _cancelPendingRequest(
      String myUid,
      String friendUid,
      ) async {
    final fs = FirebaseFirestore.instance;
    final reqRef = fs
        .collection('users')
        .doc(friendUid)
        .collection('friendRequests')
        .doc(myUid);

    await reqRef.delete();
  }
}

/// ===============================
/// Stats tab (streak and listened books)
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

  @override
  Widget build(BuildContext context) {
    final statsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(friendUid)
        .collection('stats')
        .doc('main');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: statsRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};

        final best = (data['bestStreak'] ?? 0) as int;
        final current = (data['currentStreak'] ?? 0) as int;
        final completed = (data['completedBooksCount'] ?? 0) as int;

        final items = <Widget>[
          _StatCard(
            icon: '🏅',
            text: 'أفضل مداومة: ${_formatArabicCount(best, "يوم", "أيام")}',
          ),
          _StatCard(
            icon: '🔥',
            text: 'المداومة الحالية: ${_formatArabicCount(current, "يوم", "أيام")}',
          ),
          _StatCard(
            icon: '📚',
            text: 'الكتب المنجزة: ${_formatArabicCount(completed, "كتاب", "كتب")}',
          ),
          _OpenCompletedLibraryCard(friendUid: friendUid),
        ];

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 300, 16, 24),
          itemBuilder: (_, i) => items[i],
          separatorBuilder: (_, __) => const SizedBox(height: 32),
          itemCount: items.length,
        );
      },
    );
  }
}

String _toArabicDigits(int number) {
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  var text = number.toString();
  for (int i = 0; i < western.length; i++) {
    text = text.replaceAll(western[i], eastern[i]);
  }
  return text;
}

String _arabicWord(int count, String singular, String plural) {
  return count == 1 ? singular : plural;
}

String _formatArabicCount(int count, String singular, String plural) {
  final numText = _toArabicDigits(count);
  final word = _arabicWord(count, singular, plural);
  return '$numText $word';
}

Future<int> _getCompletedBooksCount(String friendUid) async {
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(friendUid)
      .collection('library')
      .where('isCompleted', isEqualTo: true)
      .get();

  return snap.docs.length;
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String text;
  const _StatCard({required this.icon, required this.text});

  static const Color _card = Color(0xFFC9DABF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: _darkGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenCompletedLibraryCard extends StatelessWidget {
  final String friendUid;
  const _OpenCompletedLibraryCard({required this.friendUid});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FriendCompletedLibraryPage(friendUid: friendUid),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFC9DABF),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '📖', // أيقونة مختلفة عن اللي فوق
              style: TextStyle(fontSize: 22),
            ),
            Expanded(
              child: Text(
                'عرض الكتب المنجزة',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: _darkGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow {
  final String icon;
  final String text;
  const _StatRow({required this.icon, required this.text});
}

/// ===============================
/// Friend completed library page
/// ===============================
class FriendCompletedLibraryPage extends StatelessWidget {
  final String friendUid;
  const FriendCompletedLibraryPage({super.key, required this.friendUid});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/backttt.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 130,
              leading: Padding(
                padding: const EdgeInsets.only(top: 30, right: 8),
                child: IconButton(
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _midGreen,
                    size: 20,
                  ),
                ),
              ),
              centerTitle: true,
              title: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(friendUid)
                      .snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data() ?? {};
                    final name = (data['name'] ?? 'المستخدم') as String;

                    return Text(
                      'مكتبة $name المنجزة',
                      style: const TextStyle(
                        color: _darkGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    );
                  },
                ),
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 38),
                child: _FriendCompletedShelf(uid: friendUid),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendLibraryBook {
  final String id;
  final String title;
  final ImageProvider? cover;
  final String type;
  final bool isCompleted;

  const _FriendLibraryBook({
    required this.id,
    required this.title,
    this.cover,
    this.type = 'book',
    this.isCompleted = false,
  });
}

class _FriendCompletedShelf extends StatefulWidget {
  final String uid;
  const _FriendCompletedShelf({required this.uid});

  @override
  State<_FriendCompletedShelf> createState() => _FriendCompletedShelfState();
}

class _FriendCompletedShelfState extends State<_FriendCompletedShelf> {
  List<_FriendLibraryBook> _lastNonEmpty = const [];

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('library')
        .where('isCompleted', isEqualTo: true)
        .orderBy('addedAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          if (_lastNonEmpty.isNotEmpty) {
            return _FriendShelfView(books: _lastNonEmpty);
          }
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          if (_lastNonEmpty.isNotEmpty) {
            return _FriendShelfView(books: _lastNonEmpty);
          }
          return const Center(
            child: Text(
              'لا توجد كتب مكتملة بعد',
              style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w700),
            ),
          );
        }

        final docs = snap.data?.docs ?? const [];
        final books = docs.map((d) {
          final m = d.data();
          final title = (m['title'] ?? '') as String;
          final cover = (m['coverUrl'] ?? '') as String;
          final type = (m['type'] ?? 'book') as String;
          final isCompleted = (m['isCompleted'] ?? false) as bool;

          return _FriendLibraryBook(
            id: d.id,
            title: title.isEmpty ? 'كتاب' : title,
            cover: cover.isNotEmpty ? NetworkImage(cover) : null,
            type: type,
            isCompleted: isCompleted,
          );
        }).toList();

        if (books.isNotEmpty) {
          _lastNonEmpty = books;
          return _FriendShelfView(books: books);
        }

        return const Center(
          child: Text(
            'لا توجد كتب مكتملة بعد',
            style: TextStyle(color: _darkGreen, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}

class _FriendShelfRect {
  final double leftFrac, rightFrac, topFrac, heightFrac;
  const _FriendShelfRect({
    required this.leftFrac,
    required this.rightFrac,
    required this.topFrac,
    required this.heightFrac,
  });
}

class _FriendShelfView extends StatefulWidget {
  final List<_FriendLibraryBook> books;
  const _FriendShelfView({required this.books});

  @override
  State<_FriendShelfView> createState() => _FriendShelfViewState();
}

class _FriendShelfViewState extends State<_FriendShelfView> {
  static const List<_FriendShelfRect> _shelfRects = [
    _FriendShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.00,
      heightFrac: 0.11,
    ),
    _FriendShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.20,
      heightFrac: 0.11,
    ),
    _FriendShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.40,
      heightFrac: 0.11,
    ),
    _FriendShelfRect(
      leftFrac: 0.18,
      rightFrac: 0.18,
      topFrac: 0.60,
      heightFrac: 0.11,
    ),
  ];

  static const int _perShelf = 4;
  static const int _shelvesPerPage = 4;
  static const int _booksPerPage = _perShelf * _shelvesPerPage;
  static const double _spacing = 1;
  static const double _bookAspect = .25;
  static const double _bookStretch = 1.2;

  final PageController _pageController = PageController();
  late List<List<_FriendLibraryBook>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = _paginate(widget.books, _booksPerPage);
  }

  @override
  void didUpdateWidget(covariant _FriendShelfView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books.length != widget.books.length) {
      _pages = _paginate(widget.books, _booksPerPage);
    }
  }

  List<List<_FriendLibraryBook>> _paginate(
      List<_FriendLibraryBook> list,
      int size,
      ) {
    final pages = <List<_FriendLibraryBook>>[];
    for (var i = 0; i < list.length; i += size) {
      pages.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    if (pages.isEmpty) pages.add(const []);
    return pages;
  }

  List<List<_FriendLibraryBook>> _chunk(
      List<_FriendLibraryBook> list,
      int size,
      ) {
    final chunks = <List<_FriendLibraryBook>>[];
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
                        : const <_FriendLibraryBook>[];

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
                                alignment: const Alignment(0, -2.5),
                                child: _FriendLibraryBookCard(book: book),
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

class _FriendLibraryBookCard extends StatelessWidget {
  final _FriendLibraryBook book;
  const _FriendLibraryBookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);

    return InkWell(
      onTap: () {
        final isPodcast = book.type == 'podcast';

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => isPodcast
                ? PodcastDetailsPage(podcastId: book.id)
                : BookDetailsPage(bookId: book.id),
          ),
        );
      },
      child: Container(
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
          child: book.cover != null
              ? Image(
            image: book.cover!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          )
              : Container(
            width: double.infinity,
            height: double.infinity,
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
    );
  }
}

/// ===============================
/// Reviews tab (friend book reviews)
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
        final reviews = docs
            .map((d) => _FriendReview.fromDoc(d.id, d.data()))
            .toList();

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
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'لا توجد تقييمات بعد',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
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
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
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
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 280, 16, 24),
      children: [
        bone(),
        const SizedBox(height: 10),
        bone(),
        const SizedBox(height: 10),
        bone(),
      ],
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
    if (raw is Timestamp) {
      created = raw.toDate();
    } else if (raw is String) {
      try {
        created = DateTime.tryParse(raw);
      } catch (_) {}
    }

    final title = (data['bookTitle'] ?? data['title']) as String?;
    final cover = (data['bookCover'] ?? data['coverUrl']) as String?;
    final content = (data['text'] ?? data['snippet']) as String?;

    final ratingVal = (() {
      final v = data['rating'];
      if (v is num) return v.toInt();
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null) return p;
      }
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
      decoration: BoxDecoration(
        color: _lightGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (coverUrl != null && coverUrl!.isNotEmpty)
                ? Image.network(
              coverUrl!,
              width: 56,
              height: 72,
              fit: BoxFit.cover,
            )
                : Container(
              width: 56,
              height: 72,
              color: Colors.white.withOpacity(0.6),
              child: const Icon(Icons.menu_book, color: _darkGreen),
            ),
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _darkGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      date,
                      style: const TextStyle(fontSize: 12, color: _darkGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: List.generate(5, (i) {
                    final filled = i < stars;
                    return Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        filled ? Icons.star : Icons.star_border,
                        size: 18,
                        color: _darkGreen,
                      ),
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
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: _darkGreen,
                      ),
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
/// Clubs tab: shows friend clubs with your join state
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

        if (snap.hasError) {
          return Center(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 280, 16, 24),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                border: Border.all(color: Colors.red.withOpacity(0.25)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'حدث خطأ أثناء جلب الأندية.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        final clubs = snap.data?.docs ?? const [];

        if (clubs.isEmpty) {
          return _clubsEmptyBox();
        }

        return FutureBuilder<List<bool>>(
          future: _loadMembershipForClubs(clubs, friendUid),
          builder: (context, memSnap) {
            if (memSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (memSnap.hasError) {
              return Center(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 280, 16, 24),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'حدث خطأ أثناء التحقق من عضوية الأندية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }

            final membership =
                memSnap.data ?? List<bool>.filled(clubs.length, false);

            final visibleClubs =
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (int i = 0; i < clubs.length; i++) {
              if (membership[i]) {
                visibleClubs.add(clubs[i]);
              }
            }

            if (visibleClubs.isEmpty) {
              return _clubsEmptyBox();
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 280, 16, 24),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                physics: const ClampingScrollPhysics(),
                itemCount: visibleClubs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final clubDoc = visibleClubs[i];
                  final clubId = clubDoc.id;
                  final data = clubDoc.data();
                  final title = (data['title'] ?? 'نادي بدون اسم') as String;
                  final desc = (data['description'] ?? '') as String?;
                  final cat = (data['category'] ?? '') as String?;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _darkGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (desc != null && desc.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            style: const TextStyle(
                              color: Colors.black87,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (cat != null && cat.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'الفئة: $cat',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _JoinOrOpenButtonFD(
                            clubId: clubId,
                            clubTitle: title,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  static Widget _clubsEmptyBox() {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 280, 16, 24),
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'لم يشترك في نادي بعد',
          style: TextStyle(
            color: Colors.black54,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static Future<List<bool>> _loadMembershipForClubs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> clubs,
      String friendUid,
      ) async {
    final fs = FirebaseFirestore.instance;

    final futures = clubs.map((clubDoc) {
      return fs
          .collection('clubs')
          .doc(clubDoc.id)
          .collection('members')
          .doc(friendUid)
          .get();
    }).toList();

    final snapshots = await Future.wait(futures);
    return snapshots.map((s) => s.exists).toList();
  }
}

/// ===============================
/// Join / open chat button in friend clubs tab
/// ===============================
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
        .collection('clubs')
        .doc(widget.clubId)
        .collection('members')
        .doc(me.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: myMemberDocStream,
      builder: (context, snap) {
        final isMember = snap.data?.exists == true;

        final String label = isMember ? 'أنت جزء من النادي' : 'انضم';
        final Color bg = isMember ? Colors.white : _confirm;
        final BorderSide side = isMember
            ? const BorderSide(color: _darkGreen, width: 1.2)
            : BorderSide.none;

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
                      .collection('clubs')
                      .doc(widget.clubId)
                      .collection('members')
                      .doc(me.uid)
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
              foregroundColor: _darkGreen,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: side,
              ),
            ),
            child: _busy
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_darkGreen),
              ),
            )
                : Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
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
        decoration: BoxDecoration(
          color: _confirm.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: const [
            Icon(Icons.verified, size: 18, color: _confirm),
            SizedBox(width: 6),
            Text(
              'صديق',
              style: TextStyle(fontWeight: FontWeight.w700, color: _confirm),
            ),
          ],
        ),
      ),
    );
  }
}