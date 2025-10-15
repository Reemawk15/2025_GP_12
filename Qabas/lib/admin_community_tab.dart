import 'package:flutter/material.dart';

class AdminCommunityTab extends StatelessWidget {
  const AdminCommunityTab({super.key});

  static const Color _titleColor = Color(0xFFC9DABF); // نفس ألوان قَبَس الفاتحة
  static const _titleColor1  = Color(0xFF0E3A2C); // أخضر داكن للنصوص

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          // الخلفية
          Positioned.fill(
            child: Image.asset('assets/images/back.png', fit: BoxFit.cover),
          ),

          Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 300, // نزل السهم شوي
              leadingWidth: 56,
              leading: SafeArea(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8, top: 12),
                  child: IconButton(
                    tooltip: 'رجوع',
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _titleColor1,
                      size: 26,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
              title: const Padding(
                padding: EdgeInsets.only(top: 10), // نزل العنوان شوي
                child: Text(
                  'مجتمع الأدمن',
                  style: TextStyle(
                    color: _titleColor1,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              centerTitle: true,
            ),


            ),
        ],
      ),
    );
  }
}