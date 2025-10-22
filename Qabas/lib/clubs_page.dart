import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'club_chat_page.dart';
import 'firestore_clubs_service.dart';

/// =====================
/// تحكّم بالمسافات
/// =====================
const double kBackArrowTopPadding = 55;
const double kTabTopPadding = 30;
const double kTabBarHeight = 40;
const double kTabBottomPadding = 35;

const double kListTopPadding = 230;
const double kFormTopPadding = 230;
const double kMyRequestsTopPadding = 240;

/// =====================
/// ألوان الهوية
/// =====================
const Color _darkGreen  = Color(0xFF0E3A2C);
const Color _midGreen   = Color(0xFF2F5145);
const Color _lightGreen = Color(0xFFC9DABF);
const Color _confirm    = Color(0xFF6F8E63);
const Color _danger     = Color(0xFFB64B4B);
const Color _pending    = Color(0xFFB38A1B);

class ClubsPage extends StatelessWidget {
  const ClubsPage({super.key});

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
            toolbarHeight: 90,
            leadingWidth: 56,
            leading: Padding(
              padding: const EdgeInsets.only(top: kBackArrowTopPadding, right: 8),
              child: IconButton(
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _midGreen, size: 20),
              ),
            ),
            bottom: const _TabbarContainer(
              topPadding: kTabTopPadding,
              barHeight: kTabBarHeight,
              bottomPadding: kTabBottomPadding,
            ),
          ),
          body: const TabBarView(
            physics: BouncingScrollPhysics(),
            children: [
              _ClubsListTab(background: 'assets/images/clubs1.png'),
              _CreateRequestTab(background: 'assets/images/clubs1.png'),
              _MyRequestsTab(background: 'assets/images/clubs1.png'),
            ],
          ),
        ),
      ),
    );
  }
}

/// =====================
/// شريط التبويبات
/// =====================
class _TabbarContainer extends StatelessWidget implements PreferredSizeWidget {
  final double topPadding;
  final double barHeight;
  final double bottomPadding;

  const _TabbarContainer({
    super.key,
    this.topPadding = 40,
    this.barHeight = 50,
    this.bottomPadding = 12,
  });

  @override
  Size get preferredSize => Size.fromHeight(topPadding + barHeight + bottomPadding);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding),
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: const TabBar(
          labelColor: _darkGreen,
          unselectedLabelColor: Colors.black54,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(width: 4, color: _darkGreen),
            insets: EdgeInsets.symmetric(horizontal: 24),
          ),
          labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'الأندية'),
            Tab(text: 'طلب إنشاء نادي'),
            Tab(text: 'طلباتي'),
          ],
        ),
      ),
    );
  }
}

