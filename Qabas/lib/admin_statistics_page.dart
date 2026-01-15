import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminStatisticsPage extends StatelessWidget {
  const AdminStatisticsPage({super.key});


  // Converting numbers to english
  String toArabicNumber(num number) {
    const arabicDigits = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
    return number
        .toString()
        .split('')
        .map((e) => arabicDigits[int.parse(e)])
        .join();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/adminstat.png',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 20),


                  //The three cards
                  FutureBuilder(
                    future: _fetchTopCardsData(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      final data = snapshot.data as Map<String, int>;

                      return Row(
                        children: [
                          _statCard(
                            context: context,
                            icon: Icons.group,
                            value: data['users']!,
                            label: 'أصدقاء قبس',
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            context: context,
                            icon: Icons.headphones,
                            value: data['books']!,
                            label: 'الكتب الصوتية',
                          ),
                          const SizedBox(width: 12),
                          _statCard(
                            context: context,
                            icon: Icons.menu_book,
                            value: data['clubs']!,
                            label: 'نوادي الكتب',
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 30),


                  // Bar Chart

                  _chartCard(
                    context: context,
                    title: 'أكثر ٣ تصنيفات للكتب المسموعة',
                    child: FutureBuilder(
                      future: _fetchTopCategories(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }

                        final data =
                        snapshot.data as List<Map<String, dynamic>>;

                        final maxValue = data
                            .map((e) => e['count'] as int)
                            .reduce((a, b) => a > b ? a : b);

                        return SizedBox(
                          height: 220,
                          child: BarChart(
                            BarChartData(
                              maxY: (maxValue + 1).toDouble(),
                              borderData: FlBorderData(show: false),
                              gridData: FlGridData(show: false),
                              titlesData: FlTitlesData(
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 1,
                                    getTitlesWidget: (value, meta) =>
                                        Text(toArabicNumber(value.toInt())),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 42,
                                    getTitlesWidget: (value, meta) => Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: SizedBox(
                                        width: 60,
                                        child: Text(
                                          data[value.toInt()]['category'],
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              barGroups: List.generate(data.length, (index) {
                                return BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: data[index]['count'].toDouble(),
                                      width: 24,
                                      borderRadius:
                                      BorderRadius.circular(12),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.8),
                                    ),
                                  ],
                                );
                              }),
                            ),
                            swapAnimationDuration:
                            const Duration(milliseconds: 900),
                            swapAnimationCurve: Curves.easeOutCubic,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 30),


                  /// Pie Chart (Animated)

                  _chartCard(
                    context: context,
                    title: 'الأندية',
                    child: FutureBuilder(
                      future: _fetchClubStatuses(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }

                        final data = snapshot.data as Map<String, int>;

                        return Column(
                          children: [
                            SizedBox(
                              height: 200,
                              child: AnimatedPieChart(data: data),
                            ),
                            const SizedBox(height: 24),
                            Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _legendDot(
                                  context,
                                  'المقبولة',
                                  Theme.of(context).colorScheme.primary,
                                ),
                                _legendDot(
                                  context,
                                  'قيد المراجعة',
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.6),
                                ),
                                _legendDot(
                                  context,
                                  'المرفوضة',
                                  Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                ),
                                _legendDot(
                                  context,
                                  'الملغاة',
                                  Colors.grey.shade500,
                                ),
                              ],
                            ),
                          ],
                        );
                      },
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


  // Widgets

  Widget _statCard({
    required BuildContext context,
    required IconData icon,
    required int value,
    required String label,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Text(
                toArabicNumber(value),
                key: ValueKey(value),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _chartCard({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 6, backgroundColor: color),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
  }


  // Firestore Logic


  Future<Map<String, int>> _fetchTopCardsData() async {
    final users =
    await FirebaseFirestore.instance.collection('users').count().get();
    final books =
    await FirebaseFirestore.instance.collection('audiobooks').count().get();
    final clubs = await FirebaseFirestore.instance
        .collection('clubRequests')
        .where('status', isEqualTo: 'accepted')
        .count()
        .get();

    return {
      'users': users.count ?? 0,
      'books': books.count ?? 0,
      'clubs': clubs.count ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> _fetchTopCategories() async {
    final snapshot =
    await FirebaseFirestore.instance.collection('audiobooks').get();

    Map<String, int> counter = {};

    for (var doc in snapshot.docs) {
      final category = doc['category'];
      counter[category] = (counter[category] ?? 0) + 1;
    }

    final sorted = counter.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(3).map((e) {
      return {'category': e.key, 'count': e.value};
    }).toList();
  }

  Future<Map<String, int>> _fetchClubStatuses() async {
    final snapshot =
    await FirebaseFirestore.instance.collection('clubRequests').get();

    Map<String, int> result = {
      'accepted': 0,
      'rejected': 0,
      'pending': 0,
      'canceled': 0,
    };

    for (var doc in snapshot.docs) {
      final status = doc['status'];
      if (result.containsKey(status)) {
        result[status] = result[status]! + 1;
      }
    }

    return result;
  }
}


// Animated Pie Chart

class AnimatedPieChart extends StatefulWidget {
  final Map<String, int> data;

  const AnimatedPieChart({super.key, required this.data});

  @override
  State<AnimatedPieChart> createState() => _AnimatedPieChartState();
}

class _AnimatedPieChartState extends State<AnimatedPieChart> {
  int touchedIndex = -1;

  String toArabicNumber(num number) {
    const arabicDigits = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
    return number
        .toString()
        .split('')
        .map((e) => arabicDigits[int.parse(e)])
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.data.values.fold(0, (a, b) => a + b);

    final values = [
      widget.data['accepted']!,
      widget.data['pending']!,
      widget.data['rejected']!,
      widget.data['canceled']!,
    ];

    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.primary.withOpacity(0.6),
      Theme.of(context).colorScheme.primary.withOpacity(0.3),
      Colors.grey.shade500,
    ];

    return PieChart(
      PieChartData(
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  response == null ||
                  response.touchedSection == null) {
                touchedIndex = -1;
              } else {
                touchedIndex =
                    response.touchedSection!.touchedSectionIndex;
              }
            });
          },
        ),
        centerSpaceRadius: 55,
        sectionsSpace: 2,
        sections: List.generate(4, (i) {
          final isTouched = i == touchedIndex;
          final value = values[i];
          final percentage =
          total == 0 ? 0 : (value / total * 100).round();

          return PieChartSectionData(
            value: value.toDouble(),
            color: colors[i],
            radius: isTouched ? 75 : 65,
            title: '${toArabicNumber(percentage)}٪',
            titleStyle: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isTouched ? 18 : 14,
            ),
          );
        }),
      ),
      swapAnimationDuration: const Duration(milliseconds: 900),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

