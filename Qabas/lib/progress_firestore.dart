import 'package:cloud_firestore/cloud_firestore.dart';

class ProgressFirestore {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String bookId) {
    return _db.collection('users').doc(uid).collection('library').doc(bookId);
  }

  Future<int> loadListenedSeconds({
    required String uid,
    required String bookId,
  }) async {
    final snap = await _doc(uid, bookId).get();
    if (!snap.exists) return 0;
    final data = snap.data();
    if (data == null) return 0;
    return (data['listenedSeconds'] as num?)?.toInt() ?? 0;
  }

  Future<void> saveProgress({
    required String uid,
    required String bookId,
    required int listenedSeconds,
    required int estimatedTotalSeconds,
  }) async {
    final isCompleted =
        listenedSeconds >= estimatedTotalSeconds && estimatedTotalSeconds > 0;

    await _doc(uid, bookId).set({
      'listenedSeconds': listenedSeconds,
      'estimatedTotalSeconds': estimatedTotalSeconds,
      'updatedAt': FieldValue.serverTimestamp(),

      // Behavior tracking
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'lastListenedAt': FieldValue.serverTimestamp(),
      'isCompleted': isCompleted,
      'status': isCompleted ? 'listened' : 'listen_now',
    }, SetOptions(merge: true));
  }
}