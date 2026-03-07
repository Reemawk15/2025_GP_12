import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class OfflineAudioPlayerPage extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final String bookAuthor;
  final String coverUrl;
  final List<String> audioPaths;

  const OfflineAudioPlayerPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.coverUrl,
    required this.audioPaths,
  });

  @override
  State<OfflineAudioPlayerPage> createState() => _OfflineAudioPlayerPageState();
}

class _OfflineAudioPlayerPageState extends State<OfflineAudioPlayerPage> {
  static const Color _darkGreen = Color(0xFF0E3A2C);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _midGreen = Color(0xFF2F5145);

  final AudioPlayer _player = AudioPlayer();

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  int _currentIndex = 0;
  double _speed = 1.0;
  bool _isReady = false;

  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final sources = widget.audioPaths
          .where((p) => File(p).existsSync())
          .map((p) => AudioSource.uri(Uri.file(p)))
          .toList();

      if (sources.isEmpty) return;

      await _player.setAudioSource(ConcatenatingAudioSource(children: sources));

      _durationSub = _player.durationStream.listen((d) {
        if (!mounted) return;
        setState(() {
          _duration = d ?? Duration.zero;
        });
      });

      _positionSub = _player.positionStream.listen((p) {
        if (!mounted) return;
        setState(() {
          _position = p;
        });
      });

      _indexSub = _player.currentIndexStream.listen((i) {
        if (!mounted) return;
        setState(() {
          _currentIndex = i ?? 0;
        });
      });

      _playerStateSub = _player.playerStateStream.listen((_) {
        if (!mounted) return;
        setState(() {});
      });

      if (!mounted) return;
      setState(() {
        _isReady = true;
      });
    } catch (e) {
      debugPrint('Offline player init error: $e');
    }
  }

  String _format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Future<void> _togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekForward() async {
    final newPos = _position + const Duration(seconds: 10);
    await _player.seek(newPos);
  }

  Future<void> _seekBackward() async {
    final newPos = _position - const Duration(seconds: 10);
    await _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  Future<void> _changeSpeed() async {
    final speeds = [1.0, 1.25, 1.5, 1.75, 2.0];
    int current = speeds.indexOf(_speed);
    current = (current + 1) % speeds.length;
    _speed = speeds[current];
    await _player.setSpeed(_speed);

    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _indexSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _player.playing;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/back_private.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: _isReady
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: Column(
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: _darkGreen,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 70),
                            padding: const EdgeInsets.fromLTRB(20, 90, 20, 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: widget.coverUrl.isNotEmpty
                                      ? Image.network(
                                          widget.coverUrl,
                                          width: 130,
                                          height: 185,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  width: 130,
                                                  height: 185,
                                                  color: _lightGreen,
                                                  child: const Icon(
                                                    Icons.menu_book,
                                                    size: 50,
                                                    color: _darkGreen,
                                                  ),
                                                );
                                              },
                                        )
                                      : Container(
                                          width: 150,
                                          height: 210,
                                          color: _lightGreen,
                                          child: const Icon(
                                            Icons.menu_book,
                                            size: 50,
                                            color: _darkGreen,
                                          ),
                                        ),
                                ),

                                const SizedBox(height: 20),

                                Text(
                                  widget.bookTitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _darkGreen,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Text(
                                  widget.bookAuthor,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black54,
                                  ),
                                ),

                                const SizedBox(height: 26),

                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    thumbColor: _darkGreen,
                                    activeTrackColor: _lightGreen,
                                    inactiveTrackColor: _lightGreen.withOpacity(
                                      0.35,
                                    ),
                                    trackHeight: 3,
                                  ),
                                  child: Slider(
                                    value: _position.inMilliseconds
                                        .toDouble()
                                        .clamp(
                                          0,
                                          (_duration.inMilliseconds == 0
                                                  ? 1
                                                  : _duration.inMilliseconds)
                                              .toDouble(),
                                        ),
                                    max:
                                        (_duration.inMilliseconds == 0
                                                ? 1
                                                : _duration.inMilliseconds)
                                            .toDouble(),
                                    onChanged: (value) async {
                                      await _player.seek(
                                        Duration(milliseconds: value.toInt()),
                                      );
                                    },
                                  ),
                                ),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _format(_position),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Text(
                                        _format(_duration),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      onPressed: _seekForward,
                                      icon: const Icon(
                                        Icons.replay_10_rounded,
                                        color: _darkGreen,
                                        size: 30,
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Container(
                                      width: 74,
                                      height: 74,
                                      decoration: const BoxDecoration(
                                        color: _lightGreen,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        onPressed: _togglePlayPause,
                                        icon: Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          size: 36,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    IconButton(
                                      onPressed: _seekBackward,
                                      icon: const Icon(
                                        Icons.forward_10_rounded,
                                        color: _darkGreen,
                                        size: 30,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      onTap: _changeSpeed,
                                      child: Text(
                                        '${_speed.toStringAsFixed(2)}x',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: _darkGreen,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'الجزء ${_currentIndex + 1} من ${widget.audioPaths.length}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
