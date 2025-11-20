// lib/notifications_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const Color _darkGreen  = Color(0xFF0E3A2C);
  static const Color _midGreen   = Color(0xFF2F5145);
  static const Color _lightGreen = Color(0xFFC9DABF);
  static const Color _confirm    = Color(0xFF6F8E63);

  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _enabled = (snap.data()?['notificationsEnabled'] ?? false) as bool;
      }
    } catch (_) {

    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(bool value) async {
    setState(() => _enabled = value);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'notificationsEnabled': value}, SetOptions(merge: true));
      }
    } catch (_) {

    }
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
            body: _loading
                ? Center(
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(_midGreen),
              ),
            )
                : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Column(
                children: [
                  const SizedBox(height: 190),

                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(

                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [

                          Align(
                            alignment: AlignmentDirectional.centerStart, // RTL: start = يمين
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


                          const SizedBox(height: 28),


                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F7F5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(end: 8),
                                  child: Icon(Icons.notifications, color: _confirm),
                                ),
                                const Expanded(
                                  child: Text(
                                    'تفعيل الإشعارات',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _enabled,

                                  activeTrackColor: _lightGreen,
                                  onChanged: (v) => _save(v),

                                  thumbColor: MaterialStateProperty.resolveWith<Color?>(
                                        (states) => states.contains(MaterialState.selected)
                                        ? _confirm
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Text(
                            'فعّل الإشعارات عشان نذكّرك وتحقّق هدفك القرائي بسهولة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
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