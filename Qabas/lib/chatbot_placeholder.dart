import 'package:flutter/material.dart';

class ChatBotPlaceholderPage extends StatelessWidget {
  const ChatBotPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('مساعد قبس (قريباً)')),
        body: const Center(
          child: Text(
            '',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
