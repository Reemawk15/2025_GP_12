import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'friend_details_page.dart';

/// =====================
/// Spacing quick controls
/// =====================
const double kFriendsTopPadding   = 260;
const double kRequestsTopPadding  = 260;
const double kSearchBarTopPadding = 270;
const double kBackArrowTopPadding = 45;

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);

  /// Unified SnackBar helper for this page
  static void _showAppSnack(BuildContext context, String message, {IconData icon = Icons.check_circle}) {
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

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.only(top: kBackArrowTopPadding, right: 8),
              child: IconButton(
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _midGreen, size: 20),
              ),
            ),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(80),
              child: _TabbarContainer(),
            ),
          ),
          body: const TabBarView(
            physics: BouncingScrollPhysics(),
            children: [
              _FriendsListTab(background: 'assets/images/friends1.png'),
              _RequestsTab(background: 'assets/images/friends2.png'),
              _SearchTab(background: 'assets/images/friends2.png'),
            ],
          ),
        ),
      ),
    );
  }
}

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
        child: const _FriendsTabBar(),
      ),
    );
  }
}

class _FriendsTabBar extends StatelessWidget {
  const _FriendsTabBar();

  static const Color _darkGreen = Color(0xFF0E3A2C);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      labelColor: _darkGreen,
      unselectedLabelColor: Colors.black54,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(width: 4, color: _darkGreen),
        insets: EdgeInsets.symmetric(horizontal: 24),
      ),
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      tabs: const [
        Tab(text: 'أصدقائي'),
        Tab(text: 'طلبات الإضافة'),
        Tab(text: 'البحث عن أصدقاء'),
      ],
    );
  }
}

// ======================== Tab: My Friends ========================
class _FriendsListTab extends StatelessWidget {
  final String background;
  const _FriendsListTab({required this.background});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('الرجاء تسجيل الدخول.'));
    }

    final friendsRef = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('friends')
        .orderBy('since', descending: true);

    return Stack(
      children: [
        Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: friendsRef.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return const Center(child: Text('لا يوجد لديك أصدقاء بعد 📭', style: TextStyle(color: Colors.black54)));
            }

            final friendUids = snap.data!.docs.map((d) => d.id).toList();

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, kFriendsTopPadding, 16, 24),
              itemBuilder: (_, i) {
                final friendUid = friendUids[i];
                return _FriendTileFromUid(
                  friendUid: friendUid,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FriendDetailsPage(friendUid: friendUid)),
                    );
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: friendUids.length,
            );
          },
        ),
      ],
    );
  }
}

// ======================== Tab: Friend Requests ========================
class _RequestsTab extends StatelessWidget {
  final String background;
  const _RequestsTab({required this.background});

  static const Color _confirm = Color(0xFF6F8E63);
  static const Color _danger  = Color(0xFFB64B4B);

  Future<void> _accept(BuildContext context, String fromUid) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final batch = FirebaseFirestore.instance.batch();

    final myFriends = FirebaseFirestore.instance.collection('users').doc(myUid).collection('friends').doc(fromUid);
    final hisFriends = FirebaseFirestore.instance.collection('users').doc(fromUid).collection('friends').doc(myUid);
    final myReq = FirebaseFirestore.instance.collection('users').doc(myUid).collection('friendRequests').doc(fromUid);

    batch.set(myFriends, {'since': FieldValue.serverTimestamp()});
    batch.set(hisFriends, {'since': FieldValue.serverTimestamp()});
    batch.delete(myReq);

    try {
      await batch.commit();
      FriendsPage._showAppSnack(context, 'تم قبول الطلب ✅');
    } catch (e) {
      FriendsPage._showAppSnack(context, 'تعذّر القبول: $e', icon: Icons.error_outline);
    }
  }

  Future<void> _decline(BuildContext context, String fromUid) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final reqRef = FirebaseFirestore.instance.collection('users').doc(myUid).collection('friendRequests').doc(fromUid);
    try {
      await reqRef.delete();
      FriendsPage._showAppSnack(context, 'تم رفض الطلب');
    } catch (e) {
      FriendsPage._showAppSnack(context, 'تعذّر الرفض: $e', icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('الرجاء تسجيل الدخول.'));
    }

    final requestsRef = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('friendRequests')
        .orderBy('createdAt', descending: true);

    return Stack(
      children: [
        Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: requestsRef.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return const Center(child: Text('لا توجد طلبات ً ✨', style: TextStyle(color: Colors.black54)));
            }

            final fromUids = snap.data!.docs.map((d) => d.id).toList();

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, kRequestsTopPadding, 16, 24),
              itemBuilder: (_, i) {
                final fromUid = fromUids[i];
                return _FriendTileFromUid(
                  friendUid: fromUid,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TinyActionButton(label: 'قبول', color: _confirm, onTap: () => _accept(context, fromUid)),
                      const SizedBox(width: 8),
                      _TinyActionButton(label: 'رفض', color: _danger, onTap: () => _decline(context, fromUid)),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FriendDetailsPage(friendUid: fromUid)),
                    );
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: fromUids.length,
            );
          },
        ),
      ],
    );
  }
}

