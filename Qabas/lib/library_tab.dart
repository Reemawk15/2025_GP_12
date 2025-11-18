import 'package:flutter/material.dart';
import 'my_library.dart';
import 'my_books.dart';

const Color _darkGreen  = Color(0xFF0E3A2C);
const Color _midGreen   = Color(0xFF2F5145);
const Color _lightGreen = Color(0xFFC9DABF);
const _confirmColor = Color(0xFF6F8E63);

class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/back_private.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 8, // Thin bar with no title
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionCard(
                        title: 'مكتبتي الخاصة',
                        subtitle: 'يمكنك إدارة مكتبتك في قَبَس وإضافة الكتب الصوتية بالضغط على الزر أدناه',
                        buttonText: 'مكتبتي',
                        onPressed: () {
                          // Navigate to a separate page
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyLibraryPage()),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _ActionCard(
                        title: 'إضافة كتب',
                        subtitle: 'إضافة كتابك الخاص',
                        buttonText: 'أضف كتاب جديد',
                        onPressed: () {
                          // Navigate to a separate page
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MyBooksPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Action card widget
class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160, // Fixed card height
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      decoration: BoxDecoration(
        color: _lightGreen.withOpacity(0.88),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute title/subtitle and button
        children: [
          Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _darkGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 2, // Prevents overflow
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _confirmColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                elevation: 0,
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
