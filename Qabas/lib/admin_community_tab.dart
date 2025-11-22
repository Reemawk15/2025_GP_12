import 'package:flutter/material.dart';
import 'firestore_clubs_service.dart';

class AdminCommunityTab extends StatefulWidget {
  const AdminCommunityTab({super.key});

  @override
  State<AdminCommunityTab> createState() => _AdminCommunityTabState();
}

class _AdminCommunityTabState extends State<AdminCommunityTab> {
  // ==========================
  // Colors
  // ==========================
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _lightCard  = Color(0xFFE6F0E0);
  static const Color _confirm    = Color(0xFF6F8E63);
  static const Color _danger     = Color(0xFFB64B4B);

  // ==========================
  // Snackbars
  // ==========================
  void _showDecisionSnack(bool accepted) {
    final msg   = accepted ? 'تم قبول الطلب' : 'تم رفض الطلب';
    final icon  = accepted ? Icons.check_circle : Icons.close_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFE7C4DA), size: 22),
            const SizedBox(width: 8),
            Text(
              msg,
              style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClubCancelledSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _confirm,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle, color: Color(0xFFE7C4DA), size: 22),
            SizedBox(width: 8),
            Text(
              'تم إلغاء النادي وحذف بياناته',
              style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================
  // Open details page
  // ==========================
  Future<void> _openDetails(ClubRequest r) async {
    final result = await Navigator.of(context).push<_Decision?>(
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

    if (result == null) return;

    final accepted = result == _Decision.accepted;

    await FirestoreClubsService.instance.decide(request: r, accept: accepted);
    _showDecisionSnack(accepted);
  }

  // ==========================
  // Cancel accepted club (DIALOG + DELETE)
  // ==========================
  Future<void> _cancelClub(ClubRequest r) async {
    final confirm = await showDialog<bool>(
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
                  'إلغاء النادي',
                  style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد من إلغاء النادي؟ سيتم حذف جميع بياناته من التطبيق.',
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
                      'تأكيد الإلغاء',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'رجوع',
                      style: TextStyle(color: _darkGreen, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm != true) return;

    // Run club deletion logic
    await FirestoreClubsService.instance.cancelClubForRequest(r);

    if (!mounted) return;
    _showClubCancelledSnack();
  }

  // ==========================
  // Current requests tab
  // ==========================
  Widget _buildCurrentRequests() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<ClubRequest>>(
        stream: FirestoreClubsService.instance.streamPending(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('لا توجد طلبات حالية'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemCount: list.length,
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
                      r.title,
                      style: const TextStyle(
                        color: _darkGreen,
                        fontWeight: FontWeight.bold,
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
                            horizontal: 18, vertical: 10,
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
          );
        },
      ),
    );
  }

  // ==========================
  // History tab (with CANCEL CLUB button)
  // ==========================
  Widget _buildHistoryRequests() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<ClubRequest>>(
        stream: FirestoreClubsService.instance.streamHistory(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = snap.data!;
          if (list.isEmpty) {
            return const Center(child: Text('لا توجد طلبات سابقة'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];

              // Decide chip text & color based on status
              String statusLabel;
              Color statusColor;

              if (r.status == RequestStatus.accepted) {
                statusLabel = 'مقبول';
                statusColor = _confirm;
              } else if (r.status == RequestStatus.rejected) {
                statusLabel = 'مرفوض';
                statusColor = _danger;
              } else {
                statusLabel = 'ملغى';
                statusColor = Colors.grey;
              }

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
                      r.title,
                      style: const TextStyle(
                        color: _darkGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        // حبة حالة الطلب
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // زر "إلغاء النادي" بنفس شكل مقبول وبجنبه
                        if (isAccepted)
                          InkWell(
                            onTap: () => _cancelClub(r),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _midGreen,        // نفس لون مقبول
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'إلغاء النادي',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ==========================
  // Build main screen
  // ==========================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/clubs1.jpeg',
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
                      color: _darkGreen, size: 20,
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
                  children: const [
                    TabBar(
                      labelColor: _darkGreen,
                      unselectedLabelColor: Colors.black54,
                      indicatorColor: _darkGreen,
                      tabs: [
                        Tab(text: 'الطلبات الحالية'),
                        Tab(text: 'الطلبات السابقة'),
                      ],
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _CurrentTabHost(),
                          _HistoryTabHost(),
                        ],
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

// Hosts for TabBarView (same technique as admin books)
class _CurrentTabHost extends StatelessWidget {
  const _CurrentTabHost();

  @override
  Widget build(BuildContext context) {
    final s = context.findAncestorStateOfType<_AdminCommunityTabState>();
    return s?._buildCurrentRequests() ?? const SizedBox();
  }
}

class _HistoryTabHost extends StatelessWidget {
  const _HistoryTabHost();

  @override
  Widget build(BuildContext context) {
    final s = context.findAncestorStateOfType<_AdminCommunityTabState>();
    return s?._buildHistoryRequests() ?? const SizedBox();
  }
}

// ===============================
// Request details page (same as before)
// ===============================
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
                    color: darkGreen, size: 20,
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
                      _readonlyField(
                        'عنوان النادي', request.title, lightCard, darkGreen,
                      ),
                      const SizedBox(height: 14),

                      _readonlyField(
                        'وصف قصير', request.description ?? '—', lightCard, darkGreen,
                      ),
                      const SizedBox(height: 14),

                      _readonlyField(
                        'الفئة', request.category ?? '—', lightCard, darkGreen,
                      ),
                      const SizedBox(height: 14),

                      _readonlyField(
                        'اسم المنشئ', request.ownerName ?? '—', lightCard, darkGreen,
                      ),
                      const SizedBox(height: 14),

                      _readonlyField(
                        'ملاحظات', request.notes ?? '—', lightCard, darkGreen,
                      ),
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
                              onPressed: () =>
                                  Navigator.pop(context, _Decision.rejected),
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
                              onPressed: () =>
                                  Navigator.pop(context, _Decision.accepted),
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

  Widget _readonlyField(
      String label, String value, Color bg, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 6),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: textColor, fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
