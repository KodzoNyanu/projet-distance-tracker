import 'package:distance_tracker/utils/distance_pipeline.dart';
import 'package:distance_tracker/utils/filter_profiles.dart';
import 'package:distance_tracker/utils/movement_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/trace_loader.dart';

/// Replays recorded/synthetic traces (test/fixtures/*.jsonl) through the
/// distance pipeline and checks the result against each trace's ground truth.
///
/// This is the accuracy gate for every filter/tuning change: a change that
/// makes any fixture worse than its tolerance must not ship. Tolerances are
/// per-fixture because GPS quality differs by scenario (open-sky walk vs
/// urban drive). When a new real-world trace is recorded, set its measured
/// ground truth in the header and add a tolerance here.
void main() {
  // Acceptable error per fixture: absolute metres when truth is 0,
  // relative otherwise. History (full pipeline):
  //   legacy MovementFilter: stationary +902.8 m/h, walking +9.35%,
  //     drive +1.61%, mixed +4.17%
  //   Phase 1 hardening:     stationary +331.6 m/h, walking +10.08%,
  //     drive +1.61%, mixed +4.08%
  //   Phase 2 Kalman:        stationary +389.7 m/h, walking +5.72%,
  //     drive +1.48%, mixed +2.82%
  // Stationary regressed slightly vs Phase 1 (+58 m/h): the fixture is a
  // 20%-duty multipath torture test with sustained fake Doppler, and each
  // smoothed↔raw handoff at an episode boundary costs a few metres. The
  // across-the-board gains on real movement outweigh it, and still-detection
  // via the motion coprocessor (activity recognition phase) is the proper
  // fix for sustained multipath — GPS alone cannot distinguish it from a
  // slow walk. Tighten after each improvement; never loosen without a
  // written justification.
  const tolerances = <String, double>{
    'stationary_multipath': 400, // metres of phantom distance per hour
    'walking_loop': 0.06,
    'drive_with_stops': 0.02,
    'mixed_walk_drive': 0.03,
  };

  final traces = loadFixtureTraces();

  test('all fixtures are covered by a tolerance entry', () {
    expect(
      traces.map((t) => t.sessionId).toSet(),
      tolerances.keys.toSet(),
    );
  });

  for (final trace in traces) {
    test('replay ${trace.sessionId}: pipeline within tolerance, '
        'not worse than legacy', () {
      final truth = trace.groundTruthMeters;
      expect(truth, isNotNull,
          reason: 'fixture ${trace.sessionId} needs groundTruthMeters');

      final legacy = MovementFilter();
      var legacyMeters = 0.0;
      for (final fix in trace.fixes) {
        legacyMeters += legacy.process(fix).deltaMeters;
      }
      legacyMeters += legacy.flush();

      final pipeline = DistancePipeline();
      var pipelineMeters = 0.0;
      for (final fix in trace.fixes) {
        pipelineMeters += pipeline.process(fix).deltaMeters;
      }
      pipelineMeters += pipeline.flush();

      final legacyError =
          truth == 0 ? legacyMeters : (legacyMeters - truth!) / truth;
      final pipelineError =
          truth == 0 ? pipelineMeters : (pipelineMeters - truth!) / truth;
      final unit = truth == 0 ? ' m' : '%';
      final scale = truth == 0 ? 1.0 : 100.0;
      // ignore: avoid_print
      print(
        '[replay] ${trace.sessionId}: truth ${truth!.toStringAsFixed(1)} m | '
        'legacy ${legacyMeters.toStringAsFixed(1)} m '
        '(${(legacyError * scale).toStringAsFixed(2)}$unit) | '
        'pipeline ${pipelineMeters.toStringAsFixed(1)} m '
        '(${(pipelineError * scale).toStringAsFixed(2)}$unit)',
      );

      if (truth == 0) {
        // No legacy comparison here: the smoothed↔raw handoff cost on this
        // torture fixture is accepted and bounded by the absolute tolerance.
        expect(pipelineMeters, lessThanOrEqualTo(tolerances[trace.sessionId]!),
            reason: 'phantom distance while stationary');
      } else {
        expect(
          pipelineError.abs(),
          lessThanOrEqualTo(tolerances[trace.sessionId]!),
          reason: 'distance error vs ground truth',
        );
        expect(
          pipelineError.abs(),
          lessThanOrEqualTo(legacyError.abs() + 0.005),
          reason: 'pipeline must not be worse than the legacy filter',
        );
      }
    });
  }

  // With activity recognition live, single-mode sessions run on their
  // mode-specific profile. Measured at Phase 3: stationary/still
  // +227.3 m/h, walking/walking +4.75%, drive/vehicle +1.06%.
  const profiledExpectations = <String, (FilterProfile, double)>{
    'stationary_multipath': (FilterProfile.still, 250),
    'walking_loop': (FilterProfile.walking, 0.05),
    'drive_with_stops': (FilterProfile.vehicle, 0.015),
  };

  for (final trace in traces) {
    final entry = profiledExpectations[trace.sessionId];
    if (entry == null) continue;
    final (profile, tolerance) = entry;

    test('replay ${trace.sessionId}: mode-correct profile meets its target',
        () {
      final pipeline = DistancePipeline(profile: profile);
      var meters = 0.0;
      for (final fix in trace.fixes) {
        meters += pipeline.process(fix).deltaMeters;
      }
      meters += pipeline.flush();

      final truth = trace.groundTruthMeters!;
      if (truth == 0) {
        expect(meters, lessThanOrEqualTo(tolerance),
            reason: 'phantom distance with the still profile');
      } else {
        final error = ((meters - truth) / truth).abs();
        expect(error, lessThanOrEqualTo(tolerance),
            reason: 'distance error with the mode-correct profile');
      }
    });
  }
}
