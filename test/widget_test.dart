import 'dart:math' as math;

import 'package:eepy_time/controllers/timer_controller.dart';
import 'package:eepy_time/main.dart';
import 'package:eepy_time/models/history_model.dart';
import 'package:eepy_time/screens/history_tab_view.dart';
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

  testWidgets(
      'Interactive circular wheel sets minutes (60m per full rotation) and supports multiple rotations',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EepyTimeApp());
    await tester.pump();

    final Finder wheelHint = find.text('Geser roda • 60m/putaran');
    expect(wheelHint, findsOneWidget);

    final Finder customPaintFinder = find.ancestor(
      of: wheelHint,
      matching: find.byWidgetPredicate(
        (Widget w) => w is SizedBox && w.width == 256.0 && w.height == 256.0,
      ),
    );
    await tester.ensureVisible(customPaintFinder);
    final Offset center = tester.getCenter(customPaintFinder);
    const double ringRadius = 108.0;

    // Touch at 3 o'clock (15 minutes) and rotate clockwise 1 full turn (+60m -> 1h 15m)
    final Offset threeOClock = Offset(center.dx + ringRadius, center.dy);
    final TestGesture gesture = await tester.startGesture(threeOClock);
    await tester.pump();
    expect(find.text('00:15:00'), findsOneWidget);

    const int steps = 36;
    for (int i = 1; i <= steps; i++) {
      final double angle = (i / steps) * 2 * math.pi; // clockwise from 3 o'clock
      final Offset nextPos = Offset(
        center.dx + ringRadius * math.cos(angle),
        center.dy + ringRadius * math.sin(angle),
      );
      await gesture.moveTo(nextPos);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(find.text('01:15:00'), findsOneWidget);
    expect(find.text('Putaran 2 • 60m/putaran'), findsOneWidget);
  });

  testWidgets(
      'HistoryTabView displays actual sleep duration summary and omits redundant lock badges',
      (WidgetTester tester) async {
    final _FakeHistoryTimerController controller =
        _FakeHistoryTimerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: HistoryTabView(controller: controller),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ringkasan Kebiasaan Tidur'), findsOneWidget);
    expect(find.text('2 Sesi'), findsOneWidget);
    expect(find.text('14j 30m'), findsOneWidget);
    expect(find.text('7j 15m'), findsOneWidget);

    // Redundant lock/mute badges are removed
    expect(find.textContaining('Terkunci'), findsNothing);
    expect(find.text('Terkunci & Teredam'), findsNothing);

    // Actual sleep duration and timer badge are displayed cleanly
    expect(find.text('Tidur Cepat (15 Menit)'), findsOneWidget);
    expect(find.text('Tidur 7 Jam 15 Menit'), findsOneWidget);
    expect(find.text('Timer 15m'), findsOneWidget);
  });
}

class _FakeHistoryTimerController extends TimerController {
  @override
  Map<String, int> get habitSummary => const <String, int>{
        'totalSessions': 2,
        'totalSleepSeconds': 52200, // 14h 30m
        'averageSleepSeconds': 26100, // 7h 15m
      };

  @override
  List<HistoryModel> get historyList => const <HistoryModel>[
        HistoryModel(
          id: 1,
          sessionKey: 'sleep_1',
          presetLabel: 'Tidur Cepat (15 Menit)',
          durationSeconds: 900,
          executedAt: '2026-11-14T23:00:00.000',
          wokeUpAt: '2026-11-15T06:15:00.000',
          sleepDurationSeconds: 26100,
        ),
      ];
}
