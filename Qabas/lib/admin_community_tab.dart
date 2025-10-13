import 'package:flutter/material.dart';

class AdminCommunityTab extends StatelessWidget {
  const AdminCommunityTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('مجتمع الأدمن')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Text(
              'من هنا تدير منشورات المجتمع (مراجعة/حذف/تثبيت).',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),

          ],
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _AdminCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, textDirection: TextDirection.rtl),
        subtitle: Text(subtitle, textDirection: TextDirection.rtl),
        trailing: const Icon(Icons.chevron_left),
        onTap: () {},
      ),
    );
  }
}