import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service wrapper untuk jembatan komunikasi MethodChannel (`sleep_timer/native_control`)
/// menuju API sistem operasi Android (`DevicePolicyManager` dan `AudioManager`).
class NativeControlService {
  NativeControlService._internal();

  static final NativeControlService instance = NativeControlService._internal();

  factory NativeControlService() => instance;

  static const MethodChannel _channel = MethodChannel(
    'sleep_timer/native_control',
  );

  /// Memeriksa apakah izin Device Administrator (`lockNow`) saat ini aktif.
  Future<bool> checkAdmin() async {
    try {
      final bool? isActive = await _channel.invokeMethod<bool>('checkAdmin');
      return isActive ?? false;
    } on PlatformException catch (e) {
      debugPrint('NativeControlService.checkAdmin PlatformException: ${e.message}');
      return false;
    } on MissingPluginException catch (e) {
      debugPrint('NativeControlService.checkAdmin MissingPluginException: ${e.message}');
      return false;
    }
  }

  /// Membuka halaman sistem Android (`ACTION_ADD_DEVICE_ADMIN`) untuk meminta izin Device Admin.
  Future<bool> requestAdmin() async {
    try {
      final bool? launched = await _channel.invokeMethod<bool>('requestAdmin');
      return launched ?? false;
    } on PlatformException catch (e) {
      debugPrint('NativeControlService.requestAdmin PlatformException: ${e.message}');
      return false;
    } on MissingPluginException catch (e) {
      debugPrint('NativeControlService.requestAdmin MissingPluginException: ${e.message}');
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
      debugPrint('NativeControlService.revokeAdmin PlatformException: ${e.message}');
      return false;
    } on MissingPluginException catch (e) {
      debugPrint('NativeControlService.revokeAdmin MissingPluginException: ${e.message}');
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
      debugPrint('NativeControlService.muteAudio PlatformException: ${e.message}');
      return 0;
    } on MissingPluginException catch (e) {
      debugPrint('NativeControlService.muteAudio MissingPluginException: ${e.message}');
      return 0;
    }
  }

  /// Memulihkan volume `STREAM_MUSIC` ke level sebelum diredam (atau 50% volume maksimum).
  /// Mengembalikan level volume setelah dipulihkan.
  Future<int> restoreAudio() async {
    try {
      final int? restoredVolume = await _channel.invokeMethod<int>('restoreAudio');
      return restoredVolume ?? 0;
    } on PlatformException catch (e) {
      debugPrint('NativeControlService.restoreAudio PlatformException: ${e.message}');
      return 0;
    } on MissingPluginException catch (e) {
      debugPrint('NativeControlService.restoreAudio MissingPluginException: ${e.message}');
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
      debugPrint('NativeControlService.lockScreen PlatformException: ${e.message}');
      return false;
    } on MissingPluginException catch (e) {
      debugPrint('NativeControlService.lockScreen MissingPluginException: ${e.message}');
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
}
