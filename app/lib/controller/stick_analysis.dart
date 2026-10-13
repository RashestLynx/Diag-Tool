// Pure-Dart stick-drift / dead-zone analysis. No Flutter or plugin imports,
// so the thresholds can be unit-tested.
import 'dart:math' as math;

/// Which kind of controller we're looking at (for labels and button names).
enum ControllerBrand { playstation, xbox, generic }

({String label, String a, String b, String x, String y, String view}) brandNames(
    ControllerBrand brand) {
  return switch (brand) {
    ControllerBrand.playstation =>
      (label: 'PlayStation', a: 'Cross', b: 'Circle', x: 'Square', y: 'Triangle', view: 'Create'),
    ControllerBrand.xbox =>
      (label: 'Xbox', a: 'A', b: 'B', x: 'X', y: 'Y', view: 'View'),
    ControllerBrand.generic =>
      (label: 'Controller', a: 'A', b: 'B', x: 'X', y: 'Y', view: 'Back'),
  };
}

/// Classify a controller from its USB ids (preferred) or its name.
///
/// vendorId is null on macOS/iOS, so fall back to the reported name there.
ControllerBrand classifyController({int? vendorId, String name = ''}) {
  // Sony = 0x054C, Microsoft = 0x045E.
  if (vendorId == 0x054C) return ControllerBrand.playstation;
  if (vendorId == 0x045E) return ControllerBrand.xbox;
  final n = name.toLowerCase();
  // Check Xbox first: its name is often "Xbox Wireless Controller", which
  // would otherwise match the looser PlayStation "wireless controller" marker.
  if (n.contains('xbox') || n.contains('xinput') || n.contains('microsoft')) {
    return ControllerBrand.xbox;
  }
  if (n.contains('dualsense') ||
      n.contains('dualshock') ||
      n.contains('playstation') ||
      n.contains('wireless controller') ||
      n.contains('ps5') ||
      n.contains('ps4') ||
      n.contains('sony')) {
    return ControllerBrand.playstation;
  }
  return ControllerBrand.generic;
}

enum DriftVerdict { healthy, minor, drift }

/// Result of watching one stick rest at centre for a moment.
class StickDriftResult {
  StickDriftResult({
    required this.maxMagnitude,
    required this.averageMagnitude,
    required this.restX,
    required this.restY,
    required this.sampleCount,
  });

  /// Farthest the stick wandered from centre while it should have been still,
  /// as a fraction of full travel (0.0 = dead centre, 1.0 = pushed to the rim).
  final double maxMagnitude;
  final double averageMagnitude;

  /// Average resting offset on each axis (signed), for showing direction.
  final double restX;
  final double restY;
  final int sampleCount;

  DriftVerdict get verdict {
    if (maxMagnitude >= 0.10) return DriftVerdict.drift;
    if (maxMagnitude >= 0.05) return DriftVerdict.minor;
    return DriftVerdict.healthy;
  }

  int get driftPercent => (maxMagnitude * 100).round();

  /// A dead zone that would mask this resting wander, with a small margin,
  /// clamped to a sensible range. As a percentage of full travel.
  int get recommendedDeadZonePercent =>
      ((maxMagnitude + 0.02) * 100).ceil().clamp(5, 40);

  String get direction {
    if (maxMagnitude < 0.03) return 'centred';
    final parts = <String>[];
    if (restY.abs() > 0.02) parts.add(restY > 0 ? 'up' : 'down');
    if (restX.abs() > 0.02) parts.add(restX > 0 ? 'right' : 'left');
    return parts.isEmpty ? 'centred' : parts.join('-');
  }
}

/// Accumulates stick samples while the user is told not to touch it, then
/// reports how far it drifted. Feed it (x, y) pairs as events arrive.
class StickDriftRecorder {
  final List<double> _magnitudes = [];
  double _sumX = 0;
  double _sumY = 0;
  double _maxMag = 0;

  void add(double x, double y) {
    final mag = math.sqrt(x * x + y * y);
    _magnitudes.add(mag);
    _sumX += x;
    _sumY += y;
    if (mag > _maxMag) _maxMag = mag;
  }

  bool get isEmpty => _magnitudes.isEmpty;
  int get sampleCount => _magnitudes.length;

  StickDriftResult result() {
    final n = _magnitudes.length;
    final avg = n == 0 ? 0.0 : _magnitudes.reduce((a, b) => a + b) / n;
    return StickDriftResult(
      maxMagnitude: _maxMag.clamp(0.0, 1.0),
      averageMagnitude: avg,
      restX: n == 0 ? 0 : _sumX / n,
      restY: n == 0 ? 0 : _sumY / n,
      sampleCount: n,
    );
  }
}

/// Apply a radial dead zone to a raw stick reading, the way a game would.
/// Returns the magnitude the game would actually see (0 inside the dead zone,
/// rescaled to 0..1 outside it).
double appliedMagnitude(double x, double y, double deadZone) {
  final mag = math.sqrt(x * x + y * y);
  if (mag <= deadZone) return 0;
  return ((mag - deadZone) / (1 - deadZone)).clamp(0.0, 1.0);
}
