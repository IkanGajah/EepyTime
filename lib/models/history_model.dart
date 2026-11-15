class HistoryModel {
  final int? id;
  final String? sessionKey;
  final String presetLabel;
  final int durationSeconds;
  final String executedAt;
  final String? wokeUpAt;
  final int? sleepDurationSeconds;
  final bool isScreenLocked;
  final bool isAudioMuted;

  const HistoryModel({
    this.id,
    this.sessionKey,
    required this.presetLabel,
    required this.durationSeconds,
    required this.executedAt,
    this.wokeUpAt,
    this.sleepDurationSeconds,
    this.isScreenLocked = true,
    this.isAudioMuted = true,
  });

  HistoryModel copyWith({
    int? id,
    String? sessionKey,
    String? presetLabel,
    int? durationSeconds,
    String? executedAt,
    String? wokeUpAt,
    int? sleepDurationSeconds,
    bool? isScreenLocked,
    bool? isAudioMuted,
  }) {
    return HistoryModel(
      id: id ?? this.id,
      sessionKey: sessionKey ?? this.sessionKey,
      presetLabel: presetLabel ?? this.presetLabel,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      executedAt: executedAt ?? this.executedAt,
      wokeUpAt: wokeUpAt ?? this.wokeUpAt,
      sleepDurationSeconds: sleepDurationSeconds ?? this.sleepDurationSeconds,
      isScreenLocked: isScreenLocked ?? this.isScreenLocked,
      isAudioMuted: isAudioMuted ?? this.isAudioMuted,
    );
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = <String, dynamic>{
      'session_key': sessionKey,
      'preset_label': presetLabel,
      'duration_seconds': durationSeconds,
      'executed_at': executedAt,
      'woke_up_at': wokeUpAt,
      'sleep_duration_seconds': sleepDurationSeconds,
      'is_screen_locked': isScreenLocked ? 1 : 0,
      'is_audio_muted': isAudioMuted ? 1 : 0,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory HistoryModel.fromMap(Map<String, dynamic> map) {
    final Object? rawLocked = map['is_screen_locked'];
    final Object? rawMuted = map['is_audio_muted'];
    final Object? rawSleepSec = map['sleep_duration_seconds'];

    return HistoryModel(
      id: map['id'] as int?,
      sessionKey: map['session_key'] as String?,
      presetLabel: (map['preset_label'] as String?) ?? '',
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      executedAt: (map['executed_at'] as String?) ?? '',
      wokeUpAt: map['woke_up_at'] as String?,
      sleepDurationSeconds:
          rawSleepSec is num ? rawSleepSec.toInt() : null,
      isScreenLocked: rawLocked is bool ? rawLocked : (rawLocked == 1),
      isAudioMuted: rawMuted is bool ? rawMuted : (rawMuted == 1),
    );
  }

  @override
  String toString() {
    return 'HistoryModel(id: $id, sessionKey: $sessionKey, presetLabel: $presetLabel, durationSeconds: $durationSeconds, executedAt: $executedAt, wokeUpAt: $wokeUpAt, sleepDurationSeconds: $sleepDurationSeconds)';
  }
}
