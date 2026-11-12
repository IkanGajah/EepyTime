import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/history_model.dart';
import '../models/preset_model.dart';
import '../services/native_control_service.dart';

enum TimerStatus {
  idle,
  running,
  paused,
}

class TimerController extends ChangeNotifier {
  final DatabaseHelper _databaseHelper;
  final NativeControlService _nativeControlService;

  Timer? _countdownTimer;

  int _initialSeconds = 900; // Default 15 Menit (900 detik)
  int _remainingSeconds = 900;
  String _activePresetLabel = 'Tidur Cepat (15 Menit)';
  TimerStatus _timerStatus = TimerStatus.idle;

  bool _isAdminActive = false;
  bool _isMuted = false;
  bool _isPitchBlack = false;
  bool _isHapticEnabled = true;
  bool _isInitialized = false;

  List<PresetModel> _presets = <PresetModel>[];
  List<HistoryModel> _historyList = <HistoryModel>[];
  Map<String, int> _habitSummary = const <String, int>{
    'totalSessions': 0,
    'successfulSessions': 0,
    'totalDurationSeconds': 0,
    'averageDurationSeconds': 0,
  };

  TimerController({
    DatabaseHelper? databaseHelper,
    NativeControlService? nativeControlService,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _nativeControlService =
            nativeControlService ?? NativeControlService.instance;

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  int get initialSeconds => _initialSeconds;
  int get remainingSeconds => _remainingSeconds;
  String get activePresetLabel => _activePresetLabel;
  TimerStatus get timerStatus => _timerStatus;

  bool get isAdminActive => _isAdminActive;
  bool get isMuted => _isMuted;
  bool get isPitchBlack => _isPitchBlack;
  bool get isHapticEnabled => _isHapticEnabled;
  bool get isInitialized => _isInitialized;

  List<PresetModel> get presets => List<PresetModel>.unmodifiable(_presets);
  List<HistoryModel> get historyList =>
      List<HistoryModel>.unmodifiable(_historyList);
  Map<String, int> get habitSummary =>
      Map<String, int>.unmodifiable(_habitSummary);

  double get progress {
    if (_initialSeconds <= 0) {
      return 0.0;
    }
    return (_remainingSeconds / _initialSeconds).clamp(0.0, 1.0);
  }

  String get formattedRemainingTime => formatDuration(_remainingSeconds);

  static String formatDuration(int totalSeconds) {
    final int safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final int hours = safeSeconds ~/ 3600;
    final int minutes = (safeSeconds % 3600) ~/ 60;
    final int seconds = safeSeconds % 60;

    final String hh = hours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  // ===========================================================================
  // INISIALISASI & SINKRONISASI DATA
  // ===========================================================================

  Future<void> initialize() async {
    await Future.wait(<Future<void>>[
      checkAdminStatus(),
      loadSettings(),
      loadPresets(),
      loadHistoryAndSummary(),
    ]);
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> checkAdminStatus() async {
    _isAdminActive = await _nativeControlService.checkAdmin();
    notifyListeners();
  }

  Future<void> requestAdminPermission() async {
    _triggerHaptic();
    await _nativeControlService.requestAdmin();
    await checkAdminStatus();
  }

  Future<bool> revokeAdminPermission() async {
    _triggerHaptic();
    final bool revoked = await _nativeControlService.revokeAdmin();
    await checkAdminStatus();
    return revoked;
  }

  Future<void> loadPresets() async {
    _presets = await _databaseHelper.getPresets();
    notifyListeners();
  }

  Future<void> addPreset(String label, int durationSeconds) async {
    if (label.trim().isEmpty || durationSeconds <= 0) {
      return;
    }
    _triggerHaptic();
    final PresetModel newPreset = PresetModel(
      label: label.trim(),
      durationSeconds: durationSeconds,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _databaseHelper.insertPreset(newPreset);
    await loadPresets();
  }

  Future<void> removePreset(int id) async {
    _triggerHaptic();
    await _databaseHelper.deletePreset(id);
    await loadPresets();
  }

  Future<void> loadHistoryAndSummary() async {
    _historyList = await _databaseHelper.getHistory();
    _habitSummary = await _databaseHelper.getHabitSummary();
    notifyListeners();
  }

  Future<void> clearAllHistory() async {
    _triggerHaptic();
    await _databaseHelper.clearHistory();
    await loadHistoryAndSummary();
  }

  Future<void> loadSettings() async {
    final String? pitchBlackVal =
        await _databaseHelper.getSetting('pitch_black_mode');
    final String? hapticVal =
        await _databaseHelper.getSetting('haptic_feedback');

    _isPitchBlack = pitchBlackVal == 'true';
    _isHapticEnabled = hapticVal != 'false';
    notifyListeners();
  }

  Future<void> togglePitchBlackMode(bool enabled) async {
    _isPitchBlack = enabled;
    notifyListeners();
    _triggerHaptic();
    await _databaseHelper.updateSetting(
      'pitch_black_mode',
      enabled ? 'true' : 'false',
    );
  }

  Future<void> toggleHapticFeedback(bool enabled) async {
    _isHapticEnabled = enabled;
    notifyListeners();
    if (enabled) {
      HapticFeedback.lightImpact();
    }
    await _databaseHelper.updateSetting(
      'haptic_feedback',
      enabled ? 'true' : 'false',
    );
  }

  // ===========================================================================
  // MESIN HITUNG MUNDUR (CORE TIMER ENGINE)
  // ===========================================================================

  /// Memilih durasi baru (baik dari input manual maupun kartu preset).
  void selectDuration(int seconds, String label) {
    if (seconds <= 0) {
      return;
    }
    _triggerHaptic();
    _countdownTimer?.cancel();
    _initialSeconds = seconds;
    _remainingSeconds = seconds;
    _activePresetLabel = label.trim().isEmpty ? 'Durasi Kustom' : label.trim();
    _timerStatus = TimerStatus.idle;
    notifyListeners();
  }

  /// Memulai atau menjeda hitung mundur tanpa kehilangan sisa detik.
  void startOrPauseTimer() {
    _triggerHaptic();

    if (_timerStatus == TimerStatus.running) {
      _countdownTimer?.cancel();
      _timerStatus = TimerStatus.paused;
      notifyListeners();
      return;
    }

    if (_remainingSeconds <= 0) {
      _remainingSeconds = _initialSeconds > 0 ? _initialSeconds : 900;
    }

    _timerStatus = TimerStatus.running;
    notifyListeners();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_remainingSeconds > 1) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        _remainingSeconds = 0;
        timer.cancel();
        _onTimerCompleted();
      }
    });
  }

  /// Mengembalikan angka hitung mundur ke nilai durasi awal yang dipilih.
  void resetTimer() {
    _triggerHaptic();
    _countdownTimer?.cancel();
    _remainingSeconds = _initialSeconds;
    _timerStatus = TimerStatus.idle;
    notifyListeners();
  }

  /// Dieksekusi otomatis tepat ketika `remainingSeconds` menyentuh `0`.
  Future<void> _onTimerCompleted() async {
    _timerStatus = TimerStatus.idle;
    notifyListeners();

    if (_isHapticEnabled) {
      HapticFeedback.heavyImpact();
    }

    final Map<String, bool> executionResult =
        await _nativeControlService.executeSleepAndMute();

    final bool mutedSuccess = executionResult['muted'] ?? true;
    final bool lockedSuccess = executionResult['locked'] ?? false;

    _isMuted = mutedSuccess;
    _isAdminActive = lockedSuccess || _isAdminActive;

    final HistoryModel completedSession = HistoryModel(
      presetLabel: _activePresetLabel,
      durationSeconds: _initialSeconds,
      executedAt: DateTime.now().toIso8601String(),
      isScreenLocked: lockedSuccess,
      isAudioMuted: mutedSuccess,
    );

    await _databaseHelper.insertHistory(completedSession);
    await loadHistoryAndSummary();

    // Kembalikan angka ke durasi awal agar siap dipakai kembali
    _remainingSeconds = _initialSeconds;
    notifyListeners();
  }

  // ===========================================================================
  // KONTROL CEPAT (ONE-TAP ACTIONS)
  // ===========================================================================

  /// Meredam suara media (`STREAM_MUSIC`) ke titik 0 secara instan.
  Future<int> oneTapMute() async {
    _triggerHaptic();
    final int previousVolume = await _nativeControlService.muteAudio();
    _isMuted = true;
    notifyListeners();
    return previousVolume;
  }

  /// Memulihkan suara media (`STREAM_MUSIC`) ke level sebelum diredam.
  Future<int> restoreAudio() async {
    _triggerHaptic();
    final int restoredVolume = await _nativeControlService.restoreAudio();
    _isMuted = false;
    notifyListeners();
    return restoredVolume;
  }

  /// Mengunci layar perangkat seketika menggunakan `DevicePolicyManager.lockNow()`.
  Future<bool> oneTapLock() async {
    _triggerHaptic();
    final bool locked = await _nativeControlService.lockScreen();
    if (!locked) {
      _isAdminActive = false;
      notifyListeners();
    }
    return locked;
  }

  void _triggerHaptic() {
    if (_isHapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
