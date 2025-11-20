// Profile tab (shows user info, buttons, logout, etc.)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'edit_profile_page.dart';
import 'main.dart';                // Return to HomePage after logout
import 'notifications_page.dart'; // Notifications screen
import 'weekly_goal_page.dart';
import 'ratings_page.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  // Theme colors (same identity colors)
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm    = Color(0xFF6F8E63);
  static const _titleColor       = _darkGreen;
  static const _confirmColor     = _confirm;

  // Logout → return to HomePage
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  // Confirmation dialog
  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تأكيد تسجيل الخروج',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _titleColor,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'هل أنت متأكد من أنك تريد تسجيل الخروج؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _confirmColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'تأكيد',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontSize: 16, color: _titleColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok == true) await _logout(context);
  }

  // Stream of user profile: name + photo
  Stream<_UserProfile> _profileStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(const _UserProfile(name: 'الاسم'));
    }

    final uid = user.uid;
    final authName = user.displayName;
    final authPhoto = user.photoURL;

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    return docRef.snapshots().map((snap) {
      final data  = snap.data();
      final name  = (data?['name'] as String?)?.trim();
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
        // Full background image
        Positioned.fill(
          child: Image.asset(
            'assets/images/back.png',
            fit: BoxFit.cover,
          ),
        ),

        // Profile content
        StreamBuilder<_UserProfile>(
          stream: _profileStream(),
          builder: (context, snap) {
            final profile = snap.data ?? const _UserProfile(name: 'الاسم');

            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                children: [
                  const SizedBox(height: 200),

                  // White rounded container
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
                          // Avatar + name
                          Row(
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.only(start: 20),
                                child: _Avatar(photoUrl: profile.photoUrl),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  profile.name,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _darkGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Profile options
                          _ProfileButton(
                            title: 'المعلومات الشخصية',
                            icon: Icons.badge_outlined,
                            onTap: () {
                              Navigator.push(context,
                                MaterialPageRoute(builder: (_) => EditProfilePage()),
                              );
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
                            onTap: () => _confirmLogout(context),
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

// Avatar component
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
          ? Icon(Icons.person, size: 40,
          color: ProfileTab._darkGreen.withOpacity(0.75))
          : null,
    );
  }
}

// Green profile button
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
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 18, start: 12),
                child: Icon(icon, color: _darkGreen, size: 26),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: _darkGreen,
                  ),
                ),
              ),
              const SizedBox(width: 56),
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
