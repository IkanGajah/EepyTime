import 'package:flutter/material.dart';

import '../controllers/timer_controller.dart';
import '../models/history_model.dart';

class HistoryTabView extends StatelessWidget {
  final TimerController controller;

  const HistoryTabView({
    super.key,
    required this.controller,
  });

  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  String _formatDateTime(String isoString) {
    final DateTime? parsed = DateTime.tryParse(isoString)?.toLocal();
    if (parsed == null) {
      return isoString;
    }
    final String day = parsed.day.toString().padLeft(2, '0');
    final String month = _monthNames[parsed.month - 1];
    final String year = parsed.year.toString();
    final String hour = parsed.hour.toString().padLeft(2, '0');
    final String minute = parsed.minute.toString().padLeft(2, '0');
    final String second = parsed.second.toString().padLeft(2, '0');
    return '$day $month $year • $hour:$minute:$second';
  }

  String _formatCompactDuration(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '0 dtk';
    }
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return minutes > 0 ? '${hours}j ${minutes}m' : '${hours}j';
    }
    if (minutes > 0) {
      return seconds > 0 ? '${minutes}m ${seconds}d' : '${minutes}m';
    }
    return '$seconds dtk';
  }

  String _formatFullDuration(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '0 Detik';
    }
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    final List<String> parts = <String>[];
    if (hours > 0) {
      parts.add('$hours Jam');
    }
    if (minutes > 0) {
      parts.add('$minutes Menit');
    }
    if (seconds > 0) {
      parts.add('$seconds Detik');
    }
    return parts.join(' ');
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              SizedBox(width: 10),
              Expanded(child: Text('Bersihkan Seluruh Riwayat?')),
            ],
          ),
          content: const Text(
            'Seluruh log sesi pemakaian dan statistik ringkasan kebiasaan akan '
            'dihapus secara permanen dari database lokal.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hapus Semua'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await controller.clearAllHistory();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seluruh riwayat pemakaian berhasil dibersihkan.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showSessionDetailBottomSheet(
    BuildContext context,
    HistoryModel session,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isPitchBlack = controller.isPitchBlack;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          isPitchBlack ? const Color(0xFF0D0D0D) : colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: session.isScreenLocked
                        ? Colors.tealAccent.shade700.withValues(alpha: 0.2)
                        : Colors.amber.shade800.withValues(alpha: 0.2),
                    child: Icon(
                      session.isScreenLocked
                          ? Icons.lock_clock_rounded
                          : Icons.volume_off_rounded,
                      color: session.isScreenLocked
                          ? Colors.tealAccent.shade400
                          : Colors.amber.shade400,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Detail Sesi Timer Tidur',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          session.isScreenLocked
                              ? 'Terkunci Penuh & Suara Diredam'
                              : 'Hanya Suara Diredam (Tanpa Kunci Layar)',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: session.isScreenLocked
                                ? Colors.tealAccent.shade400
                                : Colors.amber.shade300,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),
              _DetailRow(
                icon: Icons.label_outline_rounded,
                label: 'Nama Preset',
                value: session.presetLabel,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Durasi Timer',
                value:
                    '${_formatFullDuration(session.durationSeconds)} (${TimerController.formatDuration(session.durationSeconds)})',
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Waktu Eksekusi',
                value: _formatDateTime(session.executedAt),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.screen_lock_portrait_rounded,
                label: 'Status Kunci Layar',
                value: session.isScreenLocked
                    ? 'Berhasil Terkunci (DevicePolicyManager.lockNow)'
                    : 'Gagal / Tanpa Izin Device Admin',
                valueColor: session.isScreenLocked
                    ? Colors.tealAccent.shade400
                    : Colors.amber.shade400,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.volume_off_rounded,
                label: 'Status Peredam Suara',
                value: session.isAudioMuted
                    ? 'Suara Media Diredam (STREAM_MUSIC = 0)'
                    : 'Tidak Diredam',
                valueColor: session.isAudioMuted
                    ? Colors.tealAccent.shade400
                    : Colors.redAccent,
              ),
              const SizedBox(height: 22),
              FilledButton.tonal(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Tutup Detail'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        final bool isPitchBlack = controller.isPitchBlack;
        final Color cardBgColor = isPitchBlack
            ? const Color(0xFF0A0A0A)
            : colorScheme.surfaceContainerLow;
        final Color cardBorderColor = isPitchBlack
            ? Colors.white24
            : colorScheme.outlineVariant.withValues(alpha: 0.4);

        final Map<String, int> summary = controller.habitSummary;
        final int totalSessions = summary['totalSessions'] ?? 0;
        final int successfulSessions = summary['successfulSessions'] ?? 0;
        final int totalSeconds = summary['totalDurationSeconds'] ?? 0;
        final int avgSeconds = summary['averageDurationSeconds'] ?? 0;
        final List<HistoryModel> history = controller.historyList;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1. KARTU RINGKASAN KEBIASAAN (HABIT ANALYTICS)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.insights_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Ringkasan Kebiasaan Tidur',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$successfulSessions/$totalSessions Terkunci',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _HabitMetricItem(
                            icon: Icons.check_circle_outline_rounded,
                            title: 'Total Sesi',
                            value: '$totalSessions Sesi',
                            color: Colors.tealAccent.shade400,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HabitMetricItem(
                            icon: Icons.schedule_rounded,
                            title: 'Total Waktu',
                            value: _formatCompactDuration(totalSeconds),
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HabitMetricItem(
                            icon: Icons.nights_stay_outlined,
                            title: 'Rata-rata',
                            value: _formatCompactDuration(avgSeconds),
                            color: Colors.amberAccent.shade200,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. HEADER DAFTAR RIWAYAT & TOMBOL BERSIHKAN
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Riwayat Pemakaian (${history.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (history.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: () => _confirmClearHistory(context),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('Bersihkan'),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // 3. DAFTAR RIWAYAT KRONOLOGIS TERBALIK
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 38,
                  ),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cardBorderColor),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.bedtime_off_outlined,
                        size: 44,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Belum Ada Riwayat Pemakaian',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Setiap sesi hitung mundur yang selesai dieksekusi '
                        'akan tercatat secara otomatis di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final HistoryModel item = history[index];
                    final bool fullyLocked = item.isScreenLocked;

                    return Material(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () =>
                            _showSessionDetailBottomSheet(context, item),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: Row(
                            children: <Widget>[
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: fullyLocked
                                    ? Colors.tealAccent.shade700
                                        .withValues(alpha: 0.18)
                                    : Colors.amber.shade800
                                        .withValues(alpha: 0.2),
                                child: Icon(
                                  fullyLocked
                                      ? Icons.screen_lock_portrait_rounded
                                      : Icons.volume_off_rounded,
                                  color: fullyLocked
                                      ? Colors.tealAccent.shade400
                                      : Colors.amber.shade400,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      item.presetLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Durasi: ${_formatFullDuration(item.durationSeconds)} • ${_formatDateTime(item.executedAt)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: fullyLocked
                                            ? Colors.tealAccent.shade700
                                                .withValues(alpha: 0.16)
                                            : Colors.amber.shade800
                                                .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        fullyLocked
                                            ? 'Terkunci & Teredam'
                                            : 'Hanya Teredam (Tanpa Izin Kunci)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: fullyLocked
                                              ? Colors.tealAccent.shade400
                                              : Colors.amber.shade300,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HabitMetricItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _HabitMetricItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
