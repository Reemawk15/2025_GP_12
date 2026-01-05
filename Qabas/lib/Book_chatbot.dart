import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class BookChatPage extends StatefulWidget {
  final String bookId;

  const BookChatPage({
    super.key,
    required this.bookId,
  });

  @override
  State<BookChatPage> createState() => _BookChatPageState();
}

class _BookChatPageState extends State<BookChatPage> {
  static const Color _titleColor = Color(0xFF0E3A2C);
  static const Color _confirm = Color(0xFF6F8E63);
  static const Color _bubbleUser = Color(0xFFE6F0E0);
  static const Color _bubbleBot = Color(0xFFFFEEF1);

  static const double _titleTop = 85;
  static const double _backTop = 80;
  static const double _chatStartTop = 150;

  static const String _region = 'us-central1';

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  bool _sending = false;
  bool _preparing = true;

  final List<Map<String, dynamic>> _messages = [
    {
      "role": "assistant",
      "text":
      "أهلًا! هذا مساعد قبس لهذا الكتاب فقط 📚\nيمكنك السؤال عن أي جزء، أو قول: \"لخّص\" / \"اشرح\" / \"ما معنى كلمة…؟\"",
      "quotes": <String>[],
    }
  ];

  @override
  void initState() {
    super.initState();
    _prepareBook();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: _region);

  Future<void> _prepareBook() async {
    setState(() => _preparing = true);

    try {
      final fn = _functions.httpsCallable('prepareBookChat');
      await fn.call({"bookId": widget.bookId});
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'prepareBookChat code=${e.code} message=${e.message} details=${e.details}',
      );
      if (!mounted) return;
      setState(() {
        _messages.add({
          "role": "assistant",
          "text": "تعذر تجهيز مساعد هذا الكتاب الآن. (${e.code})",
          "quotes": <String>[],
        });
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('prepareBookChat error: $e');
      if (!mounted) return;
      setState(() {
        _messages.add({
          "role": "assistant",
          "text": "تعذر تجهيز مساعد هذا الكتاب الآن.",
          "quotes": <String>[],
        });
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty || _sending || _preparing) return;

    setState(() {
      _messages.add({"role": "user", "text": t, "quotes": <String>[]});
      _sending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final fn = _functions.httpsCallable('askBookChat');
      final res = await fn.call({
        "bookId": widget.bookId,
        "message": t,
      });

      final data = (res.data ?? {}) as Map;
      final answer = (data["answer"] ?? "").toString().trim();
      final quotesRaw = data["quotes"];

      final List<String> quotes = (quotesRaw is List)
          ? quotesRaw
          .map((e) => e.toString())
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList()
          : <String>[];

      setState(() {
        _messages.add({
          "role": "assistant",
          "text": answer.isEmpty ? "غير مذكور في هذا الكتاب." : answer,
          "quotes": quotes,
        });
      });
      _scrollToBottom();
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'askBookChat code=${e.code} message=${e.message} details=${e.details}',
      );
      setState(() {
        _messages.add({
          "role": "assistant",
          "text": "حدث خطأ أثناء الاتصال. (${e.code})",
          "quotes": <String>[],
        });
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('askBookChat error: $e');
      setState(() {
        _messages.add({
          "role": "assistant",
          "text": "حدث خطأ أثناء الاتصال. حاول مرة أخرى.",
          "quotes": <String>[],
        });
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/back.png',
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: _titleTop,
              right: 0,
              left: 0,
              child: Center(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('audiobooks')
                      .doc(widget.bookId)
                      .snapshots(),
                  builder: (context, snap) {
                    final data =
                        snap.data?.data() as Map<String, dynamic>? ?? {};
                    final bookTitle = (data['title'] ?? '').toString().trim();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'مساعد قبس',
                          style: TextStyle(
                            color: _titleColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bookTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _titleColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: _backTop,
              right: 8,
              child: IconButton(
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Color(0xFF2F5145),
                  size: 20,
                ),
              ),
            ),
            Column(
              children: [
                const SizedBox(height: _chatStartTop),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_sending && i == _messages.length) {
                        return const _TypingRow();
                      }

                      final m = _messages[i];
                      final role = (m['role'] ?? '').toString();
                      final mine = role == 'user';
                      final text = (m['text'] ?? '').toString();
                      final quotes = (m['quotes'] is List)
                          ? (m['quotes'] as List)
                          .map((e) => e.toString())
                          .toList()
                          : <String>[];

                      return _ChatRow(
                        mine: mine,
                        text: text,
                        quotes: mine ? const [] : quotes,
                        bubbleColor: mine ? _bubbleUser : _bubbleBot,
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 44,
                          child: TextButton(
                            onPressed:
                            (_sending || _preparing) ? null : _send,
                            style: TextButton.styleFrom(
                              backgroundColor: _confirm,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _preparing
                                  ? '...'
                                  : (_sending ? '...' : 'إرسال'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 4,
                              enabled: !_preparing,
                              decoration: InputDecoration(
                                hintText: _preparing
                                    ? 'جارٍ تجهيز المساعد...'
                                    : 'اسأل عن هذا الكتاب...',
                                border: InputBorder.none,
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  final bool mine;
  final String text;
  final List<String> quotes;
  final Color bubbleColor;

  const _ChatRow({
    required this.mine,
    required this.text,
    required this.bubbleColor,
    this.quotes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(color: Colors.black87, height: 1.45),
          ),
          if (!mine && quotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Colors.black12),
            const SizedBox(height: 8),
            const Text(
              'اقتباسات من النص',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            ...quotes.take(3).map((q) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '“$q”',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colors.black87,
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
        mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [bubble],
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: _TypingBubble(),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFFFEEF1),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          '...',
          style: TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
