import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../l10n/app_localizations.dart';

/// Manages the Android foreground service that keeps the app alive
/// while tracking in the background. On iOS this is a no-op because
/// background location is handled via Info.plist UIBackgroundModes.
class BackgroundService {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'distance_tracker_channel',
        channelName: AppLocalizations.current.notificationChannelName,
        channelDescription:
            AppLocalizations.current.notificationChannelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start({required String distanceText}) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: AppLocalizations.current.trackingInProgress,
        notificationText: distanceText,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: AppLocalizations.current.trackingInProgress,
      notificationText: distanceText,
    );
  }

  static Future<void> update({required String distanceText}) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: AppLocalizations.current.trackingInProgress,
      notificationText: distanceText,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
