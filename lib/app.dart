import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/tracking_provider.dart';
import 'providers/history_provider.dart';
import 'providers/settings_provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

class DistanceTrackerApp extends StatelessWidget {
  const DistanceTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, TrackingProvider>(
          create: (_) => TrackingProvider(),
          update: (_, settings, tracking) => tracking!..applySettings(settings),
        ),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (_, settings, child) => MaterialApp(
          locale: Locale(settings.languageCode),
          onGenerateTitle: (context) => context.l10n.appName,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0D1117),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E5FF),
              secondary: Color(0xFF00E5FF),
              surface: Color(0xFF1E272E),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0D1117),
              elevation: 0,
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF161B22),
              selectedItemColor: Color(0xFF00E5FF),
              unselectedItemColor: Colors.white38,
              type: BottomNavigationBarType.fixed,
            ),
            useMaterial3: true,
          ),
          home: const _AppShell(),
        ),
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;

  static const _screens = [HomeScreen(), HistoryScreen(), SettingsScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          if (i == 1) context.read<HistoryProvider>().load();
          setState(() => _currentIndex = i);
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.gps_fixed),
            label: l10n.tracker,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history),
            label: l10n.history,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }
}
