import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile_page.dart';
import 'main.dart'; // ✅ للرجوع إلى HomePage بعد تسجيل الخروج
import 'notifications_page.dart'; // ✅ صفحة الإشعارات
import 'weekly_goal_page.dart';
import 'ratings_page.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  // ألوان حسب هويتك
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm    = Color(0xFF6F8E63); // ✅ نفس لون التأكيد

  // --- نفس تدفق الخروج الموجود سابقًا (نفس النصوص/الألوان/الانتقال) ---
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('  متأكد من تسجيل الخروج؟    '),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _confirm,       // ✅ نفس اللون
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await _logout(context);
  }
  // ---------------------------------------------------------------------------

  Stream<_UserProfile> _profileStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // غير مسجّل: رجّع قيم افتراضية
      return Stream.value(const _UserProfile(name: 'الاسم'));
    }

    final uid = user.uid;
    final authName = user.displayName;
    final authPhoto = user.photoURL;

    // نراقب مستند Firestore: users/{uid}
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    return docRef.snapshots().map((snap) {
      final data = snap.data();
      final name = (data?['name'] as String?)?.trim();
      final photo = (data?['photoUrl'] as String?)?.trim();

      return _UserProfile(
        name: (name?.isNotEmpty == true)
            ? name!
            : (authName?.isNotEmpty == true ? authName! : 'الاسم'),
        photoUrl: (photo?.isNotEmpty == true)
            ? photo
            : (authPhoto?.isNotEmpty == true ? authPhoto : null),
      );
    }).handleError((_) {
      // لو صار خطأ، استخدم قيم Auth / الافتراضي
      return _UserProfile(
        name: (authName?.isNotEmpty == true ? authName! : 'الاسم'),
        photoUrl: (authPhoto?.isNotEmpty == true ? authPhoto : null),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // الخلفية "back" خلف كل شيء (حتى البار — تذكّري حاطين extendBody: true في الـ Scaffold)
        Positioned.fill(
          child: Image.asset(
            'assets/images/back.png',
            fit: BoxFit.cover,
          ),
        ),

        // المحتوى
        StreamBuilder<_UserProfile>(
          stream: _profileStream(),
          builder: (context, snap) {
            final profile = snap.data ?? const _UserProfile(name: 'الاسم');

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                children: [
                  const SizedBox(height: 200),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // الاسم + الأفـاتار على اليمين
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start, // RTL مع بروفايل
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.only(start: 20),
                                child: _Avatar(photoUrl: profile.photoUrl),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  profile.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _darkGreen,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // المستطيلات/الأزرار
                          _ProfileButton(
                            title: 'المعلومات الشخصية',
                            icon: Icons.badge_outlined,
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => EditProfilePage(),
                              ));
                            },
                          ),
                          _ProfileButton(
                            title: 'هدف الاستماع الأسبوعي',
                            icon: Icons.track_changes_outlined,
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(builder: (_) => const WeeklyGoalPage()),
                              );
                            },
                          ),
                          _ProfileButton(
                            title: 'تقييماتي',
                            icon: Icons.star_rate_outlined,
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(builder: (_) => const RatingsPage()),
                              );
                            },
                          ),
                          _ProfileButton(
                            title: 'الإشعارات',
                            icon: Icons.notifications_none_outlined,
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(builder: (_) => const NotificationsPage()),
                              );
                            },
                          ),
                          _ProfileButton(
                            title: 'تسجيل خروج',
                            icon: Icons.logout,
                            onTap: () => _confirmLogout(context), // ✅ نفس الحوار والانتقال
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  const _Avatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 38,
      backgroundColor: ProfileTab._lightGreen.withOpacity(0.9),
      backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
          ? NetworkImage(photoUrl!)
          : null,
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? Icon(Icons.person, size: 40, color: ProfileTab._darkGreen.withOpacity(0.75))
          : null,
    );
  }
}

/// زر/مستطيل أخضر فاتح بحواف دائرية
class _ProfileButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ProfileButton({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  static const Color _tileBg = ProfileTab._lightGreen;
  static const Color _darkGreen = ProfileTab._darkGreen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: _tileBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // أيقونة على اليمين (RTL)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 18, start: 12),
                child: Icon(icon, color: _darkGreen, size: 26),
              ),
              // العنوان في المنتصف تقريبًا
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.right, // ✅ يجعل النص على اليمين
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: _darkGreen,
                  ),
                ),
              ),
              const SizedBox(width: 56), // محاذاة بصرية
            ],
          ),
        ),
      ),
    );
  }
}

class _UserProfile {
  final String name;
  final String? photoUrl;
  const _UserProfile({required this.name, this.photoUrl});
}