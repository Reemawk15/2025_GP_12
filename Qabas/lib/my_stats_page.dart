import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_stats_tab.dart';

class MyStatsPage extends StatelessWidget {
  const MyStatsPage({super.key});

  static const Color _darkGreen = Color(0xFF0E3A2C);

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/back.png',
                fit: BoxFit.cover,
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 50, 16, 10),
                child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: _darkGreen,
                            size: 32,
                          ),
                        ),
                        const Expanded(
                          child: Center(
                            child: Text(
                              'إحصائياتي',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: _darkGreen,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60), // ⬅️ هذا ينزل المستطيلات

                  Expanded(
                    child: me == null
                        ? const Center(
                      child: Text(
                        'الرجاء تسجيل الدخول',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _darkGreen,
                        ),
                      ),
                    )
                        : UserStatsTab(uid: me.uid),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
