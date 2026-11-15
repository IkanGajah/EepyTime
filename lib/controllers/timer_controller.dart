import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../database/database_helper.dart';
import '../models/history_model.dart';
import '../models/preset_model.dart';
import '../services/native_control_service.dart';

enum TimerStatus {
  idle,
  running,
  paused,
}

class TimerController extends ChangeNotifier with WidgetsBindingObserver {
  final DatabaseHelper _databaseHelper;
  final NativeControlService _nativeControlService;

  Timer? _countdownTimer;
  DateTime? _deadline;

  static const String defaultIdleLabel = 'Pilih Durasi / Preset';

  int _initialSeconds = 0;
  int _remainingSeconds = 0;
  String _activePresetLabel = defaultIdleLabel;
  TimerStatus _timerStatus = TimerStatus.idle;

  bool _isAdminActive = false;
  bool _isMuted = false;
  bool _isPitchBlack = false;
  bool _isHapticEnabled = true;
  bool _isToastEnabled = true;
  bool _hasCompletedOnboarding = false;
  bool _isInitialized = false;
  bool _isObservingLifecycle = false;
  bool _isCompleting = false;

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
            nativeControlService ?? NativeControlService.instance {
    _nativeControlService.setNativeTimerEventHandler(_onNativeTimerEvent);
  }

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  int get initialSeconds => _initialSeconds;
  int get remainingSeconds => _remainingSeconds;
  String get activePresetLabel => _activePresetLabel;
  TimerStatus get timerStatus => _timerStatus;
  DateTime? get deadline => _deadline;

  bool get isAdminActive => _isAdminActive;
  bool get isMuted => _isMuted;
  bool get isPitchBlack => _isPitchBlack;
  bool get isHapticEnabled => _isHapticEnabled;
  bool get isToastEnabled => _isToastEnabled;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
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
  // INISIALISASI, LIFECYCLE, & SINKRONISASI DATA
  // ===========================================================================

