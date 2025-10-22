import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestStatus { pending, accepted, rejected }

RequestStatus _statusFromString(String s) {
  switch (s) {
    case 'accepted': return RequestStatus.accepted;
    case 'rejected': return RequestStatus.rejected;
    default:         return RequestStatus.pending;
  }
}

String _statusToString(RequestStatus s) {
  switch (s) {
    case RequestStatus.accepted: return 'accepted';
    case RequestStatus.rejected: return 'rejected';
    case RequestStatus.pending:  return 'pending';
  }
}

class ClubRequest {
  final String id;
  final String title;
  final String? description;
  final String? category;
  final String? ownerName;
  final String? notes;
  final String createdBy;
  final RequestStatus status;

  ClubRequest({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.status,
    this.description,
    this.category,
    this.ownerName,
    this.notes,
  });

  factory ClubRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ClubRequest(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'],
      category: d['category'],
      ownerName: d['ownerName'],
      notes: d['notes'],
      createdBy: d['createdBy'] ?? '',
      status: _statusFromString(d['status'] ?? 'pending'),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'category': category,
    'ownerName': ownerName,
    'notes': notes,
    'createdBy': createdBy,
    'status': _statusToString(status),
  };
}

class PublicClub {
  final String id;
  final String title;
  final String? description;
  final String? category;
  final String ownerUid;
  PublicClub({
    required this.id,
    required this.title,
    required this.ownerUid,
    this.description,
    this.category,
  });

  factory PublicClub.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return PublicClub(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'],
      category: d['category'],
      ownerUid: d['ownerUid'] ?? '',
    );
  }
}

class FirestoreClubsService {
  FirestoreClubsService._();

  static final instance = FirestoreClubsService._();

  final _requests = FirebaseFirestore.instance.collection('clubRequests');
  final _clubs = FirebaseFirestore.instance.collection('clubs');

  // ======== Requests ========
  Future<void> submitRequest({
    required String uid,
    required String title,
    required String description,
    required String category,
    String? ownerName,
    String? notes,
  }) async {
    await _requests.add({
      'title': title.trim(),
      'description': description.trim(),
      'category': category.trim(),
      'ownerName': ownerName?.trim(),
      'notes': notes?.trim(),
      'createdBy': uid,
      'status': 'pending',
    });
  }

  Stream<List<ClubRequest>> streamPending() =>
      _requests
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((s) => s.docs.map((d) => ClubRequest.fromDoc(d)).toList());

  Stream<List<ClubRequest>> streamHistory() =>
      _requests
          .where('status', whereIn: ['accepted', 'rejected'])
          .snapshots()
          .map((s) => s.docs.map((d) => ClubRequest.fromDoc(d)).toList());

  Stream<List<ClubRequest>> streamMyRequests(String uid) =>
      _requests
          .where('createdBy', isEqualTo: uid)
          .snapshots()
          .map((s) => s.docs.map((d) => ClubRequest.fromDoc(d)).toList());

  /// قرار الأدمن + إنشاء نادي عند القبول
  Future<void> decide({
    required ClubRequest request,
    required bool accept,
  }) async {
    final batch = FirebaseFirestore.instance.batch();

    final reqRef = _requests.doc(request.id);
    batch.update(reqRef, {'status': accept ? 'accepted' : 'rejected'});

    if (accept) {
      final clubRef = _clubs.doc(); // id تلقائي
      batch.set(clubRef, {
        'title': request.title,
        'description': request.description,
        'category': request.category,
        'ownerUid': request.createdBy,
        'requestId': request.id,
        'createdAt': FieldValue.serverTimestamp(), // للعرض فقط
        'membersCount': 1, // يبدأ بصاحب الطلب
      });
      // إضافة صاحب الطلب كعضو أولي
      batch.set(clubRef.collection('members').doc(request.createdBy), {
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ======== Clubs (Public) ========
  Stream<List<PublicClub>> streamPublicClubs() =>
      _clubs
      // ترتيب بسيط على createdAt فقط (بدون where) → لا يحتاج فهرس مركّب
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map((d) => PublicClub.fromDoc(d)).toList());

  Future<void> joinClub({
    required String clubId,
    required String uid,
  }) async {
    final clubRef = _clubs.doc(clubId);
    final memberRef = clubRef.collection('members').doc(uid);

    final snap = await memberRef.get();
    if (!snap.exists) {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.set(memberRef, {'joinedAt': FieldValue.serverTimestamp()});
        tx.update(clubRef, {'membersCount': FieldValue.increment(1)});
      });
    }
  }

  // ======== Chat ========
  Stream<QuerySnapshot<Map<String, dynamic>>> streamMessages(String clubId) {
    return _clubs
        .doc(clubId)
        .collection('messages')
        .orderBy('createdAt', descending: false) // فقط ترتيب
        .snapshots();
  }

  Future<void> sendMessage({
    required String clubId,
    required String uid,
    required String text,
    required String displayName,
    String? photoUrl, // << جديد
  }) async {
    await _clubs
        .doc(clubId)
        .collection('messages')
        .add({
      'uid': uid,
      'text': text,
      'displayName': displayName,
      'photoUrl': photoUrl, // << جديد
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}