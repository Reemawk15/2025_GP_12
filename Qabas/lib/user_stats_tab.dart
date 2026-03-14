import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_stats_service.dart';

const Color _darkGreen = Color(0xFF0E3A2C);
const Color _card = Color(0xFFC9DABF);

class UserStatsTab extends StatefulWidget {
  final String uid;

  const UserStatsTab({super.key, required this.uid});

  @override
  State<UserStatsTab> createState() => _UserStatsTabState();
}

class _UserStatsTabState extends State<UserStatsTab> {
  @override
  void initState() {
    super.initState();
    _syncStats();
  }

  Future<void> _syncStats() async {
    await UserStatsService.syncCompletedBooksCount(widget.uid);
  }


  @override
  Widget build(BuildContext context) {
    final statsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('stats')
        .doc('main');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: statsRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};

        final best = (data['bestStreak'] as num?)?.toInt() ?? 0;
        final current = (data['currentStreak'] as num?)?.toInt() ?? 0;
        final completed = (data['completedBooksCount'] as num?)?.toInt() ?? 0;

        final items = [
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
        ];

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          itemBuilder: (_, i) => items[i],
          separatorBuilder: (_, __) => const SizedBox(height: 24),
          itemCount: items.length,
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String text;

  const _StatCard({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
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

String _toArabicDigits(int number) {
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  var text = number.toString();
  for (int i = 0; i < western.length; i++) {
    text = text.replaceAll(western[i], arabic[i]);
  }
  return text;
}

String _arabicWord(int count, String singular, String plural) {
  return count == 1 ? singular : plural;
}

String _formatArabicCount(int count, String singular, String plural) {
  final number = _toArabicDigits(count);
  final word = _arabicWord(count, singular, plural);
  return '$number $word';
}
