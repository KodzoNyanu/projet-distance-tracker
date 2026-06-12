/// The kind of motion the pipeline is currently tuned for.
enum ActivityMode { still, walking, cycling, vehicle }

/// What the user chose on the home screen. [auto] defers to activity
/// recognition; the others pin a profile from the first fix. There is no
/// manual "still" — that only makes sense as an automatic detection.
enum DisplacementMode { auto, walking, cycling, vehicle }

extension DisplacementModeX on DisplacementMode {
  /// The pinned activity mode, or null for [DisplacementMode.auto].
  ActivityMode? get activityMode {
    switch (this) {
      case DisplacementMode.auto:
        return null;
      case DisplacementMode.walking:
        return ActivityMode.walking;
      case DisplacementMode.cycling:
        return ActivityMode.cycling;
      case DisplacementMode.vehicle:
        return ActivityMode.vehicle;
    }
  }

  /// Parses a persisted [name]; unknown values fall back to [auto].
  static DisplacementMode parse(String? name) {
    return DisplacementMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => DisplacementMode.auto,
    );
  }
}

/// Picks the active filter profile from the live inputs, in priority order:
///
///  1. the speed safety net — sustained vehicle speed forces the vehicle
///     profile upward no matter the label, so a mislabeled "Walking" lock
///     during an accidental drive still measures (the walking profile alone
///     rejects every car-speed fix as implausible);
///  2. a manual mode lock from the home screen;
///  3. the recognized activity mode;
///  4. the mixed-use default when nothing is known.
FilterProfile resolveActiveProfile({
  required bool forcingVehicle,
  ActivityMode? manualMode,
  ActivityMode? recognizedMode,
}) {
  if (forcingVehicle) return FilterProfile.vehicle;
  final mode = manualMode ?? recognizedMode;
  return mode == null ? FilterProfile.defaults : FilterProfile.forMode(mode);
}

/// Tuning parameters for the distance pipeline.
///
/// One profile describes how the filters should behave for a given kind of
/// motion. Activity recognition selects between per-mode profiles without
/// resetting filter state; [defaults] is the mixed-use compromise applied
/// when no mode is known.
class FilterProfile {
  /// Absolute minimum displacement for any accepted fix.
  final double minDistanceMeters;

  /// While moving, a displacement must exceed accuracy * this scale to be
  /// credited as distance.
  final double movingGateScale;

  /// While stationary, a displacement must exceed accuracy * this scale to
  /// count as movement starting…
  final double startGateScale;

  /// …unless Doppler corroborates movement, which shrinks the start gate.
  final double corroboratedStartGateScale;

  /// Calculated speeds above this are treated as glitches.
  final double maxPlausibleSpeedMs;

  /// Consecutive evidence fixes required to leave the stationary state.
  final int enterMovingEvidence;

  /// Consecutive no-motion fixes required to leave the moving state.
  final int exitMovingEvidence;

  /// Number of consecutive stationary readings before auto-pause triggers.
  final int autoPauseAfterCount;

  /// While stationary, the anchor is refreshed at this interval so GPS drift
  /// is flushed instead of accumulating against a stale anchor.
  final int anchorRefreshSeconds;

  /// Hard upper bound on the accuracy radius of a usable fix. The filter
  /// also adapts below this ceiling based on recent fix quality.
  final double accuracyCeilingMeters;

  /// Smoothing factor for the exponential moving average of displayed speed.
  final double speedEmaAlpha;

  /// Expected acceleration noise in m/s² — drives the Kalman process noise
  /// (gentle for walking, aggressive for vehicles).
  final double processNoiseSigmaA;

  /// Speed below which the user counts as stationary, in m/s. The
  /// user-configured auto-pause threshold can only raise this, never lower
  /// it below what the mode requires (a car crawling at 1 m/s is stopped
  /// traffic, not travel).
  final double stationaryThresholdMs;

