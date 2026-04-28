import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'offline_audio_player_page.dart';
import 'offline_podcast_player_page.dart';

class OfflineBooksPage extends StatefulWidget {
  const OfflineBooksPage({super.key});

  @override
  State<OfflineBooksPage> createState() => _OfflineBooksPageState();

}

class _OfflineBooksPageState extends State<OfflineBooksPage> {
  static const Color _darkGreen = Color(0xFF0E3A2C);
  static const Color _midGreen = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm = Color(0xFF6F8E63);

  bool _loading = true;
  List<_OfflineBook> books = [];
  List<_OfflinePodcast> podcasts = [];

  @override
  void initState() {
    super.initState();
    _loadOfflineBooks();
  }

  Future<void> _loadOfflineBooks() async {
    final prefs = await SharedPreferences.getInstance();

    final stored = prefs.getStringList('offline_books') ?? [];
    final storedPodcasts = prefs.getStringList('offline_podcasts') ?? [];

    final loadedBooks = stored.map((e) {
      final parts = e.split('|||');

      return _OfflineBook(
        bookId: parts.length > 0 ? parts[0] : '',
        title: parts.length > 1 ? parts[1] : '',
        author: parts.length > 2 ? parts[2] : '',
        coverUrl: parts.length > 3 ? parts[3] : '',
        folderPath: parts.length > 4 ? parts[4] : '',
      );
    }).toList();

    final loadedPodcasts = storedPodcasts.map((e) {
      final parts = e.split('|||');
      return _OfflinePodcast(
        podcastId: parts.length > 0 ? parts[0] : '',
        title: parts.length > 1 ? parts[1] : '',
        coverUrl: parts.length > 2 ? parts[2] : '',
        audioPath: parts.length > 3 ? parts[3] : '',
      );
    }).toList();

    if (!mounted) return;
    setState(() {
      books = loadedBooks;
      podcasts = loadedPodcasts;
      _loading = false;
    });
  }
  Future<bool> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'حذف التحميل',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0E3A2C),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد من حذف هذا الصوت؟',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Color(0xFF6F8E63),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('تأكيد'),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey,
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return confirm == true;
  }
  void _showSnack(String msg, {IconData icon = Icons.check_circle}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF6F8E63),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFE7C4DA)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  Future<void> _deleteOfflineBook(_OfflineBook book) async {
    try {
      final dir = Directory(book.folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('offline_books') ?? [];

      stored.removeWhere((e) => e.startsWith('${book.bookId}|||'));
      await prefs.setStringList('offline_books', stored);

      await prefs.remove('downloaded_${book.bookId}');
      await prefs.remove('downloadPath_${book.bookId}');

      setState(() {
        books.removeWhere((b) => b.bookId == book.bookId);
      });

      if (!mounted) return;
      _showSnack('تم حذف التحميل', icon: Icons.check_circle);
    } catch (e) {
      if (!mounted) return;
      _showSnack('تعذّر حذف التحميل', icon: Icons.error_outline);
    }
  }

  Future<void> _deleteOfflinePodcast(_OfflinePodcast podcast) async {
    try {
      final file = File(podcast.audioPath);
      if (await file.exists()) {
        await file.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('offline_podcasts') ?? [];

      stored.removeWhere((e) => e.startsWith('${podcast.podcastId}|||'));
      await prefs.setStringList('offline_podcasts', stored);

      await prefs.remove('downloaded_${podcast.podcastId}');
      await prefs.remove('downloadPath_${podcast.podcastId}');

      setState(() {
        podcasts.removeWhere((p) => p.podcastId == podcast.podcastId);
      });

      if (!mounted) return;
      _showSnack('تم حذف التحميل', icon: Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      _showSnack('تعذّر حذف التحميل', icon: Icons.error_outline);
    }
  }
  Future<void> _openOfflineBook(_OfflineBook book) async {
    final dir = Directory(book.folderPath);

    if (!await dir.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ملفات الكتاب غير موجودة')));
      return;
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.mp3'))
        .toList();

    files.sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد ملفات صوتية لهذا الكتاب')),
      );
      return;
    }

    final localPaths = files.map((f) => f.path).toList();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OfflineAudioPlayerPage(
          bookId: book.bookId,
          bookTitle: book.title,
          bookAuthor: book.author,
          coverUrl: book.coverUrl,
          audioPaths: localPaths,
        ),
      ),
    );
  }

  Future<void> _openOfflinePodcast(_OfflinePodcast podcast) async {
    final file = File(podcast.audioPath);

    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ملف البودكاست غير موجود')));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OfflinePodcastPlayerPage(
          podcastId: podcast.podcastId,
          podcastTitle: podcast.title,
          coverUrl: podcast.coverUrl,
          audioPath: podcast.audioPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        _midGreen,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 190),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: IconButton(
                                    tooltip: 'رجوع',
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white.withOpacity(
                                        0.85,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                    ),
                                    color: _darkGreen,
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),

                                const SizedBox(height: 28),

                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F7F5),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      const Padding(
                                        padding: EdgeInsetsDirectional.only(
                                          end: 8,
                                        ),
                                        child: Icon(
                                          Icons.offline_bolt_outlined,
                                          color: _confirm,
                                        ),
                                      ),
                                      const Expanded(
                                        child: Text(
                                          'الاستماع بدون إنترنت',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _lightGreen,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '${books.length + podcasts.length} كتب',
                                          style: const TextStyle(
                                            color: _darkGreen,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                if (books.isEmpty && podcasts.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF9F9F7),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE8E8E3),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.headphones_outlined,
                                          size: 38,
                                          color: _midGreen.withOpacity(0.75),
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'لا توجد كتب محمّلة حالياً',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w600,
                                            color: _darkGreen,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  )
                                else
                                  ...books.map(
                                    (book) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),

                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => _openOfflineBook(book),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF9F9F7),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFE8E8E3),
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: book.coverUrl.isNotEmpty
                                                    ? Image.network(
                                                        book.coverUrl,
                                                        width: 58,
                                                        height: 78,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              context,
                                                              error,
                                                              stackTrace,
                                                            ) {
                                                              return Container(
                                                                width: 58,
                                                                height: 78,
                                                                color:
                                                                    _lightGreen,
                                                                child: const Icon(
                                                                  Icons
                                                                      .menu_book,
                                                                  color:
                                                                      _darkGreen,
                                                                ),
                                                              );
                                                            },
                                                      )
                                                    : Container(
                                                        width: 58,
                                                        height: 78,
                                                        color: _lightGreen,
                                                        child: const Icon(
                                                          Icons.menu_book,
                                                          color: _darkGreen,
                                                        ),
                                                      ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      book.title,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 15.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _darkGreen,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      book.author,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () async {
                                                  final ok = await _confirmDelete();
                                                  if (!ok) return;

                                                  _deleteOfflineBook(book);
                                                },
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Colors.red,
                                                ),
                                                tooltip: 'حذف التحميل',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ...podcasts.map(
                                  (podcast) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => _openOfflinePodcast(podcast),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF9F9F7),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE8E8E3),
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: podcast.coverUrl.isNotEmpty
                                                  ? Image.network(
                                                      podcast.coverUrl,
                                                      width: 58,
                                                      height: 78,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stackTrace,
                                                          ) {
                                                            return Container(
                                                              width: 58,
                                                              height: 78,
                                                              color:
                                                                  _lightGreen,
                                                              child: const Icon(
                                                                Icons
                                                                    .podcasts_rounded,
                                                                color:
                                                                    _darkGreen,
                                                              ),
                                                            );
                                                          },
                                                    )
                                                  : Container(
                                                      width: 58,
                                                      height: 78,
                                                      color: _lightGreen,
                                                      child: const Icon(
                                                        Icons.podcasts_rounded,
                                                        color: _darkGreen,
                                                      ),
                                                    ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                podcast.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: _darkGreen,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () async {
                                                final ok = await _confirmDelete();
                                                if (!ok) return;

                                                _deleteOfflinePodcast(podcast);
                                              },
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
                                                color: Colors.red,
                                              ),
                                              tooltip: 'حذف التحميل',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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
        ],
      ),
    );
  }
}

class _OfflineBook {
  final String bookId;
  final String title;
  final String author;
  final String coverUrl;
  final String folderPath;

  _OfflineBook({
    required this.bookId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.folderPath,
  });
}

class _OfflinePodcast {
  final String podcastId;
  final String title;
  final String coverUrl;
  final String audioPath;

  _OfflinePodcast({
    required this.podcastId,
    required this.title,
    required this.coverUrl,
    required this.audioPath,
  });
}
