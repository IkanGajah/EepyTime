import 'package:eepy_time/controllers/timer_controller.dart';
import 'package:eepy_time/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'EepyTimeApp renders cleanly on narrow phone width without overflow or +10m button',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const EepyTimeApp());
    await tester.pump();

    expect(find.text('EepyTime'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('+10m'), findsNothing);
    expect(
      find.text('Pilih Durasi Manual (JJ : MM : DD)'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Manual duration and Add Preset dialogs open and close cleanly on Batal and Confirm',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EepyTimeApp());
    await tester.pump();

    // 1. Open "Pilih Durasi Manual" and press "Batal"
    final Finder manualBtn = find.text('Pilih Durasi Manual (JJ : MM : DD)');
    await tester.ensureVisible(manualBtn);
    await tester.tap(manualBtn);
    await tester.pumpAndSettle();

    expect(find.text('Pilih Durasi Manual'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    // 2. Open "Pilih Durasi Manual", enter 5 minutes, press "Terapkan"
    await tester.tap(manualBtn);
    await tester.pumpAndSettle();

    final Finder textFields = find.byType(TextField);
    await tester.enterText(textFields.at(1), '5');
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(find.text('00:05:00'), findsOneWidget);

    // 3. Open "Tambah Preset" and press "Batal"
    final Finder addPresetBtn = find.text('Tambah Preset');
    await tester.ensureVisible(addPresetBtn);
    await tester.tap(addPresetBtn);
    await tester.pumpAndSettle();

    expect(find.text('Tambah Preset Durasi'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
  });

  test('TimerController defaults to 0 and resetTimer resets back to 0',
      () async {
    final TimerController controller = TimerController();
    addTearDown(controller.dispose);

    expect(controller.initialSeconds, 0);
    expect(controller.remainingSeconds, 0);
    expect(controller.formattedRemainingTime, '00:00:00');
    expect(controller.startOrPauseTimer(), isFalse);

    controller.selectDuration(30, 'Tes 30 Detik');
    expect(controller.remainingSeconds, 30);
    expect(controller.startOrPauseTimer(), isTrue);
    expect(controller.timerStatus, TimerStatus.running);

    controller.resetTimer();
    expect(controller.timerStatus, TimerStatus.idle);
    expect(controller.initialSeconds, 0);
    expect(controller.remainingSeconds, 0);
    expect(controller.formattedRemainingTime, '00:00:00');
  });
}
