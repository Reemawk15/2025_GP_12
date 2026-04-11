import 'dart:async';
import 'offline_download_service.dart';
import 'app_message_service.dart';
import 'package:flutter/material.dart';

enum DownloadTaskStatus { idle, downloading, downloaded, failed }

class DownloadTaskManager {
  DownloadTaskManager._();
  static final DownloadTaskManager instance = DownloadTaskManager._();

  final Map<String, DownloadTaskStatus> _status = {};
  final Map<String, Future<void>> _runningTasks = {};

  DownloadTaskStatus statusOf(String bookId) {
    return _status[bookId] ?? DownloadTaskStatus.idle;
  }

  bool isDownloading(String bookId) =>
      statusOf(bookId) == DownloadTaskStatus.downloading;

  bool isDownloaded(String bookId) =>
      statusOf(bookId) == DownloadTaskStatus.downloaded;

  Future<void> startDownload({
    required String bookId,
    required String title,
    required String author,
    required String coverUrl,
  }) {
    if (_runningTasks.containsKey(bookId)) {
      return _runningTasks[bookId]!;
    }

    _status[bookId] = DownloadTaskStatus.downloading;

    final task = _runDownload(
      bookId: bookId,
      title: title,
      author: author,
      coverUrl: coverUrl,
    );

    _runningTasks[bookId] = task;

    task.whenComplete(() {
      _runningTasks.remove(bookId);
    });

    return task;
  }

  Future<void> _runDownload({
    required String bookId,
    required String title,
    required String author,
    required String coverUrl,
  }) async {
    try {
      final parts = await OfflineDownloadService.prepareAudioParts(bookId);

      if (parts.isEmpty) {
        throw Exception('audioParts empty');
      }

      final folderPath = await OfflineDownloadService.downloadPartsToDevice(
        parts,
        title,
      );

      await OfflineDownloadService.markAsDownloaded(
        bookId: bookId,
        folderPath: folderPath,
      );

      await OfflineDownloadService.saveOfflineBookInfo(
        bookId: bookId,
        title: title,
        author: author,
        coverUrl: coverUrl,
        folderPath: folderPath,
      );

      _status[bookId] = DownloadTaskStatus.downloaded;
      showGlobalSnack('تم تحميل كتاب $title');
    } catch (_) {
      _status[bookId] = DownloadTaskStatus.failed;
      showGlobalSnack('فشل تحميل كتاب $title', icon: Icons.error_outline);
      rethrow;
    }
  }
}
