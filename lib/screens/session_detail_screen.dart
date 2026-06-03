import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../l10n/app_localizations.dart';
import '../models/session.dart';
import '../services/export_service.dart';
import '../utils/formatters.dart';

class SessionDetailScreen extends StatelessWidget {
  final Session session;
  final bool useImperial;

  const SessionDetailScreen({
    super.key,
    required this.session,
    this.useImperial = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final distStr = formatDistance(
      session.totalDistanceMeters,
      useImperial: useImperial,
    );
    final avgSpeedStr = formatSpeed(
      session.avgSpeedMs,
      useImperial: useImperial,
    );
    final maxSpeedStr = formatSpeed(
      session.maxSpeedMs,
      useImperial: useImperial,
    );
    final durStr = formatDurationShort(
      session.activeDuration,
      hourUnit: l10n.hourShort,
      minuteUnit: l10n.minuteShort,
      secondUnit: l10n.secondShort,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          l10n.sessionDetails,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            tooltip: l10n.exportSession,
            color: const Color(0xFF1E272E),
            onSelected: (value) {
              if (value == 'json') {
                ExportService.exportSessionAsJson(session);
              } else if (value == 'csv') {
                ExportService.exportSessionAsCsv(session);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'json',
                child: Text(
                  l10n.exportAsJson,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Text(
                  l10n.exportAsCsvPoints,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateHeader(session: session),
              const SizedBox(height: 20),
              _StatsGrid(
                l10n: l10n,
                distStr: distStr,
                durStr: durStr,
                avgSpeedStr: avgSpeedStr,
                maxSpeedStr: maxSpeedStr,
              ),
              const SizedBox(height: 28),
              if (session.locationPoints.length >= 2) ...[
                Text(
                  l10n.speedOverTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _SpeedChart(session: session, useImperial: useImperial),
              ] else
                Center(
                  child: Text(
                    l10n.notEnoughDataForChart,
                    style: const TextStyle(color: Colors.white38),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final Session session;
  const _DateHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final dt = session.startTime;
    final end = session.endTime;

    String fmt(DateTime d) {
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${dt.day}/${dt.month}/${dt.year}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${fmt(dt)} → ${end != null ? fmt(end) : '--:--'}',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final AppLocalizations l10n;
  final String distStr;
  final String durStr;
  final String avgSpeedStr;
  final String maxSpeedStr;

  const _StatsGrid({
    required this.l10n,
    required this.distStr,
    required this.durStr,
    required this.avgSpeedStr,
    required this.maxSpeedStr,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: [
        _StatTile(label: l10n.distance, value: distStr, icon: Icons.straighten),
        _StatTile(label: l10n.activeTime, value: durStr, icon: Icons.timer),
        _StatTile(label: l10n.avgSpeed, value: avgSpeedStr, icon: Icons.speed),
        _StatTile(
          label: l10n.maxSpeed,
          value: maxSpeedStr,
          icon: Icons.flash_on,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E272E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedChart extends StatelessWidget {
  final Session session;
  final bool useImperial;

  const _SpeedChart({required this.session, required this.useImperial});

  @override
  Widget build(BuildContext context) {
    final points = session.locationPoints;
    if (points.isEmpty) return const SizedBox.shrink();

    final t0 = points.first.timestamp.millisecondsSinceEpoch;

    final spots = <FlSpot>[];
    for (final p in points) {
      final x = (p.timestamp.millisecondsSinceEpoch - t0) / 1000.0; // seconds
      final speedDisplay = useImperial ? p.speed * 2.23694 : p.speed * 3.6;
      spots.add(FlSpot(x, speedDisplay.clamp(0.0, double.infinity)));
    }

    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);
    final yTop = (maxY * 1.2).clamp(5.0, double.infinity);

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(0, 12, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E272E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white12, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, _) => Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _xInterval(spots),
                getTitlesWidget: (value, _) => Text(
                  formatDuration(Duration(seconds: value.toInt())),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: spots.last.x,
          minY: 0,
          maxY: yTop,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF00E5FF),
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF00E5FF).withAlpha(38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _xInterval(List<FlSpot> spots) {
    if (spots.isEmpty) return 60;
    final totalSeconds = spots.last.x;
    if (totalSeconds <= 120) return 30;
    if (totalSeconds <= 600) return 60;
    if (totalSeconds <= 3600) return 300;
    return 600;
  }
}
