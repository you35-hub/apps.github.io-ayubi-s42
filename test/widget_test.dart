import 'package:flutter_test/flutter_test.dart';
import 'package:ayubi_s42/main.dart';

void main() {
  testWidgets('Ayubi_S42 app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const AyubiApp());
    expect(find.text('Ayubi_S42'), findsOneWidget);
  });
}