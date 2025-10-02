// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.
import 'package:flutter_test/flutter_test.dart';
import 'package:qabas/main.dart';

void main() {
  testWidgets('الصفحة الرئيسية تعرض أزرار التسجيل والدخول', (WidgetTester tester) async {
    await tester.pumpWidget(const QabasApp());

    expect(find.text('تسجيل مستخدم جديد'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });
}
