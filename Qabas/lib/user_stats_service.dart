import 'package:cloud_firestore/cloud_firestore.dart';

class UserStatsService {
  static final _fs = FirebaseFirestore.instance;

  static String _dateKey(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime _onlyDate(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  static Future<void> updateUserStreak(String uid) async {
    final statsRef = _fs
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('main');

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(statsRef);
      final data = snap.data() ?? {};

      final now = DateTime.now();
      final today = _onlyDate(now);
      final todayKey = _dateKey(today);

      final lastListenDateStr = (data['lastListenDate'] ?? '') as String;
      final currentStreak = (data['currentStreak'] as num?)?.toInt() ?? 0;
      final bestStreak = (data['bestStreak'] as num?)?.toInt() ?? 0;

      int newCurrent = currentStreak;
      int newBest = bestStreak;

      if (lastListenDateStr.isEmpty) {
        newCurrent = 1;
        if (newBest < 1) newBest = 1;
      } else {
        final lastDate = DateTime.tryParse(lastListenDateStr);

        if (lastDate == null) {
          newCurrent = 1;
          if (newBest < 1) newBest = 1;
        } else {
          final lastOnly = _onlyDate(lastDate);
          final diffDays = today.difference(lastOnly).inDays;

          if (diffDays == 0) {
            newCurrent = currentStreak == 0 ? 1 : currentStreak;
          } else if (diffDays == 1) {
            newCurrent = currentStreak + 1;
          } else {
            newCurrent = 1;
          }

          if (newCurrent > newBest) {
            newBest = newCurrent;
          }
        }
      }

      tx.set(
        statsRef,
        {
          'currentStreak': newCurrent,
          'bestStreak': newBest,
          'lastListenDate': todayKey,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> syncCompletedBooksCount(String uid) async {
    final librarySnap = await _fs
        .collection('users')
        .doc(uid)
        .collection('library')
        .get();

    int count = 0;

    for (final doc in librarySnap.docs) {
      final data = doc.data();

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final isCompleted = data['isCompleted'] == true;

      if (status == 'listened' || isCompleted) {
        count++;
      }
    }

    await _fs
        .collection('users')
        .doc(uid)
        .collection('stats')
        .doc('main')
        .set({
      'completedBooksCount': count,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

}