/// =====================
/// تبويب: الأندية (من Firestore)
/// الترتيب: اسم النادي (أكبر) -> الوصف -> الفئة -> عدد الأعضاء
/// زر الانضمام يسار ويتحول لـ "أنت جزء من النادي" إذا كنتِ عضوة
/// =====================
class _ClubsListTab extends StatelessWidget {
  final String background;
  const _ClubsListTab({required this.background});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
        StreamBuilder<List<PublicClub>>(
          stream: FirestoreClubsService.instance.streamPublicClubs(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final clubs = snap.data ?? const [];
            if (clubs.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, kListTopPadding, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _lightGreen.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'لا توجد أندية منشورة حتى الآن.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black87),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, kListTopPadding, 16, 24),
              itemBuilder: (_, i) {
                final c = clubs[i];

                // جلب عدد الأعضاء Realtime
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('clubs')
                      .doc(c.id)
                      .collection('members')
                      .snapshots(),
                  builder: (context, memberSnap) {
                    final membersCount = memberSnap.data?.docs.length ?? 0;

                    return Container(
                      decoration: BoxDecoration(
                        color: _lightGreen.withOpacity(0.88),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // اسم النادي (أكبر)
                          Text(
                            c.title,
                            style: const TextStyle(
                              color: _darkGreen,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // الوصف
                          if ((c.description ?? '').isNotEmpty)
                            Text(
                              c.description!,
                              style: const TextStyle(color: Colors.black87, height: 1.35),
                            ),
                          const SizedBox(height: 6),

                          // الفئة
                          if ((c.category ?? '').isNotEmpty)
                            Text(
                              'الفئة: ${c.category!}',
                              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
                            ),
                          const SizedBox(height: 6),

                          // عدد الأعضاء
                          Text(
                            'عدد الأعضاء: $membersCount',
                            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
                          ),

                          const SizedBox(height: 12),

                          // زر الانضمام يسار (في RTL: end = يسار)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _JoinOrOpenButton(clubId: c.id, clubTitle: c.title),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemCount: clubs.length,
            );
          },
        ),
      ],
    );
  }
}

/// زر الانضمام/فتح الشات (ذكي)
/// زر الانضمام/فتح الشات (ذكي) — ألوان حسب الحالة
class _JoinOrOpenButton extends StatefulWidget {
  final String clubId;
  final String clubTitle;
  const _JoinOrOpenButton({required this.clubId, required this.clubTitle});

  @override
  State<_JoinOrOpenButton> createState() => _JoinOrOpenButtonState();
}

class _JoinOrOpenButtonState extends State<_JoinOrOpenButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final memberDocStream = FirebaseFirestore.instance
        .collection('clubs')
        .doc(widget.clubId)
        .collection('members')
        .doc(uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: memberDocStream,
      builder: (context, snap) {
        final isMember = (snap.data?.exists ?? false);

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
                  await FirestoreClubsService.instance.joinClub(
                    clubId: widget.clubId,
                    uid: uid,
                  );
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
              foregroundColor: _darkGreen, // النص داكن (دارك قرين) بالحالتين
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: side,
              ),
            ),
            child: _busy
                ? const SizedBox(
              width: 21,
              height: 21,
              child: CircularProgressIndicator(
                strokeWidth: 1,
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

/// =====================
/// تبويب: طلب إنشاء نادي
/// =====================
class _CreateRequestTab extends StatefulWidget {
  final String background;
  const _CreateRequestTab({required this.background});

  @override
  State<_CreateRequestTab> createState() => _CreateRequestTabState();
}

class _CreateRequestTabState extends State<_CreateRequestTab> {
  final _titleCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _mentorCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  String? _category;
  bool _isValid = false;

  final _categories = const [
    'الثقافة الإسلامية',
    'الآداب',
    'العلوم',
    'تطوير الذات',
    'علاقات إنسانية',
  ];

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_recomputeValid);
    _descCtrl.addListener(_recomputeValid);
  }

  void _recomputeValid() {
    final ok = _titleCtrl.text.trim().isNotEmpty &&
        _descCtrl.text.trim().isNotEmpty &&
        (_category != null && _category!.trim().isNotEmpty);
    if (ok != _isValid) setState(() => _isValid = ok);
  }

  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.asset(widget.background, fit: BoxFit.cover)),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, kFormTopPadding, 16, 24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _RequiredNote(),

                const _FieldLabel(text: 'عنوان النادي', requiredMark: true),
                _OutlinedInput(
                  hint: 'مثال: نادي القراءة الأسبوعي',
                  controller: _titleCtrl,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل إجباري' : null,
                ),
                const SizedBox(height: 14),

                const _FieldLabel(text: 'وصف قصير', requiredMark: true),
                _OutlinedInput(
                  hint: 'عرّف النادي وهدفه بإيجاز',
                  controller: _descCtrl,
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل إجباري' : null,
                ),
                const SizedBox(height: 14),

                const _FieldLabel(text: 'الفئة', requiredMark: true),
                _DropdownInput(
                  value: _category,
                  hint: 'اختر فئة',
                  items: _categories,
                  onChanged: (v) {
                    setState(() => _category = v);
                    _recomputeValid();
                  },
                  validator: (v) => (v == null || v.isEmpty) ? 'الرجاء اختيار فئة' : null,
                ),
                const SizedBox(height: 14),

                const _FieldLabel(text: 'اسم المشرف (اختياري)'),
                _OutlinedInput(
                  hint: 'يمكن تركه فارغًا',
                  controller: _mentorCtrl,
                ),
                const SizedBox(height: 14),

                const _FieldLabel(text: 'ملاحظات (اختياري)'),
                _OutlinedInput(
                  hint: 'أي تفاصيل إضافية',
                  controller: _notesCtrl,
                  maxLines: 3,
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isValid
                        ? () async {
                      if (!(_formKey.currentState?.validate() ?? false)) return;

                      final uid = FirebaseAuth.instance.currentUser!.uid;
                      await FirestoreClubsService.instance.submitRequest(
                        uid: uid,
                        title: _titleCtrl.text,
                        description: _descCtrl.text,
                        category: _category!,
                        ownerName: _mentorCtrl.text.isEmpty ? null : _mentorCtrl.text,
                        notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
                      );

                      _showSnack('تم إرسال الطلب ✅');
                      _titleCtrl.clear();
                      _descCtrl.clear();
                      _mentorCtrl.clear();
                      _notesCtrl.clear();
                      setState(() {
                        _category = null;
                        _isValid = false;
                      });
                    }
                        : null,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith(
                            (states) => states.contains(MaterialState.disabled)
                            ? Colors.grey.shade400
                            : _confirm,
                      ),
                      foregroundColor: MaterialStateProperty.all(Colors.white),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    child: const Text('إرسال الطلب', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _mentorCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }
}

class _RequiredNote extends StatelessWidget {
  const _RequiredNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text(
        'الحقول المعلّمة بعلامة (*) مطلوبة',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool requiredMark;
  const _FieldLabel({required this.text, this.requiredMark = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _darkGreen)),
        if (requiredMark)
          const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// =====================
/// تبويب: طلباتي
/// =====================
class _MyRequestsTab extends StatelessWidget {
  final String background;
  const _MyRequestsTab({required this.background});

  Color _statusColor(RequestStatus s) {
    switch (s) {
      case RequestStatus.accepted: return _confirm;
      case RequestStatus.rejected: return _danger;
      case RequestStatus.pending:  return _pending;
    }
  }

  String _statusLabel(RequestStatus s) {
    switch (s) {
      case RequestStatus.accepted: return 'مقبول';
      case RequestStatus.rejected: return 'مرفوض';
      case RequestStatus.pending:  return 'معلق';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Stack(
      children: [
        Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
        StreamBuilder<List<ClubRequest>>(
          stream: FirestoreClubsService.instance.streamMyRequests(uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return const Center(child: Text('لا توجد طلبات حتى الآن'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, kMyRequestsTopPadding, 16, 24),
              itemBuilder: (_, i) {
                final r = list[i];
                return Container(
                  decoration: BoxDecoration(
                    color: _lightGreen.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            'عنوان النادي: ${r.title}',
                            style: const TextStyle(color: _darkGreen, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      _StatusPill(label: _statusLabel(r.status), color: _statusColor(r.status)),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemCount: list.length,
            );
          },
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }
}

/// =====================
/// حقول النموذج
/// =====================
class _OutlinedInput extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final int maxLines;

  const _OutlinedInput({
    required this.hint,
    required this.controller,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(hintText: hint, border: InputBorder.none),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _DropdownInput extends StatelessWidget {
  final String? value;
  final List<String> items;
  final String hint;
  final void Function(String?)? onChanged;
  final String? Function(String?)? validator;

  const _DropdownInput({
    required this.value,
    required this.items,
    required this.hint,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: const InputDecoration(border: InputBorder.none),
        hint: Text(hint),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
        validator: validator,
      ),
    );
  }
}