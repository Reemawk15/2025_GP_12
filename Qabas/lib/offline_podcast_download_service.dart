import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class OfflinePodcastDownloadService {
  static String safeFileName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\n\r\t]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'بودكاست';
    if (cleaned.length > 60) cleaned = cleaned.substring(0, 60).trim();
    return cleaned;
  }

  static Future<String> downloadPodcastToDevice({
    required String podcastId,
    required String audioUrl,
    required String title,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory('${appDir.path}/offline_podcasts');

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final safeTitle = safeFileName(title);
    final filePath = '${baseDir.path}/${podcastId}_$safeTitle.mp3';

    final file = File(filePath);
    if (await file.exists()) return file.path;

    final dio = Dio();
    await dio.download(audioUrl, file.path);

    return file.path;
  }

  static Future<void> markAsDownloaded({
    required String podcastId,
    required String filePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('downloaded_$podcastId', true);
    await prefs.setString('downloadPath_$podcastId', filePath);
  }

  static Future<void> saveOfflinePodcastInfo({
    required String podcastId,
    required String title,
    required String coverUrl,
    required String audioPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList('offline_podcasts') ?? [];

    final item = '$podcastId|||$title|||$coverUrl|||$audioPath';

    existing.removeWhere((e) => e.startsWith('$podcastId|||'));
    existing.add(item);

    await prefs.setStringList('offline_podcasts', existing);
  }
}
