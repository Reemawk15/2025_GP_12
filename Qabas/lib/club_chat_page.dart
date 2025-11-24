import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'firestore_clubs_service.dart';
import 'friend_details_page.dart';

class ClubChatPage extends StatefulWidget {
  final String clubId;
  final String clubTitle;
  final bool showWelcome; // جديد

  const ClubChatPage({
    super.key,
    required this.clubId,
    required this.clubTitle,
    this.showWelcome = true, // اليوزر الافتراضي
  });

  @override
  State<ClubChatPage> createState() => _ClubChatPageState();
}

class _ClubChatPageState extends State<ClubChatPage> {
  static const Color _midGreen    = Color(0xFF2F5145);
  static const Color _confirm     = Color(0xFF6F8E63);
  static const Color _bubbleMe    = Color(0xFFE6F0E0);
  static const Color _bubbleOther = Color(0xFFFFEEF1);
  static const Color _titleColor  = Color(0xFF0E3A2C);

  final _controller = TextEditingController();
  late final Future<({String name, String? photoUrl})> _myProfileFuture;

  @override
  void initState() {
    super.initState();
    _myProfileFuture = _resolveCurrentUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 90,
          centerTitle: false,
          // خليه صفر أو قريب منه عشان العنوان يجي ملاصق لمنطقة التايتل
          titleSpacing: 0,
          // نخلي مساحة كافية للسهم
          leadingWidth: 56,
          title: widget.showWelcome
              ? FutureBuilder<({String name, String? photoUrl})>(
            future: _myProfileFuture,
            builder: (context, snap) {
              final userName = (snap.data?.name ?? '').trim().isEmpty
                  ? 'ضيفنا الكريم'
                  : snap.data!.name;

              return Padding(
                // نرفع التايتل شوي لتحت البار
                padding: const EdgeInsets.only(top: 16, right: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'حللت أهلاً ووطِئت سهلاً $userName',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: _titleColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'مرحبًا بك في نادي ${widget.clubTitle}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: _titleColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          )
              : Padding(
            padding: const EdgeInsets.only(top: 16, right: 24), // 👈 هنا زدتها
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'نادي ${widget.clubTitle}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _titleColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          leading: Padding(
            padding: const EdgeInsets.only(top: 40, right: 8),
            child: IconButton(
              tooltip: 'رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF2F5145),
                size: 20,
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/images/clubs2.png', fit: BoxFit.cover),
            ),
            Column(
              children: [
                const SizedBox(height: 140),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirestoreClubsService.instance
                        .streamMessages(widget.clubId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(child: Text('ابدأ المحادثة…'));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final m = docs[i].data();
                          final mine = m['uid'] == uid;
                          final text = (m['text'] ?? '') as String;
                          final senderUid = (m['uid'] ?? '') as String;

                          final fallbackName  = (m['displayName'] ?? '').toString().trim();
                          final fallbackPhoto = (m['photoUrl'] ?? '').toString().trim();

                          return _ChatRow(
                            mine: mine,
                            uid: senderUid,
                            text: text,
                            fallbackName: fallbackName.isEmpty ? null : fallbackName,
                            fallbackPhotoUrl: fallbackPhoto.isEmpty ? null : fallbackPhoto,
                            bubbleColor: mine ? _bubbleMe : _bubbleOther,
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 44,
                          child: TextButton(
                            onPressed: _send,
                            style: TextButton.styleFrom(
                              backgroundColor: _confirm,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'إرسال',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: 'اكتب رسالتك...',
                                border: InputBorder.none,
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<({String name, String? photoUrl})> _resolveCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser!;
    String name = (user.displayName ?? '').trim();
    String? photo = user.photoURL;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        name = (data['name'] ??
            data['fullName'] ??
            data['username'] ??
            name ??
            '')
            .toString()
            .trim();
        photo = (data['photoUrl'] ?? data['avatarUrl'] ?? photo)?.toString();
      }
    } catch (_) {
      // تجاهل الأخطاء
    }

    if (name.isEmpty) name = 'بدون اسم';
    return (name: name, photoUrl: photo);
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;

    final profile = await _resolveCurrentUserProfile();
    final user = FirebaseAuth.instance.currentUser!;

    await FirestoreClubsService.instance.sendMessage(
      clubId: widget.clubId,
      uid: user.uid,
      text: t,
      displayName: profile.name,
      photoUrl: profile.photoUrl,
    );
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _ChatRow extends StatelessWidget {
  final bool mine;
  final String uid;
  final String text;
  final String? fallbackName;
  final String? fallbackPhotoUrl;
  final Color bubbleColor;

  const _ChatRow({
    required this.mine,
    required this.uid,
    required this.text,
    required this.bubbleColor,
    this.fallbackName,
    this.fallbackPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    // نسمع لتغيّر بيانات المستخدم من users/{uid}
    return StreamBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        String name = fallbackName ?? '';
        String? photoUrl = fallbackPhotoUrl;

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data()!;
          name = (data['name'] ??
              data['fullName'] ??
              data['username'] ??
              name)
              .toString()
              .trim();
          photoUrl =
              (data['photoUrl'] ?? data['avatarUrl'] ?? photoUrl)
                  ?.toString();
        }

        if (name.isEmpty) name = 'مستخدم';

        final avatar = CircleAvatar(
          radius: 16,
          backgroundColor: Colors.white,
          backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
              ? NetworkImage(photoUrl!)
              : null,
          child: (photoUrl == null || photoUrl!.isEmpty)
              ? Text(
            name.isNotEmpty ? name.characters.first : 'ش',
            style: const TextStyle(color: Colors.black54),
          )
              : null,
        );

        final tappableAvatar = GestureDetector(
          onTap: () {
            if (mine || uid.isEmpty) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FriendDetailsPage(friendUid: uid),
              ),
            );
          },
          child: avatar,
        );

        final bubble = Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: mine
                ? [
              bubble,
              const SizedBox(width: 8),
              tappableAvatar,
            ]
                : [
              tappableAvatar,
              const SizedBox(width: 8),
              bubble,
            ],
          ),
        );
      },
    );
  }
}