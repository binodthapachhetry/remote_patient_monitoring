import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_health_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (tester) async {
    await tester.pumpWidget(const MobileHealthApp());
    // In the test environment permissions are not granted, so we cannot rely
    // on a specific child widget.  Assert that the root renders without error.
    expect(find.byType(MobileHealthApp), findsOneWidget);
  });
}
