import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/history_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../widgets/session_list_tile.dart';
import 'session_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          context.l10n.history,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        actions: [
          Consumer<HistoryProvider>(
            builder: (context, history, _) {
              if (history.sessions.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: const Icon(Icons.download_outlined, color: Colors.white),
                tooltip: context.l10n.exportAllSessions,
                color: const Color(0xFF1E272E),
                onSelected: (value) {
                  if (value == 'json') {
                    ExportService.exportSessionsAsJson(history.sessions);
                  } else if (value == 'csv') {
                    ExportService.exportSessionsAsCsv(history.sessions);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'json',
                    child: Text(
                      context.l10n.exportAllAsJson,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'csv',
                    child: Text(
                      context.l10n.exportAllAsCsv,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer2<HistoryProvider, SettingsProvider>(
        builder: (context, history, settings, _) {
          final sessions = history.sessions;

          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, color: Colors.white24, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.noSessionsYet,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38, fontSize: 15),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return SessionListTile(
                session: session,
                useImperial: settings.useImperial,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(
                        session: session,
                        useImperial: settings.useImperial,
                      ),
                    ),
                  );
                },
                onDelete: () => history.deleteSession(session.id),
              );
            },
          );
        },
      ),
    );
  }
}
