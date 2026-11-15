import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/timer_controller.dart';
import '../models/preset_model.dart';

class TimerTabView extends StatefulWidget {
  final TimerController controller;

  const TimerTabView({
    super.key,
    required this.controller,
  });

  @override
  State<TimerTabView> createState() => _TimerTabViewState();
}

class _TimerTabViewState extends State<TimerTabView>
    with WidgetsBindingObserver {
  TimerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.checkAdminStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.checkAdminStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _formatReadableDuration(int seconds) {
    if (seconds < 60) {
      return '$seconds Detik';
    }
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int remainingSec = seconds % 60;

    final List<String> parts = <String>[];
    if (hours > 0) {
      parts.add('$hours Jam');
    }
    if (minutes > 0) {
      parts.add('$minutes Menit');
    }
    if (remainingSec > 0) {
      parts.add('$remainingSec Detik');
    }
    return parts.join(' ');
  }

  void _showSnackBar(
    String message, {
    bool isWarning = false,
    SnackBarAction? action,
  }) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isWarning
            ? Colors.amber.shade900
            : Theme.of(context).colorScheme.inverseSurface,
        action: action,
      ),
    );
  }

  Future<void> _handleStartOrPausePressed() async {
    if (_controller.timerStatus != TimerStatus.running &&
        _controller.remainingSeconds <= 0 &&
        _controller.initialSeconds <= 0) {
      _showSnackBar(
        'Pilih preset atau atur durasi manual terlebih dahulu.',
        isWarning: true,
      );
      return;
    }

    if (_controller.timerStatus == TimerStatus.idle &&
        !_controller.isAdminActive) {
      final String? choice = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade400,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Mulai Tanpa Kunci Layar?'),
                ),
              ],
            ),
            content: const Text(
              'Izin Device Administrator belum aktif. Jika timer habis sekarang, '
              'EepyTime hanya dapat meredam suara media ke 0 tanpa mengunci layar perangkat.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop('start_anyway'),
                child: const Text('Tetap Mulai (Hanya Mute)'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop('grant_admin'),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Beri Izin Dulu'),
              ),
            ],
          );
        },
      );

      if (choice == 'grant_admin') {
        await _controller.requestAdminPermission();
        return;
      }
      if (choice != 'start_anyway') {
        return;
      }
    }

    final bool wasRunning = _controller.timerStatus == TimerStatus.running;
    final bool changed = _controller.startOrPauseTimer();
    if (changed && _controller.isToastEnabled) {
      _showSnackBar(
        wasRunning
            ? 'EepyTime dijeda pada ${_controller.formattedRemainingTime}.'
            : 'EepyTime dimulai (${_controller.activePresetLabel}).',
      );
    }
  }

  Future<void> _showManualDurationDialog() async {
    final int? selectedSeconds = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _ManualDurationDialog(
          initialTotalSeconds: _controller.initialSeconds,
        );
      },
    );

    if (selectedSeconds == null || selectedSeconds <= 0 || !mounted) {
      return;
    }

    final String customLabel =
        'Manual (${_formatReadableDuration(selectedSeconds)})';
    _controller.selectDuration(selectedSeconds, customLabel);
    _showSnackBar('Durasi diatur ke $customLabel');
  }

  Future<void> _showAddPresetDialog() async {
    final ({String label, int seconds})? result =
        await showDialog<({String label, int seconds})>(
      context: context,
      builder: (BuildContext dialogContext) {
        return const _AddPresetDialog();
      },
    );

    if (result == null || result.seconds <= 0 || !mounted) {
      return;
    }

    final String finalLabel = result.label.isEmpty
        ? 'Preset (${_formatReadableDuration(result.seconds)})'
        : result.label;

    await _controller.addPreset(finalLabel, result.seconds);
    if (!mounted) {
      return;
    }
    _showSnackBar('Preset "$finalLabel" berhasil disimpan.');
  }

  void _showUninstallGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.info_outline),
              SizedBox(width: 10),
              Expanded(child: Text('Panduan Izin Device Admin')),
            ],
          ),
          content: const Text(
            'Aplikasi ini menggunakan kebijakan sistem Android (DevicePolicyManager) '
            'agar mampu mengunci layar secara paksa meskipun pemutar video sedang '
            'menahan layar (Wake-Lock).\n\n'
            'Catatan Penting:\n'
            'Jika suatu saat Anda ingin mencopot pemasangan (uninstall) aplikasi ini, '
            'Anda cukup membuka tab Pengaturan di aplikasi ini lalu menekan tombol '
            '"Cabut Izin Device Admin", atau menonaktifkannya melalui Pengaturan '
            'Keamanan Android > Aplikasi Admin Perangkat.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        final bool isPitchBlack = _controller.isPitchBlack;
        final Color cardBgColor = isPitchBlack
            ? const Color(0xFF0A0A0A)
            : colorScheme.surfaceContainerLow;
        final Color cardBorderColor = isPitchBlack
            ? Colors.white24
            : colorScheme.outlineVariant.withValues(alpha: 0.4);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1. BANNER PERINGATAN / STATUS IZIN KUNCI LAYAR (PRIORITAS UTAMA)
              _buildAdminStatusBanner(colorScheme),
              const SizedBox(height: 16),

              // 2. MESIN HITUNG MUNDUR UTAMA
              _buildMainTimerCard(
                colorScheme: colorScheme,
                cardBgColor: cardBgColor,
                cardBorderColor: cardBorderColor,
              ),
              const SizedBox(height: 20),

              // 3. MANAJEMEN PRESET DURASI (SQLITE)
              _buildPresetsSection(
                colorScheme: colorScheme,
                cardBgColor: cardBgColor,
                cardBorderColor: cardBorderColor,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminStatusBanner(ColorScheme colorScheme) {
    if (!_controller.isAdminActive) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.shade900.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.amber.shade600,
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade400,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Izin Kunci Layar Belum Aktif',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.amber.shade200,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _showUninstallGuideDialog,
                  icon: Icon(
                    Icons.help_outline,
                    color: Colors.amber.shade200,
                    size: 20,
                  ),
                  tooltip: 'Panduan Izin Device Admin',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Fitur kunci layar otomatis membutuhkan izin Device Administrator '
              'agar layar dapat terkunci penuh saat timer habis. Tanpa izin ini, '
              'aplikasi hanya dapat meredam suara media.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.amber.shade100.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  await _controller.requestAdminPermission();
                },
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text(
                  'Beri Izin Kunci Layar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.shade900.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.tealAccent.shade700.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.verified_user_rounded,
            color: Colors.tealAccent.shade400,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Izin Kunci Layar (Device Admin) Aktif & Siap',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: _showUninstallGuideDialog,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.info_outline, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainTimerCard({
    required ColorScheme colorScheme,
    required Color cardBgColor,
    required Color cardBorderColor,
  }) {
    final TimerStatus status = _controller.timerStatus;
    final bool isRunning = status == TimerStatus.running;
    final bool isPaused = status == TimerStatus.paused;

    final String statusLabel;
    final Color statusColor;
    final IconData statusIcon;

    switch (status) {
      case TimerStatus.running:
        statusLabel = 'BERJALAN';
        statusColor = colorScheme.primary;
        statusIcon = Icons.bolt_rounded;
      case TimerStatus.paused:
        statusLabel = 'DIJEDA';
        statusColor = Colors.orangeAccent;
        statusIcon = Icons.pause_circle_outline;
      case TimerStatus.idle:
        statusLabel = 'SIAP (IDLE)';
        statusColor = colorScheme.outline;
        statusIcon = Icons.bedtime_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorderColor),
      ),
      child: Column(
        children: <Widget>[
          // Baris Badge Status Timer & Status Audio
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: <Widget>[
              _StatusChip(
                icon: statusIcon,
                label: statusLabel,
                color: statusColor,
              ),
              _StatusChip(
                icon: _controller.isFadingOut
                    ? Icons.trending_down_rounded
                    : (_controller.isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded),
                label: _controller.isFadingOut
                    ? 'FADE-OUT AUDIO'
                    : (_controller.isMuted ? 'AUDIO TEREDAM' : 'AUDIO NORMAL'),
                color: _controller.isFadingOut
                    ? Colors.amberAccent.shade400
                    : (_controller.isMuted
                        ? Colors.redAccent
                        : Colors.tealAccent.shade400),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Label Preset Aktif
          Text(
            _controller.activePresetLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // Lingkaran Progres & Angka Hitung Mundur Proporsional (Tabular Figures)
          SizedBox(
            width: 230,
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CircularProgressIndicator(
                    value: _controller.progress,
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    backgroundColor:
                        colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    color: isRunning
                        ? colorScheme.primary
                        : (isPaused ? Colors.orangeAccent : colorScheme.secondary),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _controller.formattedRemainingTime,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: colorScheme.onSurface,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Total: ${_formatReadableDuration(_controller.initialSeconds)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Tombol Kontrol Utama: Mulai/Jeda & Reset ke 0
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: isRunning
                        ? Colors.orange.shade800
                        : colorScheme.primary,
                    foregroundColor: isRunning
                        ? Colors.white
                        : colorScheme.onPrimary,
                  ),
                  onPressed: _handleStartOrPausePressed,
                  icon: Icon(
                    isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    isRunning
                        ? 'Jeda Timer'
                        : (isPaused ? 'Lanjutkan' : 'Mulai Timer'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _controller.resetTimer,
                  icon: const Icon(Icons.replay_rounded, size: 20),
                  label: const Text('Reset'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tombol Pilih Durasi Manual (Outlined & Tinted agar jelas terlihat)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.primary,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.7),
                  width: 1.4,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _showManualDurationDialog,
              icon: const Icon(Icons.edit_calendar_outlined, size: 19),
              label: const Text(
                'Pilih Durasi Manual (JJ : MM : DD)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsSection({
    required ColorScheme colorScheme,
    required Color cardBgColor,
    required Color cardBorderColor,
  }) {
    final List<PresetModel> presets = _controller.presets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.bookmarks_outlined,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Preset Durasi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onPressed: _showAddPresetDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah Preset'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (presets.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorderColor),
            ),
            child: const Center(
              child: Text(
                'Belum ada preset tersimpan. Tekan "Tambah Preset" untuk membuat baru.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: presets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final PresetModel preset = presets[index];
              final bool isSelected =
                  _controller.initialSeconds == preset.durationSeconds &&
                      _controller.activePresetLabel == preset.label;

              return Material(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : cardBgColor,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    _controller.selectDuration(
                      preset.durationSeconds,
                      preset.label,
                    );
                    _showSnackBar('Preset "${preset.label}" dipilih.');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : cardBorderColor,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isSelected
                              ? colorScheme.primary
                              : colorScheme.surfaceContainerHighest,
                          foregroundColor: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          child: const Icon(Icons.timer_outlined, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                preset.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_formatReadableDuration(preset.durationSeconds)} '
                                '(${TimerController.formatDuration(preset.durationSeconds)})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (preset.id != null)
                          IconButton(
                            onPressed: () async {
                              await _controller.removePreset(preset.id!);
                              _showSnackBar(
                                'Preset "${preset.label}" dihapus.',
                              );
                            },
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: colorScheme.error,
                              size: 20,
                            ),
                            tooltip: 'Hapus Preset',
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _DurationInputField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 12,
        ),
      ),
    );
  }
}

class _ManualDurationDialog extends StatefulWidget {
  final int initialTotalSeconds;

  const _ManualDurationDialog({
    required this.initialTotalSeconds,
  });

  @override
  State<_ManualDurationDialog> createState() => _ManualDurationDialogState();
}

class _ManualDurationDialogState extends State<_ManualDurationDialog> {
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _secondsCtrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final int initHours = widget.initialTotalSeconds ~/ 3600;
    final int initMinutes = (widget.initialTotalSeconds % 3600) ~/ 60;
    final int initSeconds = widget.initialTotalSeconds % 60;

    _hoursCtrl = TextEditingController(
      text: initHours > 0 ? initHours.toString() : '0',
    );
    _minutesCtrl = TextEditingController(
      text: initMinutes.toString(),
    );
    _secondsCtrl = TextEditingController(
      text: initSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final int h = int.tryParse(_hoursCtrl.text.trim()) ?? 0;
    final int m = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final int s = int.tryParse(_secondsCtrl.text.trim()) ?? 0;
    final int totalSeconds = (h * 3600) + (m * 60) + s;

    if (totalSeconds <= 0) {
      setState(() {
        _errorMessage = 'Durasi harus lebih dari 0 detik.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(totalSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.timer_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Pilih Durasi Manual')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Masukkan waktu hitung mundur sebelum suara diredam dan layar dikunci:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _DurationInputField(
                    controller: _hoursCtrl,
                    label: 'Jam',
                    hint: '0',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DurationInputField(
                    controller: _minutesCtrl,
                    label: 'Menit',
                    hint: '15',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DurationInputField(
                    controller: _secondsCtrl,
                    label: 'Detik',
                    hint: '0',
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Terapkan'),
        ),
      ],
    );
  }
}

class _AddPresetDialog extends StatefulWidget {
  const _AddPresetDialog();

  @override
  State<_AddPresetDialog> createState() => _AddPresetDialogState();
}

class _AddPresetDialogState extends State<_AddPresetDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _secondsCtrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController();
    _minutesCtrl = TextEditingController(text: '20');
    _secondsCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String rawLabel = _labelCtrl.text.trim();
    final int m = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final int s = int.tryParse(_secondsCtrl.text.trim()) ?? 0;
    final int totalSeconds = (m * 60) + s;

    if (totalSeconds <= 0) {
      setState(() {
        _errorMessage = 'Total durasi preset harus lebih dari 0 detik.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop((label: rawLabel, seconds: totalSeconds));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.bookmark_add_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Tambah Preset Durasi')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama Preset',
                hintText: 'Contoh: Podcast Malam',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _DurationInputField(
                    controller: _minutesCtrl,
                    label: 'Menit',
                    hint: '20',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DurationInputField(
                    controller: _secondsCtrl,
                    label: 'Detik',
                    hint: '0',
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Simpan'),
        ),
      ],
    );
  }
}
