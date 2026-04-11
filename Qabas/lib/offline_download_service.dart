import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class OfflineDownloadService {
  static bool audioReady(Map<String, dynamic>? data) {
    if (data == null) return false;
    final partsRaw = data['audioParts'];
    return partsRaw is List && partsRaw.isNotEmpty;
  }

  static Future<List<String>> waitForAudioParts({
    required DocumentReference<Map<String, dynamic>> docRef,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 9));

    while (DateTime.now().isBefore(deadline)) {
      final snap = await docRef.get();
      final data = snap.data();

      if (audioReady(data)) {
        final parts = List<String>.from(data!['audioParts'] ?? []);
        if (parts.isNotEmpty) return parts;
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    throw Exception('Timeout waiting for audioParts');
  }

  static String safeFolderName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\n\r\t]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'كتاب';
    if (cleaned.length > 60) cleaned = cleaned.substring(0, 60).trim();
    return cleaned;
  }

  static Future<String> downloadPartsToDevice(
    List<String> urls,
    String bookTitle,
  ) async {
    final safeTitle = safeFolderName(bookTitle);

    final appDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory('${appDir.path}/offline_books');

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final bookDir = Directory('${baseDir.path}/$safeTitle');

    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }

    final dio = Dio();

    for (int i = 0; i < urls.length; i++) {
      final partNumber = (i + 1).toString().padLeft(2, '0');
      final filePath = '${bookDir.path}/part_$partNumber.mp3';
      final file = File(filePath);

      if (await file.exists()) continue;

      await dio.download(urls[i], file.path);
    }

    return bookDir.path;
  }

  static Future<void> saveOfflineBookInfo({
    required String bookId,
    required String title,
    required String author,
    required String coverUrl,
    required String folderPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getStringList('offline_books') ?? [];

    final item = '$bookId|||$title|||$author|||$coverUrl|||$folderPath';

    existing.removeWhere((e) => e.startsWith('$bookId|||'));
    existing.add(item);

    await prefs.setStringList('offline_books', existing);
  }

  static Future<List<String>> prepareAudioParts(String bookId) async {
    final docRef = FirebaseFirestore.instance
        .collection('audiobooks')
        .doc(bookId)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (s, _) => (s.data() ?? {}),
          toFirestore: (m, _) => m,
        );

    final snap = await docRef.get();
    final data = snap.data();

    if (audioReady(data)) {
      return List<String>.from(data!['audioParts'] ?? []);
    }

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'generateBookAudioV2',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        );

    await callable.call({'bookId': bookId, 'maxParts': 30});

    return await waitForAudioParts(docRef: docRef);
  }

  static Future<void> markAsDownloaded({
    required String bookId,
    required String folderPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('downloaded_$bookId', true);
    await prefs.setString('downloadPath_$bookId', folderPath);
  }
}
