import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai/main.dart';

void main() {
  testWidgets('Local AI app renders model manager', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LocalAiApp());
    await tester.pumpAndSettle();

    expect(find.text('Local AI'), findsWidgets);
    expect(find.text('Model Status'), findsOneWidget);
    expect(find.textContaining('Download Model'), findsOneWidget);
    await tester.pumpAndSettle();
    final Finder googleDriveText = find.textContaining('Google Drive setup:');
    if (googleDriveText.evaluate().isNotEmpty) {
      expect(googleDriveText, findsOneWidget);
    }
  });
}
