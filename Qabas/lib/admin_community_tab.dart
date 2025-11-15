import 'package:flutter/material.dart';
import 'firestore_clubs_service.dart';

class AdminCommunityTab extends StatefulWidget {
  const AdminCommunityTab({super.key});

  @override
  State<AdminCommunityTab> createState() => _AdminCommunityTabState();
}

class _AdminCommunityTabState extends State<AdminCommunityTab> {
  // Colors
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _lightCard  = Color(0xFFE6F0E0);
  static const Color _confirm    = Color(0xFF6F8E63);
  static const Color _danger     = Color(0xFFB64B4B);

  void _showSnack(bool accepted) {
    final msg = accepted ? 'تم قبول الطلب ✅' : 'تم رفض الطلب ❌';
    final bg  = accepted ? _confirm : _danger;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openDetails(ClubRequest r) async {
    final decision = await Navigator.of(context).push<_Decision?>(
      MaterialPageRoute(
        builder: (_) => _RequestDetailsPage(
          request: r,
          darkGreen: _darkGreen,
          midGreen: _midGreen,
          lightCard: _lightCard,
          confirm: _confirm,
          danger: _danger,
        ),
      ),
    );
    if (decision == null) return;
    final accept = decision == _Decision.accepted;

    // ✅ Handle decision + create club when accepted
    await FirestoreClubsService.instance.decide(request: r, accept: accept);
    _showSnack(accept);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/clubs1.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 120,
              leading: SafeArea(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, top: 20),
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _darkGreen,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 150, 16, 24),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            const TabBar(
                              labelColor: _darkGreen,
                              unselectedLabelColor: Colors.black54,
                              indicatorColor: _darkGreen,
                              tabs: [
                                Tab(text: 'الطلبات الحالية'),
                                Tab(text: 'الطلبات السابقة'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  // Current requests
                                  StreamBuilder<List<ClubRequest>>(
                                    stream: FirestoreClubsService.instance.streamPending(),
                                    builder: (context, snap) {
                                      if (snap.connectionState == ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      final list = snap.data ?? const [];
                                      if (list.isEmpty) {
                                        return const Center(
                                          child: Text('لا توجد طلبات حالية'),
                                        );
                                      }
                                      return ListView.separated(
                                        padding: const EdgeInsets.all(16),
                                        itemBuilder: (_, i) {
                                          final r = list[i];
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: _lightCard,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'عنوان النادي: ${r.title}',
                                                  style: const TextStyle(
                                                    color: _darkGreen,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Align(
                                                  alignment: Alignment.centerRight,
                                                  child: FilledButton(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor: _confirm,
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                        vertical: 10,
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                    ),
                                                    onPressed: () => _openDetails(r),
                                                    child: const Text('عرض التفاصيل'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                                        itemCount: list.length,
                                      );
                                    },
                                  ),

                                  // Previous requests
                                  StreamBuilder<List<ClubRequest>>(
                                    stream: FirestoreClubsService.instance.streamHistory(),
                                    builder: (context, snap) {
                                      if (snap.connectionState == ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      final list = snap.data ?? const [];
                                      if (list.isEmpty) {
                                        return const Center(
                                          child: Text('لا توجد طلبات سابقة'),
                                        );
                                      }
                                      return ListView.separated(
                                        padding: const EdgeInsets.all(16),
                                        itemBuilder: (_, i) {
                                          final r = list[i];
                                          final isAccepted = r.status == RequestStatus.accepted;
                                          return Container(
                                            decoration: BoxDecoration(
                                              color: _lightCard,
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'عنوان النادي: ${r.title}',
                                                  style: const TextStyle(
                                                    color: _darkGreen,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    const Text(
                                                      'حالة الطلب: ',
                                                      style: TextStyle(color: Colors.black87),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isAccepted ? _confirm : _danger,
                                                        borderRadius: BorderRadius.circular(999),
                                                      ),
                                                      child: Text(
                                                        isAccepted ? 'مقبول' : 'مرفوض',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                                        itemCount: list.length,
                                      );
                                    },
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}

// ======== Request details page ========
enum _Decision { accepted, rejected }

class _RequestDetailsPage extends StatelessWidget {
  const _RequestDetailsPage({
    required this.request,
    required this.darkGreen,
    required this.midGreen,
    required this.lightCard,
    required this.confirm,
    required this.danger,
  });

  final ClubRequest request;
  final Color darkGreen, midGreen, lightCard, confirm, danger;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/clubs1.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 100,
              leading: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8, top: 40),
                child: IconButton(
                  tooltip: 'رجوع',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: darkGreen,
                    size: 20,
                  ),
                ),
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      _readonlyField('عنوان النادي', request.title, lightCard, darkGreen),
                      const SizedBox(height: 14),
                      _readonlyField('وصف قصير', request.description ?? '—', lightCard, darkGreen),
                      const SizedBox(height: 14),
                      _readonlyField('الفئة', request.category ?? '—', lightCard, darkGreen),
                      const SizedBox(height: 14),
                      _readonlyField('اسم المُنشئ (اختياري)', request.ownerName ?? '—', lightCard, darkGreen),
                      const SizedBox(height: 14),
                      _readonlyField('ملاحظات (اختياري)', request.notes ?? '—', lightCard, darkGreen),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: danger, width: 2),
                                foregroundColor: danger,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context, _Decision.rejected),
                              child: const Text('رفض'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: confirm,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context, _Decision.accepted),
                              child: const Text('قبول'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readonlyField(String label, String value, Color bg, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}