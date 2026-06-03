import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations current = AppLocalizations(const Locale('fr'));

  static const supportedLocales = [Locale('fr'), Locale('en')];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  bool get _fr => locale.languageCode == 'fr';

  String get appName => 'Kodzo Kilometrage';
  String get appShortName => 'KK';
  String get tracker => _fr ? 'Suivi' : 'Tracker';
  String get history => _fr ? 'Historique' : 'History';
  String get settings => _fr ? 'Reglages' : 'Settings';
  String get readyToStart => _fr ? 'Pret a demarrer' : 'Ready to start';
  String get tracking => _fr ? 'Suivi en cours' : 'Tracking';
  String get autoPausedStationary =>
      _fr ? 'Pause automatique - immobile' : 'Auto-paused - stationary';
  String get sessionComplete => _fr ? 'Session terminee' : 'Session complete';
  String get speed => _fr ? 'Vitesse' : 'Speed';
  String get time => _fr ? 'Temps' : 'Time';
  String get maxSpeed => _fr ? 'Vitesse max' : 'Max Speed';
  String get active => _fr ? 'actif' : 'active';
  String get tryAgain => _fr ? 'Reessayer' : 'Try Again';
  String get viewSummary => _fr ? 'Voir le resume' : 'View Summary';
  String get newSession => _fr ? 'Nouvelle session' : 'New Session';
  String get start => _fr ? 'DEMARRER' : 'START';
  String get stop => _fr ? 'ARRETER' : 'STOP';
  String get noSessionsYet => _fr
      ? 'Aucune session pour le moment.\nDemarrez un suivi pour voir l\'historique.'
      : 'No sessions yet.\nStart tracking to see history.';
  String get exportAllSessions =>
      _fr ? 'Exporter toutes les sessions' : 'Export all sessions';
  String get exportAllAsJson =>
      _fr ? 'Tout exporter en JSON' : 'Export all as JSON';
  String get exportAllAsCsv =>
      _fr ? 'Tout exporter en CSV' : 'Export all as CSV';
  String get deleteSessionTitle =>
      _fr ? 'Supprimer la session ?' : 'Delete session?';
  String get deleteSessionMessage =>
      _fr ? 'Cette action est definitive.' : 'This cannot be undone.';
  String get cancel => _fr ? 'Annuler' : 'Cancel';
  String get delete => _fr ? 'Supprimer' : 'Delete';
  String todayAt(String time) => _fr ? 'Aujourd\'hui, $time' : 'Today, $time';
  String yesterdayAt(String time) => _fr ? 'Hier, $time' : 'Yesterday, $time';

  String get language => _fr ? 'Langue' : 'Language';
  String get french => 'Français';
  String get english => 'English';
  String get display => _fr ? 'Affichage' : 'Display';
  String get useImperialUnits =>
      _fr ? 'Utiliser les unites imperiales' : 'Use imperial units';
  String get useImperialSubtitle => _fr
      ? 'Afficher miles et mph au lieu de km et km/h'
      : 'Show miles and mph instead of km and km/h';
  String get autoPause => _fr ? 'Pause automatique' : 'Auto-pause';
  String get autoPauseEnabled =>
      _fr ? 'Activer la pause automatique' : 'Enable auto-pause';
  String get autoPauseEnabledSubtitle => _fr
      ? 'Optionnel. La distance ignore deja les petits sauts GPS quand cette option est desactivee.'
      : 'Optional. Distance still ignores small GPS jumps when this is off.';
  String get autoPauseThreshold =>
      _fr ? 'Seuil de pause automatique' : 'Auto-pause threshold';
  String autoPauseThresholdSubtitle(double kmh) => _fr
      ? 'Le temps actif se met en pause sous cette vitesse (${kmh.toStringAsFixed(1)} km/h)'
      : 'Active time pauses below this speed (${kmh.toStringAsFixed(1)} km/h)';
  String get apiWebhook => _fr ? 'API / Webhook' : 'API / Webhook';
  String get endpointUrl => _fr ? 'URL du endpoint' : 'Endpoint URL';
  String get endpointSubtitle => _fr
      ? 'Destination POST pour les donnees JSON structurees'
      : 'POST destination for structured JSON payloads';
  String get realtimeStreaming =>
      _fr ? 'Diffusion en temps reel' : 'Real-time streaming';
  String get realtimeStreamingSubtitle => _fr
      ? 'Envoyer automatiquement un payload distance_update pendant le deplacement'
      : 'Automatically POST a distance_update payload as you move';
  String get postingInterval =>
      _fr ? 'Intervalle d\'envoi' : 'Posting interval';
  String postingIntervalSubtitle(int seconds) => _fr
      ? 'Secondes minimum entre les envois en temps reel (${seconds}s)'
      : 'Minimum seconds between real-time posts (${seconds}s)';
  String get postSessionOnComplete =>
      _fr ? 'POST de la session terminee' : 'POST session on complete';
  String get postSessionOnCompleteSubtitle => _fr
      ? 'Envoyer un payload session_end avec tous les points GPS a l\'arret'
      : 'Send a session_end payload with all GPS points when you stop';
  String get testWebhook => _fr ? 'Tester le webhook' : 'Test webhook';
  String get testing => _fr ? 'Test en cours...' : 'Testing...';
  String get webhookSuccess => _fr
      ? 'Succes - le endpoint a repondu en 2xx.'
      : 'Success - endpoint responded 2xx.';
  String get webhookFailure => _fr
      ? 'Echec - verifiez l\'URL ou le reseau.'
      : 'Failed - check URL or network.';
  String get webhookTestMessage => _fr
      ? 'Test du webhook Kodzo Kilometrage'
      : 'Kodzo Kilometrage webhook test';
  String get about => _fr ? 'A propos' : 'About';
  String get measurementMethod =>
      _fr ? 'Methode de mesure' : 'Measurement method';
  String get measurementMethodSubtitle => _fr
      ? 'GPS Haversine - adapte a la marche, au velo ou au vehicule. Aucune API de carte requise.'
      : 'GPS Haversine - works on foot, bicycle, or vehicle. No maps API required.';
  String get backgroundTracking =>
      _fr ? 'Suivi en arriere-plan' : 'Background tracking';
  String get backgroundTrackingSubtitle => _fr
      ? 'Actif - utilise la localisation systeme lorsque l\'ecran est eteint.'
      : 'Active - uses system location services when the screen is off.';
  String get gpsAccuracyFilter =>
      _fr ? 'Filtre de precision GPS' : 'GPS accuracy filter';
  String get gpsAccuracyFilterSubtitle => _fr
      ? 'Les mesures avec une precision superieure a 50 m sont ignorees automatiquement.'
      : 'Readings with accuracy worse than 50 m are discarded automatically.';

  String get sessionDetails =>
      _fr ? 'Details de la session' : 'Session Details';
  String get exportSession => _fr ? 'Exporter la session' : 'Export session';
  String get exportAsJson => _fr ? 'Exporter en JSON' : 'Export as JSON';
  String get exportAsCsvPoints =>
      _fr ? 'Exporter en CSV (points GPS)' : 'Export as CSV (GPS points)';
  String get speedOverTime => _fr ? 'Vitesse dans le temps' : 'Speed over time';
  String get notEnoughDataForChart => _fr
      ? 'Pas assez de donnees pour le graphique.'
      : 'Not enough data for chart.';
  String get distance => _fr ? 'Distance' : 'Distance';
  String get activeTime => _fr ? 'Temps actif' : 'Active Time';
  String get avgSpeed => _fr ? 'Vitesse moy.' : 'Avg Speed';
  String get hourShort => 'h';
  String get minuteShort => _fr ? 'min' : 'm';
  String get secondShort => 's';

  String get locationServicesDisabled => _fr
      ? 'Les services de localisation sont desactives. Activez-les dans les reglages de l\'appareil.'
      : 'Location services are disabled. Please enable them in device settings.';
  String get locationPermissionDenied => _fr
      ? 'L\'autorisation de localisation a ete refusee.'
      : 'Location permission was denied.';
  String get locationPermissionDeniedForever => _fr
      ? 'L\'autorisation de localisation est refusee definitivement. Activez-la dans les reglages de l\'app.'
      : 'Location permission is permanently denied. Please enable it in app settings.';
  String get notificationChannelName =>
      _fr ? 'Suivi de distance' : 'Distance Tracking';
  String get notificationChannelDescription => _fr
      ? 'Affiche pendant le suivi de distance en arriere-plan.'
      : 'Shown while distance tracking is active in the background.';
  String get trackingInProgress =>
      _fr ? 'Suivi en cours' : 'Tracking in progress';
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['fr', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final languageCode = locale.languageCode == 'en' ? 'en' : 'fr';
    final localizations = AppLocalizations(Locale(languageCode));
    AppLocalizations.current = localizations;
    return SynchronousFuture(localizations);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
