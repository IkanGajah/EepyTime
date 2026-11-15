import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/timer_controller.dart';
import 'screens/history_tab_view.dart';
import 'screens/settings_tab_view.dart';
import 'screens/timer_tab_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const EepyTimeApp());
}

typedef MyApp = EepyTimeApp;

class EepyTimeApp extends StatefulWidget {
  final TimerController? controller;

  const EepyTimeApp({
    super.key,
    this.controller,
  });

  @override
  State<EepyTimeApp> createState() => _EepyTimeAppState();
}

class _EepyTimeAppState extends State<EepyTimeApp> {
  late final TimerController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TimerController();
    _controller.initialize();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  ThemeData _buildTheme(bool isPitchBlack) {
    final ColorScheme baseDarkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: Brightness.dark,
    );

    final ColorScheme effectiveScheme = isPitchBlack
        ? baseDarkScheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
            surfaceContainerLow: const Color(0xFF0A0A0A),
            surfaceContainer: const Color(0xFF101010),
            surfaceContainerHigh: const Color(0xFF161616),
          )
        : baseDarkScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: effectiveScheme,
      scaffoldBackgroundColor:
          isPitchBlack ? Colors.black : effectiveScheme.surface,
      canvasColor: isPitchBlack ? Colors.black : effectiveScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isPitchBlack ? Colors.black : effectiveScheme.surface,
        foregroundColor: effectiveScheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isPitchBlack
            ? const Color(0xFF050505)
            : effectiveScheme.surfaceContainerLow,
        indicatorColor: effectiveScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) {
            final bool isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? effectiveScheme.primary
                  : effectiveScheme.onSurfaceVariant,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: 'EepyTime',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: _buildTheme(_controller.isPitchBlack),
          theme: _buildTheme(_controller.isPitchBlack),
          home: MainHomeScreen(controller: _controller),
        );
      },
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  final TimerController controller;

  const MainHomeScreen({
    super.key,
    required this.controller,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;
  bool _onboardingPromptShown = false;

  static const List<String> _tabTitles = <String>[
    'EepyTime',
    'Riwayat & Analitik',
    'Pengaturan Sistem',
  ];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_maybeShowFirstTimeOnboarding);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowFirstTimeOnboarding();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybeShowFirstTimeOnboarding);
    super.dispose();
  }

  void _maybeShowFirstTimeOnboarding() {
    if (!mounted || _onboardingPromptShown) {
      return;
    }
    if (!widget.controller.isInitialized) {
      return;
    }
    if (widget.controller.hasCompletedOnboarding ||
        widget.controller.isAdminActive) {
      _onboardingPromptShown = true;
      return;
    }

    _onboardingPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Row(
              children: <Widget>[
                Icon(Icons.bedtime_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Selamat Datang di EepyTime'),
                ),
              ],
            ),
            content: const Text(
              'EepyTime mengotomatiskan peredaman suara media (STREAM_MUSIC = 0) '
              'dan penguncian layar penuh (Force Screen-Lock) saat Anda tertidur, '
              'meskipun video sedang menahan layar tetap menyala.\n\n'
              'Agar fitur Kunci Layar Otomatis dapat bekerja, berikan izin '
              'Device Administrator terlebih dahulu. Anda dapat mencabut izin ini '
              'kapan saja lewat tab Pengaturan.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () async {
                  await widget.controller.completeOnboarding();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Nanti Saja'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await widget.controller.completeOnboarding();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  await widget.controller.requestAdminPermission();
                },
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Aktifkan Izin Kunci Layar'),
              ),
            ],
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isPitchBlack = widget.controller.isPitchBlack;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Icon(
              Icons.bedtime_rounded,
              color: colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _tabTitles[_selectedIndex],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          ListenableBuilder(
            listenable: widget.controller,
            builder: (BuildContext context, Widget? _) {
              final bool isRunning =
                  widget.controller.timerStatus == TimerStatus.running;
              if (!isRunning) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    Icons.timer_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  label: Text(
                    widget.controller.formattedRemainingTime,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: isPitchBlack
                ? Colors.white12
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: <Widget>[
          TimerTabView(controller: widget.controller),
          HistoryTabView(controller: widget.controller),
          SettingsTabView(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isPitchBlack
                  ? Colors.white12
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer_rounded),
              label: 'Timer',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'Riwayat',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}
