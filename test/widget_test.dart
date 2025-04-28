import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_health_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (tester) async {
    await tester.pumpWidget(const MobileHealthApp());
    expect(find.text('Mobile Health MVP'), findsOneWidget);
  });
}
