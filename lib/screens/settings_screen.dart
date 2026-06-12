import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../providers/tracking_provider.dart';
import '../services/trace_recorder_service.dart';
import '../services/webhook_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _intervalController;
  bool _testingWebhook = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController = TextEditingController(text: settings.webhookUrl);
    _intervalController = TextEditingController(
      text: settings.webhookIntervalSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _testWebhook(SettingsProvider settings) async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final l10n = context.l10n;
    setState(() {
      _testingWebhook = true;
      _testResult = null;
    });
    await settings.setWebhookUrl(url);
    final ok = await WebhookService.post(url, {
      'event': 'ping',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'message': l10n.webhookTestMessage,
    });
    if (!mounted) return;
    setState(() {
      _testingWebhook = false;
      _testResult = ok ? l10n.webhookSuccess : l10n.webhookFailure;
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
          context.l10n.settings,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final l10n = context.l10n;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _SectionHeader(label: l10n.display),
              const SizedBox(height: 10),
              _SettingsTile(
                title: l10n.useImperialUnits,
                subtitle: l10n.useImperialSubtitle,
                trailing: Switch(
                  value: settings.useImperial,
                  activeThumbColor: const Color(0xFF00E5FF),
                  activeTrackColor: const Color(0xFF00E5FF).withAlpha(128),
                  onChanged: (v) {
                    settings.setUseImperial(v);
                    context.read<TrackingProvider>().useImperial = v;
                  },
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(label: l10n.language),
              const SizedBox(height: 12),
              _LanguageSwitcher(settings: settings),
              const SizedBox(height: 20),
              _SectionHeader(label: l10n.autoPause),
              const SizedBox(height: 10),
              _SettingsTile(
                title: l10n.autoPauseEnabled,
                subtitle: l10n.autoPauseEnabledSubtitle,
                trailing: Switch(
                  value: settings.autoPauseEnabled,
                  activeThumbColor: const Color(0xFF00E5FF),
                  activeTrackColor: const Color(0xFF00E5FF).withAlpha(128),
                  onChanged: settings.setAutoPauseEnabled,
                ),
              ),
              if (settings.autoPauseEnabled) ...[
                _SettingsTile(
                  title: l10n.autoPauseThreshold,
                  subtitle: l10n.autoPauseThresholdSubtitle(
                    settings.autoPauseThresholdKmh,
                  ),
                  trailing: const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Slider(
                        value: settings.autoPauseThresholdKmh,
                        min: 0.5,
                        max: 10.0,
                        divisions: 19,
                        activeColor: const Color(0xFF00E5FF),
                        inactiveColor: Colors.white12,
                        label:
                            '${settings.autoPauseThresholdKmh.toStringAsFixed(1)} km/h',
                        onChanged: (v) {
                          settings.setAutoPauseThresholdKmh(v);
                          context
                              .read<TrackingProvider>()
                              .setAutoPauseThreshold(v / 3.6);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            '0.5',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '10.0 km/h',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── API / Webhook section ────────────────────────────────────
              _SectionHeader(label: l10n.apiWebhook),
              const SizedBox(height: 10),
              _SettingsTile(
                title: l10n.endpointUrl,
                subtitle: l10n.endpointSubtitle,
                trailing: const SizedBox.shrink(),
              ),
              const SizedBox(height: 6),
              _WebhookUrlField(
                controller: _urlController,
                onSubmitted: (v) => settings.setWebhookUrl(v),
              ),
              const SizedBox(height: 12),
              _SettingsTile(
                title: l10n.realtimeStreaming,
                subtitle: l10n.realtimeStreamingSubtitle,
                trailing: Switch(
                  value: settings.realtimeWebhookEnabled,
                  activeThumbColor: const Color(0xFF00E5FF),
                  activeTrackColor: const Color(0xFF00E5FF).withAlpha(128),
                  onChanged: (v) => settings.setRealtimeWebhookEnabled(v),
                ),
              ),
              if (settings.realtimeWebhookEnabled) ...[
                const SizedBox(height: 6),
                _SettingsTile(
                  title: l10n.postingInterval,
                  subtitle: l10n.postingIntervalSubtitle(
                    settings.webhookIntervalSeconds,
                  ),
                  trailing: const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      Slider(
                        value: settings.webhookIntervalSeconds.toDouble(),
                        min: 1,
                        max: 60,
                        divisions: 59,
                        activeColor: const Color(0xFF00E5FF),
                        inactiveColor: Colors.white12,
                        label: '${settings.webhookIntervalSeconds}s',
                        onChanged: (v) =>
                            settings.setWebhookIntervalSeconds(v.round()),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            '1s',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '60s',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              _SettingsTile(
                title: l10n.postSessionOnComplete,
                subtitle: l10n.postSessionOnCompleteSubtitle,
                trailing: Switch(
                  value: settings.postSessionOnComplete,
                  activeThumbColor: const Color(0xFF00E5FF),
                  activeTrackColor: const Color(0xFF00E5FF).withAlpha(128),
                  onChanged: (v) => settings.setPostSessionOnComplete(v),
                ),
              ),
              const SizedBox(height: 10),
              _TestWebhookButton(
                loading: _testingWebhook,
                result: _testResult,
                onPressed: () => _testWebhook(settings),
              ),

              const SizedBox(height: 24),
              _SectionHeader(label: l10n.accuracy),
              const SizedBox(height: 10),
              _SettingsTile(
                title: l10n.activityRecognition,
                subtitle: l10n.activityRecognitionSubtitle,
                trailing: Switch(
                  value: settings.activityRecognitionEnabled,
                  activeThumbColor: const Color(0xFF00E5FF),
                  activeTrackColor: const Color(0xFF00E5FF).withAlpha(128),
                  onChanged: (v) => settings.setActivityRecognitionEnabled(v),
                ),
              ),

              const SizedBox(height: 24),
              _SectionHeader(label: l10n.diagnostics),
              const SizedBox(height: 10),
              _SettingsTile(
                title: l10n.traceRecording,
                subtitle: l10n.traceRecordingSubtitle,
                trailing: Switch(
                  value: settings.traceRecordingEnabled,
                  activeThumbColor: const Color(0xFF00E5FF),
                  activeTrackColor: const Color(0xFF00E5FF).withAlpha(128),
                  onChanged: (v) => settings.setTraceRecordingEnabled(v),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final emptyMessage = l10n.noTracesToExport;
                    final shared = await TraceRecorderService.exportAll();
                    if (!shared) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(emptyMessage)),
                      );
                    }
                  },
                  icon: const Icon(Icons.ios_share_outlined, size: 16),
                  label: Text(l10n.exportTraces),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              _SectionHeader(label: l10n.about),
              const SizedBox(height: 10),
              _SettingsTile(
                title: l10n.measurementMethod,
                subtitle: l10n.measurementMethodSubtitle,
              ),
              _SettingsTile(
                title: l10n.backgroundTracking,
                subtitle: l10n.backgroundTrackingSubtitle,
              ),
              _SettingsTile(
                title: l10n.gpsAccuracyFilter,
                subtitle: l10n.gpsAccuracyFilterSubtitle,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LanguageSwitcher extends StatelessWidget {
  final SettingsProvider settings;
  const _LanguageSwitcher({required this.settings});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(value: 'fr', label: Text(l10n.french)),
        ButtonSegment(value: 'en', label: Text(l10n.english)),
      ],
      selected: {settings.languageCode},
      onSelectionChanged: (v) => settings.setLanguageCode(v.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: const Color(0xFF00E5FF).withAlpha(51),
        selectedForegroundColor: const Color(0xFF00E5FF),
        foregroundColor: Colors.white54,
        side: const BorderSide(color: Colors.white24),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF00E5FF),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SettingsTile({required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E272E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _WebhookUrlField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _WebhookUrlField({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E272E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: 'https://your-api.example.com/webhook',
          hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
          border: InputBorder.none,
        ),
        onSubmitted: onSubmitted,
        onEditingComplete: () {
          onSubmitted(controller.text);
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }
}

class _TestWebhookButton extends StatelessWidget {
  final bool loading;
  final String? result;
  final VoidCallback onPressed;

  const _TestWebhookButton({
    required this.loading,
    required this.result,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final succeeded = result == l10n.webhookSuccess;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onPressed,
            icon: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00E5FF),
                    ),
                  )
                : const Icon(Icons.send_outlined, size: 16),
            label: Text(loading ? l10n.testing : l10n.testWebhook),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
              side: const BorderSide(color: Color(0xFF00E5FF)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: succeeded
                  ? const Color(0xFF00E5FF).withAlpha(25)
                  : Colors.red.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: succeeded
                    ? const Color(0xFF00E5FF).withAlpha(100)
                    : Colors.red.withAlpha(100),
              ),
            ),
            child: Text(
              result!,
              style: TextStyle(
                color: succeeded ? const Color(0xFF00E5FF) : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
