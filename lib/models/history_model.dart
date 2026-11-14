class HistoryModel {
  final int? id;
  final String presetLabel;
  final int durationSeconds;
  final String executedAt;
  final bool isScreenLocked;
  final bool isAudioMuted;

  const HistoryModel({
    this.id,
    required this.presetLabel,
    required this.durationSeconds,
    required this.executedAt,
    this.isScreenLocked = true,
    this.isAudioMuted = true,
  });

  HistoryModel copyWith({
    int? id,
    String? presetLabel,
    int? durationSeconds,
    String? executedAt,
    bool? isScreenLocked,
    bool? isAudioMuted,
  }) {
    return HistoryModel(
      id: id ?? this.id,
      presetLabel: presetLabel ?? this.presetLabel,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      executedAt: executedAt ?? this.executedAt,
      isScreenLocked: isScreenLocked ?? this.isScreenLocked,
      isAudioMuted: isAudioMuted ?? this.isAudioMuted,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'preset_label': presetLabel,
      'duration_seconds': durationSeconds,
      'executed_at': executedAt,
      'is_screen_locked': isScreenLocked ? 1 : 0,
      'is_audio_muted': isAudioMuted ? 1 : 0,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory HistoryModel.fromMap(Map<String, dynamic> map) {
    final rawLocked = map['is_screen_locked'];
    final rawMuted = map['is_audio_muted'];

    return HistoryModel(
      id: map['id'] as int?,
      presetLabel: (map['preset_label'] as String?) ?? '',
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      executedAt: (map['executed_at'] as String?) ?? '',
      isScreenLocked: rawLocked is bool ? rawLocked : (rawLocked == 1),
      isAudioMuted: rawMuted is bool ? rawMuted : (rawMuted == 1),
    );
  }

  @override
  String toString() {
    return 'HistoryModel(id: $id, presetLabel: $presetLabel, durationSeconds: $durationSeconds, executedAt: $executedAt, isScreenLocked: $isScreenLocked, isAudioMuted: $isAudioMuted)';
  }
}
