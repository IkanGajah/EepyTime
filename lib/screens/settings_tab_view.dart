import 'package:flutter/material.dart';

import '../controllers/timer_controller.dart';

class SettingsTabView extends StatelessWidget {
  final TimerController controller;

  const SettingsTabView({
    super.key,
    required this.controller,
  });

  Future<void> _confirmRevokeAdmin(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.no_encryption_gmailerrorred_rounded, color: Colors.amber),
              SizedBox(width: 10),
              Expanded(child: Text('Cabut Izin Kunci Layar?')),
            ],
          ),
          content: const Text(
            'Mencabut hak akses Device Administrator akan menonaktifkan fitur '
            'penguncian layar otomatis, namun memungkinkan Anda untuk mencopot '
            'pemasangan (uninstall) aplikasi ini dari perangkat Android Anda dengan mudah.\n\n'
            'Anda dapat mengaktifkan kembali izin ini kapan saja.',
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
              child: const Text('Cabut Izin'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final bool success = await controller.revokeAdminPermission();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Izin Device Admin berhasil dicabut. Aplikasi kini dapat di-uninstall.'
                  : 'Izin Device Admin sudah dalam keadaan tidak aktif.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1. TEMA TAMPILAN
              _SectionHeader(
                icon: Icons.palette_outlined,
                title: 'Tema Tampilan',
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorderColor),
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: Icon(
                        Icons.contrast_rounded,
                        color: colorScheme.primary,
                      ),
                      title: const Text(
                        'Mode AMOLED Pitch Black',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Menggunakan latar belakang hitam murni (#000000) untuk '
                        'menghemat daya baterai di layar OLED pada malam hari.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      value: controller.isPitchBlack,
                      onChanged: (bool val) {
                        controller.togglePitchBlackMode(val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. SUARA & PEMBERITAHUAN
              _SectionHeader(
                icon: Icons.vibration_rounded,
                title: 'Suara & Pemberitahuan',
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorderColor),
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: Icon(
                        Icons.edgesensor_high_rounded,
                        color: colorScheme.primary,
                      ),
                      title: const Text(
                        'Umpan Balik Getar (Haptic Feedback)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Memberikan getaran halus dan umpan balik status saat '
                        'tombol ditekan maupun ketika timer dimulai/selesai.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      value: controller.isHapticEnabled,
                      onChanged: (bool val) {
                        controller.toggleHapticFeedback(val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. TENTANG APLIKASI & KEAMANAN IZIN SISTEM
              _SectionHeader(
                icon: Icons.security_rounded,
                title: 'Tentang Aplikasi & Keamanan Izin',
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.bedtime_rounded,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Timer Tidur Otomatis',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Versi 1.0.0+1 • 100% Offline-First Utility',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    _InfoTile(
                      label: 'Jembatan Native',
                      value: 'MethodChannel (sleep_timer/native_control)',
                    ),
                    const SizedBox(height: 8),
                    _InfoTile(
                      label: 'Kebijakan Sistem',
                      value: 'DevicePolicyManager & AudioManager',
                    ),
                    const SizedBox(height: 8),
                    _InfoTile(
                      label: 'Status Izin Device Admin',
                      value: controller.isAdminActive
                          ? 'Aktif (Siap Mengunci Layar)'
                          : 'Belum Aktif (Hanya Peredam Suara)',
                      valueColor: controller.isAdminActive
                          ? Colors.tealAccent.shade400
                          : Colors.amber.shade400,
                    ),
                    const SizedBox(height: 18),
                    if (!controller.isAdminActive)
                      FilledButton.icon(
                        onPressed: () {
                          controller.requestAdminPermission();
                        },
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Aktifkan Izin Kunci Layar'),
                      )
                    else
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _confirmRevokeAdmin(context),
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text(
                          'Cabut Izin Kunci Layar (Untuk Uninstall)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      'Catatan: Android melarang penghapusan aplikasi yang masih '
                      'memegang izin Device Administrator aktif. Gunakan tombol '
                      'di atas untuk mencabut izin secara instan sebelum melakukan uninstall.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