  const FilterProfile({
    required this.minDistanceMeters,
    required this.movingGateScale,
    required this.startGateScale,
    required this.corroboratedStartGateScale,
    required this.maxPlausibleSpeedMs,
    required this.enterMovingEvidence,
    required this.exitMovingEvidence,
    required this.autoPauseAfterCount,
    required this.anchorRefreshSeconds,
    required this.accuracyCeilingMeters,
    required this.speedEmaAlpha,
    required this.processNoiseSigmaA,
    required this.stationaryThresholdMs,
  });

  /// Mixed-use defaults, matching the historical hard-coded constants.
  static const FilterProfile defaults = FilterProfile(
    minDistanceMeters: 2.0,
    movingGateScale: 0.4,
    startGateScale: 1.0,
    corroboratedStartGateScale: 0.5,
    maxPlausibleSpeedMs: 90.0,
    enterMovingEvidence: 2,
    exitMovingEvidence: 3,
    autoPauseAfterCount: 6,
    anchorRefreshSeconds: 30,
    accuracyCeilingMeters: 50.0,
    speedEmaAlpha: 0.3,
    processNoiseSigmaA: 1.5,
    stationaryThresholdMs: 0.55,
  );

  /// Phone resting: clamp everything down so multipath cannot invent travel.
  static const FilterProfile still = FilterProfile(
    minDistanceMeters: 2.0,
    movingGateScale: 1.0,
    startGateScale: 1.0,
    corroboratedStartGateScale: 0.5,
    maxPlausibleSpeedMs: 10.0,
    enterMovingEvidence: 2,
    exitMovingEvidence: 3,
    autoPauseAfterCount: 4,
    anchorRefreshSeconds: 30,
    accuracyCeilingMeters: 35.0,
    speedEmaAlpha: 0.2,
    processNoiseSigmaA: 0.1,
    stationaryThresholdMs: 0.55,
  );

  /// Walking or running: gentle dynamics, strong smoothing.
  /// maxPlausibleSpeed covers a sprint, not just a stroll.
  static const FilterProfile walking = FilterProfile(
    minDistanceMeters: 2.0,
    movingGateScale: 0.4,
    startGateScale: 1.0,
    corroboratedStartGateScale: 0.5,
    maxPlausibleSpeedMs: 8.0,
    enterMovingEvidence: 2,
    exitMovingEvidence: 3,
    autoPauseAfterCount: 8,
    anchorRefreshSeconds: 30,
    accuracyCeilingMeters: 50.0,
    speedEmaAlpha: 0.3,
    processNoiseSigmaA: 0.8,
    stationaryThresholdMs: 0.55,
  );

  static const FilterProfile cycling = FilterProfile(
    minDistanceMeters: 2.0,
    movingGateScale: 0.35,
    startGateScale: 0.8,
    corroboratedStartGateScale: 0.4,
    maxPlausibleSpeedMs: 16.0,
    enterMovingEvidence: 2,
    exitMovingEvidence: 3,
    autoPauseAfterCount: 10,
    anchorRefreshSeconds: 30,
    accuracyCeilingMeters: 60.0,
    speedEmaAlpha: 0.4,
    processNoiseSigmaA: 1.5,
    stationaryThresholdMs: 0.8,
  );

  /// Vehicle: hard accelerations, urban-canyon accuracy, and a long
  /// auto-pause so red lights never toggle the session.
  static const FilterProfile vehicle = FilterProfile(
    minDistanceMeters: 2.0,
    movingGateScale: 0.3,
    startGateScale: 0.6,
    corroboratedStartGateScale: 0.3,
    maxPlausibleSpeedMs: 70.0,
    enterMovingEvidence: 2,
    exitMovingEvidence: 4,
    autoPauseAfterCount: 25,
    anchorRefreshSeconds: 30,
    accuracyCeilingMeters: 75.0,
    speedEmaAlpha: 0.5,
    processNoiseSigmaA: 3.0,
    stationaryThresholdMs: 1.5,
  );

  /// The tuning profile for an activity mode.
  static FilterProfile forMode(ActivityMode mode) {
    switch (mode) {
      case ActivityMode.still:
        return still;
      case ActivityMode.walking:
        return walking;
      case ActivityMode.cycling:
        return cycling;
      case ActivityMode.vehicle:
        return vehicle;
    }
  }
}
