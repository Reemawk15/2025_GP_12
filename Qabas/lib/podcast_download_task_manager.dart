import 'offline_podcast_download_service.dart';
import 'package:flutter/material.dart';
import 'app_message_service.dart';

enum PodcastDownloadTaskStatus { idle, downloading, downloaded, failed }

class PodcastDownloadTaskManager {
  PodcastDownloadTaskManager._();
  static final PodcastDownloadTaskManager instance =
      PodcastDownloadTaskManager._();

  final Map<String, PodcastDownloadTaskStatus> _status = {};
  final Map<String, Future<void>> _runningTasks = {};

  PodcastDownloadTaskStatus statusOf(String podcastId) {
    return _status[podcastId] ?? PodcastDownloadTaskStatus.idle;
  }

  bool isDownloading(String podcastId) =>
      statusOf(podcastId) == PodcastDownloadTaskStatus.downloading;

  bool isDownloaded(String podcastId) =>
      statusOf(podcastId) == PodcastDownloadTaskStatus.downloaded;

  Future<void> startDownload({
    required String podcastId,
    required String audioUrl,
    required String title,
    required String coverUrl,
  }) {
    if (_runningTasks.containsKey(podcastId)) {
      return _runningTasks[podcastId]!;
    }

    _status[podcastId] = PodcastDownloadTaskStatus.downloading;

    final task = _runDownload(
      podcastId: podcastId,
      audioUrl: audioUrl,
      title: title,
      coverUrl: coverUrl,
    );

    _runningTasks[podcastId] = task;

    task.whenComplete(() {
      _runningTasks.remove(podcastId);
    });

    return task;
  }

  Future<void> _runDownload({
    required String podcastId,
    required String audioUrl,
    required String title,
    required String coverUrl,
  }) async {
    try {
      final filePath =
          await OfflinePodcastDownloadService.downloadPodcastToDevice(
            podcastId: podcastId,
            audioUrl: audioUrl,
            title: title,
          );

      await OfflinePodcastDownloadService.markAsDownloaded(
        podcastId: podcastId,
        filePath: filePath,
      );

      await OfflinePodcastDownloadService.saveOfflinePodcastInfo(
        podcastId: podcastId,
        title: title,
        coverUrl: coverUrl,
        audioPath: filePath,
      );

      _status[podcastId] = PodcastDownloadTaskStatus.downloaded;
      showGlobalSnack('تم تحميل بودكاست $title');
    } catch (_) {
      _status[podcastId] = PodcastDownloadTaskStatus.failed;
      showGlobalSnack('فشل تحميل بودكاست $title', icon: Icons.error_outline);
      rethrow;
    }
  }
}
