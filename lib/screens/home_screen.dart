import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/history_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/filter_profiles.dart';
import '../utils/formatters.dart';
import '../widgets/distance_gauge.dart';
import '../widgets/stat_card.dart';
import 'session_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.l10n.appName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: Consumer2<TrackingProvider, SettingsProvider>(
        builder: (context, tracker, settings, _) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _StatusBanner(state: tracker.state),
                  const SizedBox(height: 16),

                  // ── Gauge ──────────────────────────────────────────────
                  Expanded(
                    flex: 5,
                    child: DistanceGauge(
                      value: tracker.distanceMeters,
                      autoScale: true,
                      label: _distanceLabel(
                        tracker.distanceMeters,
                        settings.useImperial,
                      ),
                      unit: distanceUnitForValue(
                        tracker.distanceMeters,
                        useImperial: settings.useImperial,
                      ),
                      arcColor: tracker.isAutoPaused
                          ? Colors.orangeAccent
                          : const Color(0xFF00E5FF),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Stat Cards ─────────────────────────────────────────
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: context.l10n.speed,
                            value: _speedValue(
                              tracker.currentSpeedMs,
                              settings.useImperial,
                            ),
                            unit: speedUnit(useImperial: settings.useImperial),
                            icon: Icons.speed,
                            accentColor: const Color(0xFF00E5FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: context.l10n.time,
                            value: formatDuration(tracker.activeDuration),
                            unit: context.l10n.active,
                            icon: Icons.timer_outlined,
                            accentColor: Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: context.l10n.maxSpeed,
                            value: _speedValue(
                              tracker.maxSpeedMs,
                              settings.useImperial,
                            ),
                            unit: speedUnit(useImperial: settings.useImperial),
                            icon: Icons.flash_on,
                            accentColor: Colors.amberAccent,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Movement mode (idle only) ──────────────────────────
                  if (tracker.isIdle) ...[
                    _ModePicker(settings: settings),
                    const SizedBox(height: 16),
                  ],

                  // ── Control Button ─────────────────────────────────────
                  _ControlButton(tracker: tracker, settings: settings),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _distanceLabel(double meters, bool imperial) {
    if (imperial) {
      final miles = meters / 1609.344;
      return miles >= 1.0
          ? miles.toStringAsFixed(2)
          : (meters * 3.28084).toStringAsFixed(0);
    }
    final km = meters / 1000.0;
    return km >= 1.0 ? km.toStringAsFixed(2) : meters.toStringAsFixed(0);
  }

  String _speedValue(double speedMs, bool imperial) {
    if (imperial) return (speedMs * 2.23694).toStringAsFixed(1);
    return (speedMs * 3.6).toStringAsFixed(1);
  }
}

class _ModePicker extends StatelessWidget {
  final SettingsProvider settings;

  const _ModePicker({required this.settings});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = <(DisplacementMode, IconData, String)>[
      (DisplacementMode.auto, Icons.auto_mode, l10n.modeAuto),
      (DisplacementMode.walking, Icons.directions_walk, l10n.modeWalking),
      (DisplacementMode.cycling, Icons.directions_bike, l10n.modeCycling),
      (DisplacementMode.vehicle, Icons.directions_car, l10n.modeVehicle),
    ];
    final selected = settings.displacementMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.movementMode.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (mode, icon, label) in options) ...[
              Expanded(
                child: _ModeChip(
                  icon: icon,
                  label: label,
                  selected: mode == selected,
                  onTap: () => settings.setDisplacementMode(mode),
                ),
              ),
              if (mode != options.last.$1) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00E5FF);
    final fg = selected ? accent : Colors.white54;
    return Material(
      color: selected ? accent.withAlpha(26) : const Color(0xFF1E272E),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.withAlpha(128) : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final TrackingState state;

  const _StatusBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, color) = switch (state) {
      TrackingState.idle => (l10n.readyToStart, Colors.white38),
      TrackingState.tracking => (l10n.tracking, Colors.greenAccent),
      TrackingState.autoPaused => (
        l10n.autoPausedStationary,
        Colors.orangeAccent,
      ),
      TrackingState.stopped => (l10n.sessionComplete, Colors.white54),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final TrackingProvider tracker;
  final SettingsProvider settings;

  const _ControlButton({required this.tracker, required this.settings});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Error state
    if (tracker.errorMessage != null) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withAlpha(128),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tracker.errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          _buildButton(
            context: context,
            label: l10n.tryAgain,
            color: Colors.white24,
            onPressed: tracker.resetToIdle,
          ),
        ],
      );
    }

    if (tracker.isStopped) {
      return Column(
        children: [
          _buildButton(
            context: context,
            label: l10n.viewSummary,
            color: const Color(0xFF00E5FF),
            textColor: Colors.black,
            onPressed: () {
              if (tracker.currentSession != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailScreen(
                      session: tracker.currentSession!,
                      useImperial: settings.useImperial,
                    ),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          _buildButton(
            context: context,
            label: l10n.newSession,
            color: Colors.white12,
            onPressed: tracker.resetToIdle,
          ),
        ],
      );
    }

    if (tracker.isIdle) {
      return _buildButton(
        context: context,
        label: l10n.start,
        color: const Color(0xFF00E5FF),
        textColor: Colors.black,
        onPressed: () {
          tracker.useImperial = settings.useImperial;
          tracker.setAutoPauseThreshold(settings.autoPauseThresholdMs);
          tracker.startSession();
        },
      );
    }

    // Tracking or auto-paused
    return _buildButton(
      context: context,
      label: l10n.stop,
      color: Colors.redAccent,
      onPressed: () async {
        await tracker.stopSession();
        if (context.mounted) context.read<HistoryProvider>().load();
      },
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required String label,
    required Color color,
    Color textColor = Colors.white,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
