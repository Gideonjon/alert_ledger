import 'package:flutter_test/flutter_test.dart';
import 'package:alert_ledger/main.dart';

void main() {
  testWidgets('Alert Ledger app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AlertLedgerApp());
    await tester.pump();

    expect(find.byType(AlertLedgerApp), findsOneWidget);
  });
}
