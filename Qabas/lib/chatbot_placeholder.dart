import 'package:flutter/material.dart';

class ChatBotPlaceholderPage extends StatelessWidget {
  const ChatBotPlaceholderPage({super.key});

  static const Color _darkGreen = Color(0xFF0E3A2C);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية
          Positioned.fill(
            child: Image.asset(
              'assets/images/back.png',
              fit: BoxFit.cover,
            ),
          ),

          Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                const SizedBox(height: 180),

                const Center(
                  child: Text(
                    'مساعد قبس',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _darkGreen,
                    ),
                  ),
                ),

                const SizedBox(height: 250),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Text(
                      'هنا سيظهر مساعد قبس قريبًا لمساعدتك في أسئلتك حول الكتب.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            top: 110,
            right: 11,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: _darkGreen,
                size: 22,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}