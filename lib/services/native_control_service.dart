import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef NativeTimerEventHandler = Future<void> Function(
  Map<String, Object?> payload,
);

/// Service wrapper untuk jembatan komunikasi MethodChannel (`eepy_time/native_control`)
/// menuju API sistem operasi Android (`DevicePolicyManager`, `AudioManager`,
/// `AlarmManager`, dan `TimerForegroundService`).
class NativeControlService {
  NativeControlService._internal() {
    _channel.setMethodCallHandler(_handleIncomingCall);
  }

  static final NativeControlService instance = NativeControlService._internal();

  factory NativeControlService() => instance;

  static const MethodChannel _channel = MethodChannel(
    'eepy_time/native_control',
  );

  NativeTimerEventHandler? _eventHandler;

  void setNativeTimerEventHandler(NativeTimerEventHandler? handler) {
    _eventHandler = handler;
  }

  Future<dynamic> _handleIncomingCall(MethodCall call) async {
    if (call.method == 'onNativeTimerEvent') {
      final Object? rawArgs = call.arguments;
      if (rawArgs is Map<Object?, Object?> && _eventHandler != null) {
        final Map<String, Object?> normalized = <String, Object?>{};
        rawArgs.forEach((Object? key, Object? value) {
          if (key is String) {
            normalized[key] = value;
          }
        });
        await _eventHandler!(normalized);
      }
    }
    return null;
  }

  /// Memeriksa apakah izin Device Administrator (`lockNow`) saat ini aktif.
  Future<bool> checkAdmin() async {
    try {
      final bool? isActive = await _channel.invokeMethod<bool>('checkAdmin');
      return isActive ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.checkAdmin PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.checkAdmin MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Membuka halaman sistem Android (`ACTION_ADD_DEVICE_ADMIN`) untuk meminta izin Device Admin.
  Future<bool> requestAdmin() async {
    try {
      final bool? launched = await _channel.invokeMethod<bool>('requestAdmin');
      return launched ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.requestAdmin PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.requestAdmin MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Mencabut hak akses Device Administrator (`removeActiveAdmin`) agar aplikasi
  /// dapat dicopot pemasangannya (uninstall) dengan mudah bila diperlukan.
  Future<bool> revokeAdmin() async {
    try {
      final bool? revoked = await _channel.invokeMethod<bool>('revokeAdmin');
      return revoked ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.revokeAdmin PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.revokeAdmin MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Meredam volume `STREAM_MUSIC` menjadi 0 setelah menyimpan level volume terakhir.
  /// Mengembalikan level volume sebelum diredam.
  Future<int> muteAudio() async {
    try {
      final int? previousVolume = await _channel.invokeMethod<int>('muteAudio');
      return previousVolume ?? 0;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.muteAudio PlatformException: ${e.message}',
      );
      return 0;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.muteAudio MissingPluginException: ${e.message}',
      );
      return 0;
    }
  }

  /// Memulihkan volume `STREAM_MUSIC` ke level sebelum diredam (atau 50% volume maksimum).
  /// Mengembalikan level volume setelah dipulihkan.
  Future<int> restoreAudio() async {
    try {
      final int? restoredVolume =
          await _channel.invokeMethod<int>('restoreAudio');
      return restoredVolume ?? 0;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.restoreAudio PlatformException: ${e.message}',
      );
      return 0;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.restoreAudio MissingPluginException: ${e.message}',
      );
      return 0;
    }
  }

  /// Mengunci layar perangkat seketika menggunakan `DevicePolicyManager.lockNow()`.
  /// Mengembalikan `true` jika layar berhasil dikunci, atau `false` jika izin belum aktif.
  Future<bool> lockScreen() async {
    try {
      final bool? isLocked = await _channel.invokeMethod<bool>('lockScreen');
      return isLocked ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.lockScreen PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.lockScreen MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Mengeksekusi peredaman suara (`muteAudio`) sekaligus penguncian layar (`lockScreen`)
  /// secara berurutan ketika waktu hitung mundur habis.
  /// Mengembalikan Map `{'muted': bool, 'locked': bool}`.
  Future<Map<String, bool>> executeSleepAndMute() async {
    try {
      final Map<Object?, Object?>? rawResult = await _channel
          .invokeMethod<Map<Object?, Object?>>('executeSleepAndMute');

      if (rawResult == null) {
        return const <String, bool>{'muted': false, 'locked': false};
      }

      return <String, bool>{
        'muted': rawResult['muted'] == true,
        'locked': rawResult['locked'] == true,
      };
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.executeSleepAndMute PlatformException: ${e.message}',
      );
      return const <String, bool>{'muted': false, 'locked': false};
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.executeSleepAndMute MissingPluginException: ${e.message}',
      );
      return const <String, bool>{'muted': false, 'locked': false};
    }
  }

  /// Memulai atau memperbarui notifikasi foreground service dan alarm batas waktu native.
  Future<bool> startNativeTimer({
    required int deadlineMs,
    required int initialSeconds,
    required String presetLabel,
    bool toastEnabled = true,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'startNativeTimer',
        <String, Object>{
          'deadlineMs': deadlineMs,
          'initialSeconds': initialSeconds,
          'presetLabel': presetLabel,
          'toastEnabled': toastEnabled,
        },
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.startNativeTimer PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.startNativeTimer MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Mengatur status aktif/nonaktif notifikasi Toast native Android.
  Future<bool> setNativeToastEnabled(bool enabled) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'setNativeToastEnabled',
        <String, Object>{'enabled': enabled},
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.setNativeToastEnabled PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.setNativeToastEnabled MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Menjeda notifikasi foreground service dan membatalkan alarm batas waktu native.
  Future<bool> pauseNativeTimer({
    required int remainingSeconds,
    required int initialSeconds,
    required String presetLabel,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'pauseNativeTimer',
        <String, Object>{
          'remainingSeconds': remainingSeconds,
          'initialSeconds': initialSeconds,
          'presetLabel': presetLabel,
        },
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.pauseNativeTimer PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.pauseNativeTimer MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Menghentikan notifikasi foreground service dan membatalkan alarm native.
  Future<bool> stopNativeTimer() async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('stopNativeTimer');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.stopNativeTimer PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.stopNativeTimer MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Menambah durasi timer aktif pada sisi native (mis. +600 detik / 10 menit).
  Future<bool> extendNativeTimer({int additionalSeconds = 600}) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'extendNativeTimer',
        <String, Object>{'additionalSeconds': additionalSeconds},
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.extendNativeTimer PlatformException: ${e.message}',
      );
      return false;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.extendNativeTimer MissingPluginException: ${e.message}',
      );
      return false;
    }
  }

  /// Mengambil status timer & antrean penyelesaian sesi dari sisi native Android.
  Future<Map<String, Object?>?> getNativeTimerState() async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getNativeTimerState');
      if (raw == null) {
        return null;
      }
      final Map<String, Object?> normalized = <String, Object?>{};
      raw.forEach((Object? key, Object? value) {
        if (key is String) {
          normalized[key] = value;
        }
      });
      return normalized;
    } on PlatformException catch (e) {
      debugPrint(
        'NativeControlService.getNativeTimerState PlatformException: ${e.message}',
      );
      return null;
    } on MissingPluginException catch (e) {
      debugPrint(
        'NativeControlService.getNativeTimerState MissingPluginException: ${e.message}',
      );
      return null;
    }
  }
}
