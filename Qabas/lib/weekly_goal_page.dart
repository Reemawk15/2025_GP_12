// weekly_goal_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklyGoalPage extends StatefulWidget {
  const WeeklyGoalPage({super.key});

  @override
  State<WeeklyGoalPage> createState() => _WeeklyGoalPageState();
}

class _WeeklyGoalPageState extends State<WeeklyGoalPage> {
  static const Color _darkGreen = Color(0xFF0E3A2C);
  static const Color _midGreen = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm = Color(0xFF6F8E63);

  String _selectedLevel = ''; // beginner | active | pro

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

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
        final mins = (data['weeklyGoalMinutes'] as num).toInt();
        if (mins >= 160)
          _selectedLevel = 'pro';
        else if (mins >= 100)
          _selectedLevel = 'active';
        else
          _selectedLevel = 'beginner';
        setState(() {});
      }
    } catch (_) {}
  }

  int _minutesFor(String level) {
    if (level.isEmpty) return 0;

    switch (level) {
      case 'beginner':
        return 80;
      case 'active':
        return 180;
      case 'pro':
        return 360;
      default:
        return 0;
    }
  }

  String _titleFor(String level) {
    if (level.isEmpty) return ''; // لو فاضي، ارجع فاضي

    switch (level) {
      case 'active':
        return 'مستمع نشيط';
      case 'pro':
        return 'مستمع محترف';
      case 'beginner':
        return 'مستمع مبتدئ';
      default:
        return '';
    }
  }

  String _descFor(String level) {
    if (level == 'beginner') return 'ساعة (٦٠ دقيقة) على الأقل أسبوعيًا';
    if (level == 'active') return 'ساعتان (١٢٠ دقيقة) على الأقل أسبوعيًا';
    return 'ثلاث ساعات (١٨٠ دقيقة) على الأقل أسبوعيًا';
  }

  /* Future<void> _loadCurrentGoal() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // 🎯 تحقق إذا الحقل موجود فعلاً
      if (snapshot.exists && snapshot.data()?['weeklyGoal'] != null) {
        setState(() {
          _selectedLevel = snapshot.data()!['weeklyGoal']['level'] ?? '';
        });
      }
      // 🔥 لو مو موجود، يظل _selectedLevel فاضي
    }*/

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('سجّل الدخول أولًا.')));
      return;
    }

    final userDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    if (_selectedLevel.isEmpty) {
      // 🔥 نحذف الحقل من Firebase
      await userDoc.update({'weeklyGoal': FieldValue.delete()}).catchError((
        error,
      ) {
        // لو المستند مو موجود، نعمل set فاضي
        return userDoc.set({}, SetOptions(merge: true));
      });

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إلغاء هدف الاستماع 🎧')));

      Navigator.pop(context, null);
    } else {
      // 🟢 المستخدم اختار هدف جديد
      int minutes = _minutesFor(_selectedLevel);

      await userDoc.set({
        'weeklyGoal': {
          'level': _selectedLevel,
          'minutes': minutes,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ هدف الاستماع 🎧')));

      Navigator.pop(context, minutes);
    }
  }

  Widget _goalTile(String level) {
    final bool selected = _selectedLevel == level;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        print('Selected: $_selectedLevel');

        setState(() {
          if (_selectedLevel == level) {
            _selectedLevel = ''; // إلغاء التحديد
          } else {
            _selectedLevel = level; // تحديد جديد
          }
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
          textDirection:
              TextDirection.rtl, // ضروري عشان النص والدائرة يكونوا يمين
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // الدائرة أولاً على اليمين
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _midGreen : _darkGreen,
                size: 22,
              ),
              const SizedBox(width: 10),

              // النص مباشرة بجانبها
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment
                      .start, // ← يخلي النص يبدأ من يمين الأيقونة مباشرة
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
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                18,
                200,
                18,
                40,
              ), // ↓ نزلنا الصفحة
              child: Column(
                children: [
                  // الكونتينر الأبيض (السهم ثم العنوان تحته، ثم الجملة التعريفية)
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
                        // زر الرجوع داخل الكونتينر — نفس ستايل الصفحات الثانية
                        Align(
                          alignment: AlignmentDirectional
                              .centerStart, // RTL: start = يمين
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

                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'حدد هدف الاستماع الأسبوعي',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16.5,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

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

                        const SizedBox(height: 30),

                        _goalTile('beginner'),
                        const SizedBox(height: 12),
                        _goalTile('active'),
                        const SizedBox(height: 12),
                        _goalTile('pro'),

                        // نزّل زر الحفظ شوي تحت
                        const SizedBox(height: 44),

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
