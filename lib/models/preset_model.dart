class PresetModel {
  final int? id;
  final String label;
  final int durationSeconds;
  final String createdAt;

  const PresetModel({
    this.id,
    required this.label,
    required this.durationSeconds,
    required this.createdAt,
  });

  PresetModel copyWith({
    int? id,
    String? label,
    int? durationSeconds,
    String? createdAt,
  }) {
    return PresetModel(
      id: id ?? this.id,
      label: label ?? this.label,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'label': label,
      'duration_seconds': durationSeconds,
      'created_at': createdAt,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory PresetModel.fromMap(Map<String, dynamic> map) {
    return PresetModel(
      id: map['id'] as int?,
      label: (map['label'] as String?) ?? '',
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      createdAt: (map['created_at'] as String?) ?? '',
    );
  }

  @override
  String toString() {
    return 'PresetModel(id: $id, label: $label, durationSeconds: $durationSeconds, createdAt: $createdAt)';
  }
}