  Future<void> initialize() async {
    if (!_isObservingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _isObservingLifecycle = true;
    }

    await Future.wait(<Future<void>>[
      checkAdminStatus(),
      loadSettings(),
      loadPresets(),
      loadHistoryAndSummary(),
    ]);

    await syncWithNativeState();
    _isInitialized = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkAdminStatus();
      syncWithNativeState();
      if (_timerStatus == TimerStatus.running) {
        _syncFromClock();
      }
    }
  }

  Future<void> syncWithNativeState() async {
    final Map<String, Object?>? nativeState =
        await _nativeControlService.getNativeTimerState();
    if (nativeState == null) {
      return;
    }
    await _applyNativeStateMap(nativeState);
  }

  Future<void> _onNativeTimerEvent(Map<String, Object?> payload) async {
    await _applyNativeStateMap(payload);
  }

  Future<void> _applyNativeStateMap(Map<String, Object?> stateMap) async {
    // 1. Flush any completions executed natively (e.g. "Tidur Sekarang" button or background alarm)
    final Object? rawPending = stateMap['pendingCompletions'];
    bool insertedAny = false;
    if (rawPending is List<Object?> && rawPending.isNotEmpty) {
      for (final Object? item in rawPending) {
        if (item is Map<Object?, Object?>) {
          final String label =
              (item['presetLabel'] as String?) ?? _activePresetLabel;
          final int duration =
              (item['durationSeconds'] as num?)?.toInt() ?? _initialSeconds;
          final String executedAt = (item['executedAt'] as String?) ??
              DateTime.now().toIso8601String();
          final bool locked = item['isScreenLocked'] == true;
          final bool muted = item['isAudioMuted'] != false;

          await _databaseHelper.insertHistory(
            HistoryModel(
              presetLabel: label,
              durationSeconds: duration,
              executedAt: executedAt,
              isScreenLocked: locked,
              isAudioMuted: muted,
            ),
          );
          insertedAny = true;
        }
      }
    }
    if (insertedAny) {
      await loadHistoryAndSummary();
    }

    // 2. Sync mute flag
    if (stateMap.containsKey('isMuted')) {
      _isMuted = stateMap['isMuted'] == true;
    }

    // 3. Sync timer state
    final String? statusStr = stateMap['status'] as String?;
    final int nativeInitial =
        (stateMap['initialSeconds'] as num?)?.toInt() ?? _initialSeconds;
    final String? nativeLabel = stateMap['presetLabel'] as String?;
    final int deadlineMs = (stateMap['deadlineMs'] as num?)?.toInt() ?? 0;
    final int pausedRem =
        (stateMap['pausedRemainingSeconds'] as num?)?.toInt() ?? 0;

    if (statusStr == 'running' && deadlineMs > 0) {
      _initialSeconds = nativeInitial > 0 ? nativeInitial : _initialSeconds;
      if (nativeLabel != null && nativeLabel.isNotEmpty) {
        _activePresetLabel = nativeLabel;
      }
      _deadline = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
      _timerStatus = TimerStatus.running;
      _syncFromClock();
      _ensureHeartbeatRunning();
    } else if (statusStr == 'paused') {
      _countdownTimer?.cancel();
      _deadline = null;
      _initialSeconds = nativeInitial > 0 ? nativeInitial : _initialSeconds;
      if (nativeLabel != null && nativeLabel.isNotEmpty) {
        _activePresetLabel = nativeLabel;
      }
      _remainingSeconds = pausedRem > 0 ? pausedRem : _remainingSeconds;
      _timerStatus = TimerStatus.paused;
      notifyListeners();
    } else if (statusStr == 'idle' && _timerStatus != TimerStatus.idle) {
      _countdownTimer?.cancel();
      _deadline = null;
      _timerStatus = TimerStatus.idle;
      _initialSeconds = 0;
      _remainingSeconds = 0;
      _activePresetLabel = defaultIdleLabel;
      notifyListeners();
    } else {
      notifyListeners();
    }
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
    final String? toastVal =
        await _databaseHelper.getSetting('toast_notifications');
    final String? onboardingVal =
        await _databaseHelper.getSetting('onboarding_completed');

    _isPitchBlack = pitchBlackVal == 'true';
    _isHapticEnabled = hapticVal != 'false';
    _isToastEnabled = toastVal != 'false';
    _hasCompletedOnboarding = onboardingVal == 'true';
    await _nativeControlService.setNativeToastEnabled(_isToastEnabled);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _hasCompletedOnboarding = true;
    notifyListeners();
    await _databaseHelper.updateSetting('onboarding_completed', 'true');
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

  Future<void> toggleToastNotifications(bool enabled) async {
    _isToastEnabled = enabled;
    notifyListeners();
    _triggerHaptic();
    await _nativeControlService.setNativeToastEnabled(enabled);
    await _databaseHelper.updateSetting(
      'toast_notifications',
      enabled ? 'true' : 'false',
    );
  }

  // ===========================================================================
  // MESIN HITUNG MUNDUR BERBASIS DEADLINE (DEADLINE-BASED TIMER ENGINE)
  // ===========================================================================

  /// Memilih durasi baru (baik dari input manual maupun kartu preset).
  void selectDuration(int seconds, String label) {
    if (seconds <= 0) {
      return;
    }
    _triggerHaptic();
    _countdownTimer?.cancel();
    _deadline = null;
    _initialSeconds = seconds;
    _remainingSeconds = seconds;
    _activePresetLabel = label.trim().isEmpty ? 'Durasi Kustom' : label.trim();
    _timerStatus = TimerStatus.idle;
    _nativeControlService.stopNativeTimer();
    notifyListeners();
  }

  /// Memulai atau menjeda hitung mundur berbasis waktu selesai (`_deadline`).
  /// Mengembalikan `false` jika belum ada durasi (> 0 detik) yang dipilih.
  bool startOrPauseTimer() {
    if (_timerStatus == TimerStatus.running) {
      _triggerHaptic();
      _syncFromClock(allowCompletion: false);
      _countdownTimer?.cancel();
      _deadline = null;
      _timerStatus = TimerStatus.paused;
      _nativeControlService.pauseNativeTimer(
        remainingSeconds: _remainingSeconds,
        initialSeconds: _initialSeconds,
        presetLabel: _activePresetLabel,
      );
      notifyListeners();
      return true;
    }

    if (_remainingSeconds <= 0) {
      if (_initialSeconds > 0) {
        _remainingSeconds = _initialSeconds;
      } else {
        return false;
      }
    }

    _triggerHaptic();
    _deadline = DateTime.now().add(Duration(seconds: _remainingSeconds));
    _timerStatus = TimerStatus.running;
    notifyListeners();

    _nativeControlService.startNativeTimer(
      deadlineMs: _deadline!.millisecondsSinceEpoch,
      initialSeconds: _initialSeconds,
      presetLabel: _activePresetLabel,
      toastEnabled: _isToastEnabled,
    );

    _ensureHeartbeatRunning();
    return true;
  }

  /// Menambah durasi timer (mis. +10 menit / 600 detik).
  void extendTimer({int additionalSeconds = 600}) {
    if (additionalSeconds <= 0) {
      return;
    }
    _triggerHaptic();
    _initialSeconds += additionalSeconds;
    if (_timerStatus == TimerStatus.running && _deadline != null) {
      final DateTime now = DateTime.now();
      final DateTime base = _deadline!.isAfter(now) ? _deadline! : now;
      _deadline = base.add(Duration(seconds: additionalSeconds));
      _syncFromClock(allowCompletion: false);
      _nativeControlService.extendNativeTimer(
        additionalSeconds: additionalSeconds,
      );
    } else {
      _remainingSeconds += additionalSeconds;
      if (_timerStatus == TimerStatus.paused) {
        _nativeControlService.pauseNativeTimer(
          remainingSeconds: _remainingSeconds,
          initialSeconds: _initialSeconds,
          presetLabel: _activePresetLabel,
        );
      }
      notifyListeners();
    }
  }

  void _ensureHeartbeatRunning() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _syncFromClock(),
    );
  }

  void _syncFromClock({bool allowCompletion = true}) {
    final DateTime? target = _deadline;
    if (target == null) {
      return;
    }

    final int diffMs = target.difference(DateTime.now()).inMilliseconds;
    if (diffMs <= 0 && allowCompletion) {
      _countdownTimer?.cancel();
      _deadline = null;
      _remainingSeconds = 0;
      notifyListeners();
      _onTimerCompleted();
      return;
    }

    final int computedSeconds = diffMs <= 0 ? 0 : ((diffMs + 999) ~/ 1000);
    if (computedSeconds != _remainingSeconds) {
      _remainingSeconds = computedSeconds;
      notifyListeners();
    }
  }

  /// Mengembalikan angka hitung mundur kembali ke 0 (`00:00:00`).
  void resetTimer() {
    _triggerHaptic();
    _countdownTimer?.cancel();
    _deadline = null;
    _initialSeconds = 0;
    _remainingSeconds = 0;
    _activePresetLabel = defaultIdleLabel;
    _timerStatus = TimerStatus.idle;
    _nativeControlService.stopNativeTimer();
    notifyListeners();
  }

  /// Dieksekusi otomatis tepat ketika batas waktu (`_deadline`) tercapai.
  Future<void> _onTimerCompleted() async {
    if (_isCompleting) {
      return;
    }
    _isCompleting = true;
    try {
      final String completedLabel = _activePresetLabel;
      final int completedDuration = _initialSeconds;

      _timerStatus = TimerStatus.idle;
      _deadline = null;
      notifyListeners();

      await _nativeControlService.stopNativeTimer();

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
        presetLabel: completedLabel,
        durationSeconds: completedDuration,
        executedAt: DateTime.now().toIso8601String(),
        isScreenLocked: lockedSuccess,
        isAudioMuted: mutedSuccess,
      );

      await _databaseHelper.insertHistory(completedSession);
      await loadHistoryAndSummary();

      _initialSeconds = 0;
      _remainingSeconds = 0;
      _activePresetLabel = defaultIdleLabel;
      notifyListeners();
    } finally {
      _isCompleting = false;
    }
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
    if (_isObservingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _isObservingLifecycle = false;
    }
    _nativeControlService.setNativeTimerEventHandler(null);
    _countdownTimer?.cancel();
    super.dispose();
  }
}
