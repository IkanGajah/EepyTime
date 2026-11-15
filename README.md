# EepyTime

**EepyTime** is an offline-first Android sleep & mute timer utility built with **Flutter** and native **Kotlin** OS policies (`DevicePolicyManager`, `AudioManager`, `AlarmManager`, and `ForegroundService`).

Unlike app-specific sleep timers, **EepyTime** operates at the Android OS policy layer: when the countdown reaches zero, it suppresses all media audio (`STREAM_MUSIC` → `0`) and force-locks the screen (`lockNow()`) even when video apps hold a `WAKELOCK`, then automatically restores your previous media volume the next time you unlock your phone.

---

## Key Features

- **Deadline-Based Countdown + Exact Wakeup Alarm:** Survives backgrounding and Android Doze mode using wall-clock deadlines and `AlarmManager.setExactAndAllowWhileIdle()`.
- **Live Persistent Notification:** Native Android countdown chronometer in the notification shade with 3 quick-action buttons (**Stop**, **Tidur Sekarang**, **+10 Menit**).
- **Universal Media Mute & Auto-Restore:** Silences `STREAM_MUSIC` on completion (leaving morning alarms untouched) and automatically restores your saved volume upon unlocking (`ACTION_USER_PRESENT`).
- **Force Screen-Lock (`DevicePolicyManager`):** Guided first-time onboarding, top-priority permission status banner, and one-tap permission revocation for easy uninstallation.
- **Preset CRUD & Habit Analytics (SQLite):** Custom duration presets, reverse-chronological session history, and SQL-aggregated sleep timer metrics.
- **AMOLED Pitch Black Mode:** True `#000000` dark theme for nighttime OLED battery savings, plus configurable Haptic Feedback and Toast notifications.

---

## Project Structure

```text
lib/
├── main.dart                          # Entry point, theme, navigation & onboarding
├── controllers/timer_controller.dart  # Deadline countdown state & native sync
├── database/database_helper.dart      # SQLite (eepy_time.db) CRUD & analytics
├── models/                            # PresetModel & HistoryModel
├── screens/                           # Timer, History & Settings tabs
└── services/native_control_service.dart # Bidirectional MethodChannel wrapper

android/app/src/main/kotlin/com/pkb/eepy_time/
└── MainActivity.kt                    # DeviceAdmin, AudioManager, AlarmManager & ForegroundService
```

---

## Getting Started

Requirements:
- Flutter SDK `^3.13.5`
- Android device or emulator running **Android 8.0 (API 26)+**

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
