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

  String _formatShortDate(String isoString) {
    final DateTime? parsed = DateTime.tryParse(isoString)?.toLocal();
    if (parsed == null) {
      return isoString;
    }
    final String day = parsed.day.toString().padLeft(2, '0');
    final String month = _monthNames[parsed.month - 1];
    final String year = parsed.year.toString();
    return '$day $month $year';
  }

  String _formatClockHm(String isoString) {
    final DateTime? parsed = DateTime.tryParse(isoString)?.toLocal();
    if (parsed == null) {
      return '--:--';
    }
    final String hour = parsed.hour.toString().padLeft(2, '0');
    final String minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatCompactDuration(int totalSeconds) {
    if (totalSeconds <= 0) {
      return '0m';
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
    if (seconds > 0 && hours == 0) {
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
            'Seluruh riwayat sesi tidur dan statistik ringkasan kebiasaan akan '
            'dihapus secara permanen dari penyimpanan lokal.',
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
            content: Text('Seluruh riwayat tidur berhasil dibersihkan.'),
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
    final int? sleepSec = session.sleepDurationSeconds;
    final bool hasSleepDuration = sleepSec != null && sleepSec > 0;
    final bool hasWakeTime =
        session.wokeUpAt != null && session.wokeUpAt!.isNotEmpty;

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
                    backgroundColor:
                        colorScheme.primaryContainer.withValues(alpha: 0.35),
                    child: Icon(
                      Icons.nights_stay_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Detail Sesi Tidur',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          hasSleepDuration
                              ? 'Durasi Tidur: ${_formatFullDuration(sleepSec)}'
                              : session.presetLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.tealAccent.shade400,
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
                label: 'Preset / Mode',
                value: session.presetLabel,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.bedtime_outlined,
                label: 'Durasi Tidur Aktual',
                value: hasSleepDuration
                    ? '${_formatFullDuration(sleepSec)} (${TimerController.formatDuration(sleepSec)})'
                    : 'Belum tercatat (sesi lama)',
                valueColor:
                    hasSleepDuration ? Colors.tealAccent.shade400 : null,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.lock_clock_outlined,
                label: 'Mulai Tidur (Layar Terkunci)',
                value: _formatDateTime(session.executedAt),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.wb_sunny_outlined,
                label: 'Bangun Tidur (Layar Dibuka)',
                value: hasWakeTime ? _formatDateTime(session.wokeUpAt!) : '-',
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'Durasi Timer Sebelum Tidur',
                value:
                    '${_formatFullDuration(session.durationSeconds)} (${TimerController.formatDuration(session.durationSeconds)})',
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
        final int totalSleepSeconds = summary['totalSleepSeconds'] ?? 0;
        final int avgSleepSeconds = summary['averageSleepSeconds'] ?? 0;
        final List<HistoryModel> history = controller.historyList;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1. KARTU RINGKASAN KEBIASAAN TIDUR
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
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _HabitMetricItem(
                            icon: Icons.bedtime_outlined,
                            title: 'Total Sesi',
                            value: '$totalSessions Sesi',
                            color: Colors.tealAccent.shade400,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HabitMetricItem(
                            icon: Icons.schedule_rounded,
                            title: 'Total Tidur',
                            value: _formatCompactDuration(totalSleepSeconds),
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _HabitMetricItem(
                            icon: Icons.nights_stay_outlined,
                            title: 'Rata-rata Tidur',
                            value: _formatCompactDuration(avgSleepSeconds),
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
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.history_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Riwayat Tidur (${history.length})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                        'Belum Ada Riwayat Tidur',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Durasi tidur akan tercatat otomatis sejak timer selesai '
                        '(layar terkunci) hingga layar dibuka kembali.',
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
                    final int? sleepSec = item.sleepDurationSeconds;
                    final bool hasSleepDuration =
                        sleepSec != null && sleepSec > 0;
                    final bool hasWakeTime =
                        item.wokeUpAt != null && item.wokeUpAt!.isNotEmpty;

                    final String timeRangeLine = hasWakeTime
                        ? '${_formatShortDate(item.executedAt)} • ${_formatClockHm(item.executedAt)} → ${_formatClockHm(item.wokeUpAt!)}'
                        : _formatDateTime(item.executedAt);

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
                                backgroundColor: colorScheme.primaryContainer
                                    .withValues(alpha: 0.35),
                                child: Icon(
                                  Icons.nights_stay_rounded,
                                  color: colorScheme.primary,
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
                                      timeRangeLine,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: <Widget>[
                                        if (hasSleepDuration)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.tealAccent.shade700
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                Icon(
                                                  Icons.bedtime_rounded,
                                                  size: 12,
                                                  color: Colors
                                                      .tealAccent.shade400,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Tidur ${_formatFullDuration(sleepSec)}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors
                                                        .tealAccent.shade400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (item.durationSeconds > 0 ||
                                            !hasSleepDuration)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.6),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Timer ${_formatCompactDuration(item.durationSeconds)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                      ],
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
