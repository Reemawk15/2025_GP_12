// weekly_goal_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const _primary = Color(0xFF0E3A2C);
const _accent = Color(0xFF6F8E63);
const _pillGreen = Color(0xFFE6F0E0);
const _midPillGreen = Color(0xFFBFD6B5);

// retuer the weeklyGoal from database
Future<int> _getWeeklyGoalMinutesForMe() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();

  final data = doc.data() ?? {};
  final weeklyGoal = data['weeklyGoal'];

  if (weeklyGoal is! Map) return 0;

  final v = weeklyGoal['minutes'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;

  return 0;
}

Future<int> _getWeeklyListenedSecondsForMe() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 0;

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('stats')
      .doc('main')
      .get();

  final data = doc.data() ?? {};
  final v = data['weeklyListenedSeconds'] ?? data['weeklyListenedSeconds'];

  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

Widget _weeklyGoalBar() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const SizedBox.shrink();

  final statsRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('stats')
      .doc('main');

  return StreamBuilder<DocumentSnapshot>(
    stream: statsRef.snapshots(),
    builder: (context, snap) {
      final data = snap.data?.data() as Map<String, dynamic>? ?? {};
      final weeklySec =
          (data['weeklyListenedSeconds'] as num?)?.toInt() ??
              (data['weeklyListenedSeconds'] as num?)?.toInt() ??
              0;

      return FutureBuilder<int>(
        future: _getWeeklyGoalMinutesForMe(),
        builder: (context, g) {
          final goalMinutes = g.data ?? 0;
          final minutes = (weeklySec / 60).floor();
          final progress = (goalMinutes <= 0)
              ? 0.0
              : (minutes / goalMinutes).clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✅ Bar + Text inside
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 24, // زودناها شوي عشان النص يوضح داخل البار
                        backgroundColor: _pillGreen, // ✅ خلفية البار
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          _midPillGreen, // ✅ لون التعبئة
                        ),
                      ),

                      // ✅ Text inside the bar
                      Text(
                        '$minutes / $goalMinutes د',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: _primary, // ✅ لون النص
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class WeeklyGoalPage extends StatefulWidget {
  const WeeklyGoalPage({super.key});

  @override
  State<WeeklyGoalPage> createState() => _WeeklyGoalPageState();
}

class _WeeklyGoalPageState extends State<WeeklyGoalPage> {
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm    = Color(0xFF6F8E63);

  /// beginner | active | pro | '' (no goal selected)
  String _selectedLevel = '';

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  /// Unified SnackBar design used across the app
  void _showSnack(String message, {IconData icon = Icons.check_circle}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _confirm,                 // Same confirm color used in the page
        behavior: SnackBarBehavior.floating,       // Floating above the content
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFFE7C4DA),      // Light pink accent color for the icon
            ),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Load any existing weekly goal for the current user from Firestore
  Future<void> _loadExisting() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();

      if (data != null && data['weeklyGoal'] is Map) {
        final lvl = (data['weeklyGoal']['level'] as String?) ?? _selectedLevel;
        if (['beginner', 'active', 'pro'].contains(lvl)) {
          setState(() => _selectedLevel = lvl);
        }
      } else if (data != null && data['weeklyGoalMinutes'] != null) {
        // Support old field (if it exists)
        final mins = (data['weeklyGoalMinutes'] as num).toInt();
        if (mins >= 180) {
          _selectedLevel = 'pro';
        } else if (mins >= 120) {
          _selectedLevel = 'active';
        } else {
          _selectedLevel = 'beginner';
        }
        setState(() {});
      }
    } catch (_) {
      // Do not show an error to the user; the page still works fine without a saved goal
    }
  }

  /// Minutes for each level — matches the Arabic description shown in the UI
  int _minutesFor(String level) {
    switch (level) {
      case 'beginner':
        return 60;
      case 'active':
        return 120;
      case 'pro':
        return 180;
      default:
        return 0;
    }
  }

  /// Title text for each listening level (in Arabic, for display only)
  String _titleFor(String level) {
    switch (level) {
      case 'beginner':
        return 'مستمع مبتدئ';
      case 'active':
        return 'مستمع نشيط';
      case 'pro':
        return 'مستمع محترف';
      default:
        return '';
    }
  }

  /// Description text for each level (in Arabic, for display only)
  String _descFor(String level) {
    if (level == 'beginner') return 'ساعة (٦٠ دقيقة) على الأقل أسبوعيًا';
    if (level == 'active')   return 'ساعتان (١٢٠ دقيقة) على الأقل أسبوعيًا';
    return 'ثلاث ساعات (١٨٠ دقيقة) على الأقل أسبوعيًا';
  }

  /// Save the selected weekly goal (or remove it if no level selected)
  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('سجّل الدخول أولًا.', icon: Icons.login_rounded);
      return;
    }

    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

    if (_selectedLevel.isEmpty) {
      // Remove the weekly goal field completely
      await userDoc.update({'weeklyGoal': FieldValue.delete()}).catchError((_) {
        return userDoc.set({}, SetOptions(merge: true));
      });

      _showSnack('تم إلغاء هدف الاستماع ', icon: Icons.info_rounded);
      if (mounted) Navigator.pop<int?>(context, null);
      return;
    }

    // Save a new weekly goal based on the selected level
    final int minutes = _minutesFor(_selectedLevel);

    await userDoc.set({
      'weeklyGoal': {
        'level': _selectedLevel,
        'minutes': minutes,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    }, SetOptions(merge: true));

    _showSnack('تم حفظ هدف الاستماع', icon: Icons.check_circle);
    if (mounted) Navigator.pop<int>(context, minutes);
  }

  /// Single goal option tile (beginner / active / pro)
  Widget _goalTile(String level) {
    final bool selected = _selectedLevel == level;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        setState(() {
          // Tap again on the same tile to unselect / clear goal
          _selectedLevel = selected ? '' : level;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _confirm.withOpacity(0.28) : _lightGreen,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _confirm : Colors.transparent,
            width: 1.2,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: _confirm.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ]
              : [],
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _midGreen : _darkGreen,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start, // Start from the right of the icon in RTL
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _titleFor(level),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _darkGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 16.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _descFor(level),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: _darkGreen.withOpacity(0.85),
                        fontSize: 13.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          // Background image for the page
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 200, 18, 40),
              child: Column(
                children: [
                  // Main white card that contains the weekly goal content
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Back button inside the card
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: IconButton(
                            tooltip: 'رجوع',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.85),
                            ),
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            color: _darkGreen,
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        const SizedBox(height: 6),


                        const SizedBox(height: 25),

                        _weeklyGoalBar(),

                        const SizedBox(height: 25),

                        // Title
                        Align(
                          alignment: Alignment.centerRight,
                          child: const Text(
                            'حدد هدف الاستماع الأسبوعي',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtitle / helper text
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'ننصحك البدء بخطوة صغيرة لتكوين عادة ثابتة ومستمرّة',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: _darkGreen.withOpacity(0.85),
                              fontSize: 13.5,
                              height: 1.35,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Goal level tiles
                        _goalTile('beginner'),
                        const SizedBox(height: 12),
                        _goalTile('active'),
                        const SizedBox(height: 12),
                        _goalTile('pro'),

                        const SizedBox(height: 44),

                        // Save button
                        SizedBox(
                          width: 150,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _confirm,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            onPressed: _save,
                            child: const Text(
                              'حفظ',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
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
