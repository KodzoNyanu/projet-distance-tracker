import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../l10n/app_localizations.dart';

/// Wraps the geolocator plugin and handles permission checks.
/// Emits a stream of [Position] objects for the caller to consume.
class LocationService {
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0, // We do our own filtering
  );

  StreamSubscription<Position>? _subscription;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _controller.stream;

  /// Requests location permission and starts the GPS stream.
  /// Throws a [LocationServiceException] if permission is denied
  /// or location services are disabled.
  Future<void> startTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationServiceException(
        AppLocalizations.current.locationServicesDisabled,
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationServiceException(
          AppLocalizations.current.locationPermissionDenied,
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationServiceException(
        AppLocalizations.current.locationPermissionDeniedForever,
      );
    }

    _subscription =
        Geolocator.getPositionStream(
          locationSettings: _locationSettings,
        ).listen(
          (position) => _controller.add(position),
          onError: (Object e) => _controller.addError(e),
        );
  }

  /// Stops the GPS stream.
  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stopTracking();
    await _controller.close();
  }
}

class LocationServiceException implements Exception {
  final String message;
  const LocationServiceException(this.message);

  @override
  String toString() => 'LocationServiceException: $message';
}