// ======================== Tab: Search Friends (with Pending) ========================
class _SearchTab extends StatefulWidget {
  final String background;
  const _SearchTab({required this.background});

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<_FriendUser> _results = const [];

  // Tracks whether a search was performed with a non-empty query
  bool _hasSearched = false;

  // Normalize Arabic text for better matching
  String normalize(String s) => s
      .trim().toLowerCase()
      .replaceAll('ـ', '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه').replaceAll('ى', 'ي');

  // Actual search logic with pending detection
  Future<void> _onSearch(String raw) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    final q = normalize(raw);
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _hasSearched = false; // no query submitted
      });
      return;
    }

    setState(() {
      _loading = true;
      _hasSearched = true; // mark that a search attempt happened
    });

    try {
      final fs = FirebaseFirestore.instance;

      // Current friends
      final myFriendsSnap = await fs.collection('users').doc(me.uid).collection('friends').get();
      final myFriends = myFriendsSnap.docs.map((d) => d.id).toSet();

      // Incoming requests to me
      final myIncomingReqsSnap = await fs.collection('users').doc(me.uid).collection('friendRequests').get();
      final incomingFrom = myIncomingReqsSnap.docs.map((d) => d.id).toSet();

      // Prefix queries
      Future<QuerySnapshot<Map<String, dynamic>>> qBy(String field) {
        return fs.collection('users')
            .orderBy(field)
            .startAt([q]).endAt(['$q\uf8ff'])
            .limit(25)
            .get();
      }

      List<QuerySnapshot<Map<String, dynamic>>> snaps = [];
      try {
        snaps = await Future.wait([qBy('usernameLower'), qBy('nameLower')]);
      } catch (_) {
        snaps = [];
      }

      final Map<String, _FriendUser> map = {};

      void addDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final uid = d.id;
        if (uid == me.uid) return;
        if (myFriends.contains(uid)) return;     // already a friend
        if (incomingFrom.contains(uid)) return;  // already sent me a request

        final data = d.data();
        final name     = (data['name'] ?? '') as String;
        final username = (data['username'] ?? '') as String;
        final photoUrl = (data['photoUrl'] as String?) ?? '';

        final handle = username.isEmpty ? '' : (username.startsWith('@') ? username : '@$username');

        map[uid] = _FriendUser(
          uid: uid,
          name: name,
          handle: handle,
          photoUrl: photoUrl.isEmpty ? null : photoUrl,
        );
      }

      for (final s in snaps) {
        for (final d in s.docs) addDoc(d);
      }

      // Fallback: client-side filter if nothing matched
      if (map.isEmpty) {
        final allSnap = await fs.collection('users').limit(200).get();
        for (final d in allSnap.docs) {
          final uid = d.id;
          if (uid == me.uid) continue;
          if (myFriends.contains(uid)) continue;
          if (incomingFrom.contains(uid)) continue;

          final data = d.data();
          final name     = (data['name'] ?? '') as String;
          final username = (data['username'] ?? '') as String;

          final nameN = normalize(name);
          final userN = normalize(username);

          if (nameN.contains(q) || userN.contains(q)) {
            final photoUrl = (data['photoUrl'] as String?) ?? '';
            final handle = username.isEmpty ? '' : (username.startsWith('@') ? username : '@$username');

            map[uid] = _FriendUser(
              uid: uid,
              name: name,
              handle: handle,
              photoUrl: photoUrl.isEmpty ? null : photoUrl,
            );
          }
        }
      }

      // Mark "pending" (outgoing request) for results if exists
      final uids = map.keys.toList();
      if (uids.isNotEmpty) {
        final futures = uids.map((otherUid) {
          final doc = fs.collection('users').doc(otherUid).collection('friendRequests').doc(me.uid);
          return doc.get().then((snap) => MapEntry(otherUid, snap.exists));
        }).toList();

        final checks = await Future.wait(futures);
        for (final e in checks) {
          if (e.value) {
            final current = map[e.key]!;
            map[e.key] = current.copyWith(pending: true);
          }
        }
      }

      setState(() => _results = map.values.toList());
    } catch (e) {
      if (!mounted) return;
      FriendsPage._showAppSnack(context, 'فشل البحث: $e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Send friend request (keep result item but toggle to pending)
  Future<void> _sendRequest(String toUid) async {
    final me = FirebaseAuth.instance.currentUser!;
    final reqRef = FirebaseFirestore.instance
        .collection('users').doc(toUid).collection('friendRequests').doc(me.uid);

    try {
      await reqRef.set({'fromUid': me.uid, 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      setState(() {
        _results = _results.map((x) => x.uid == toUid ? x.copyWith(pending: true) : x).toList();
      });

      FriendsPage._showAppSnack(context, 'تم إرسال الطلب ✅');
    } catch (e) {
      FriendsPage._showAppSnack(context, 'تعذّر الإرسال: $e', icon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.asset(widget.background, fit: BoxFit.cover)),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, kSearchBarTopPadding, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(22),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.black45),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'ابحث بالاسم ', border: InputBorder.none,
                        ),
                        onSubmitted: _onSearch,
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        // Clear query and results; also reset search state
                        _controller.clear();
                        setState(() {
                          _results = const [];
                          _hasSearched = false;
                        });
                      },
                      icon: const Icon(Icons.close, color: Colors.black38),
                      tooltip: 'مسح',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: _results.isEmpty
                // Show a contextual message:
                // - If the user has searched and found nothing: show classical Arabic message.
                // - Otherwise: show the initial prompt.
                    ? Center(
                  child: Text(
                    _hasSearched ? 'لا يوجد أحد بهذا الاسم.' : 'ابدأ البحث عن أصدقائك ✨',
                    style: const TextStyle(color: Colors.black54),
                  ),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemBuilder: (_, i) {
                    final f = _results[i];
                    return _FriendCard(
                      name: f.name.isEmpty ? 'بدون اسم' : f.name,
                      handle: f.handle,
                      avatar: (f.photoUrl == null) ? null : NetworkImage(f.photoUrl!),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FriendDetailsPage(friendUid: f.uid)),
                        );
                      },
                      trailing: f.pending
                          ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6F8E63).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'بانتظار القبول ⏳',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6F8E63)),
                        ),
                      )
                          : _TinyActionButton(
                        label: 'إضافة',
                        color: const Color(0xFF6F8E63),
                        onTap: () => _sendRequest(f.uid),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemCount: _results.length,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ========= Result user model (with pending) =========
class _FriendUser {
  final String uid;
  final String name;
  final String handle;
  final String? photoUrl;
  final bool pending; // Whether there is an outgoing request awaiting approval

  _FriendUser({
    required this.uid,
    required this.name,
    required this.handle,
    this.photoUrl,
    this.pending = false,
  });

  _FriendUser copyWith({bool? pending}) => _FriendUser(
    uid: uid,
    name: name,
    handle: handle,
    photoUrl: photoUrl,
    pending: pending ?? this.pending,
  );
}

// ======================== Generic friend card (visual only) ========================
class _FriendCard extends StatelessWidget {
  final String name;
  final String handle;
  final ImageProvider? avatar;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _FriendCard({required this.name, required this.handle, this.avatar, this.trailing, this.onTap});

  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _darkGreen  = Color(0xFF0E3A2C);

  @override
  Widget build(BuildContext context) {
    final userTail = handle.startsWith('@') ? '${handle.substring(1)}@' : handle.isNotEmpty ? '$handle@' : '';

    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.88),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          backgroundImage: avatar,
          child: avatar == null ? const Icon(Icons.person, color: Colors.black38) : null,
        ),
        title: Text(
          name,
          style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w700, fontSize: 14.5),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(userTail, style: const TextStyle(color: Colors.black54, fontSize: 12.5), overflow: TextOverflow.ellipsis),
        trailing: trailing,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
    );
  }
}

/// Fetch and render a friend card by UID directly from Firestore
class _FriendTileFromUid extends StatelessWidget {
  final String friendUid;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _FriendTileFromUid({required this.friendUid, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(friendUid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: 66, alignment: Alignment.centerLeft,
            child: const Padding(
              padding: EdgeInsetsDirectional.only(start: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snap.data!.data()!;
        final name      = (data['name'] ?? '') as String;
        final rawUser   = (data['username'] ?? data['handle'] ?? '') as String;
        final photoUrl  = (data['photoUrl'] ?? '') as String?;

        final handle = rawUser;

        return _FriendCard(
          name: name.isEmpty ? 'بدون اسم' : name,
          handle: handle,
          avatar: (photoUrl == null || photoUrl.isEmpty) ? null : NetworkImage(photoUrl),
          trailing: trailing,
          onTap: onTap,
        );
      },
    );
  }
}

// ======================== Tiny action button (Accept / Decline / Add) ========================
class _TinyActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TinyActionButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
