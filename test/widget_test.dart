import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_timer_app/main.dart';

void main() {
  testWidgets('SleepTimerApp renders main navigation tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SleepTimerApp());

    expect(find.text('Timer Tidur Otomatis'), findsOneWidget);
    expect(find.text('Timer'), findsOneWidget);
    expect(find.text('Riwayat'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
  });
}
