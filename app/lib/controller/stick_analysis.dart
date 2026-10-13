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

enum StickSide { left, right }

/// Tracks which inputs have responded at least once, so a full press-everything
/// test can tell you if a button or stick direction is dead.
///
/// Pure Dart (keyed by opaque strings) so it doesn't depend on the plugin.
class InputCoverage {
  InputCoverage({this.reachThreshold = 0.9, this.triggerThreshold = 0.9});

  /// How far (0..1) a stick must push for a direction to count as "reaches",
  /// and how far a trigger must travel to count as fully pressed.
  final double reachThreshold;
  final double triggerThreshold;

  final Set<String> buttonsSeen = {};

  /// Farthest travel seen in each stick direction, 0..1.
  final Map<StickSide, _Reach> _reach = {
    StickSide.left: _Reach(),
    StickSide.right: _Reach(),
  };
  final Map<StickSide, double> _triggerMax = {StickSide.left: 0, StickSide.right: 0};

  void markButton(String id) => buttonsSeen.add(id);

  void markStick(StickSide side, double x, double y) => _reach[side]!.add(x, y);

  void markTrigger(StickSide side, double value) {
    if (value > _triggerMax[side]!) _triggerMax[side] = value.clamp(0.0, 1.0);
  }

  double stickMaxMagnitude(StickSide side) => _reach[side]!.maxMagnitude;
  double triggerMax(StickSide side) => _triggerMax[side]!;

  /// Whether the stick reached the rim in all four directions.
  bool stickFullRange(StickSide side) => _reach[side]!.allDirections(reachThreshold);

  /// Directions not yet pushed to the rim, e.g. ['up', 'left'].
  List<String> missingDirections(StickSide side) => _reach[side]!.missing(reachThreshold);

  bool triggerFull(StickSide side) => _triggerMax[side]! >= triggerThreshold;

  /// Buttons from [expected] that haven't responded yet.
  List<String> missingButtons(Iterable<String> expected) =>
      expected.where((b) => !buttonsSeen.contains(b)).toList();

  /// True once every expected button, both triggers and both sticks' full
  /// range have been exercised.
  bool isComplete(Iterable<String> expectedButtons) =>
      missingButtons(expectedButtons).isEmpty &&
      triggerFull(StickSide.left) &&
      triggerFull(StickSide.right) &&
      stickFullRange(StickSide.left) &&
      stickFullRange(StickSide.right);
}

class _Reach {
  double up = 0, down = 0, left = 0, right = 0, maxMagnitude = 0;

  void add(double x, double y) {
    if (y > up) up = y;
    if (-y > down) down = -y;
    if (x > right) right = x;
    if (-x > left) left = -x;
    final mag = math.sqrt(x * x + y * y);
    if (mag > maxMagnitude) maxMagnitude = mag;
  }

  bool allDirections(double t) => up >= t && down >= t && left >= t && right >= t;

  List<String> missing(double t) => [
        if (up < t) 'up',
        if (down < t) 'down',
        if (left < t) 'left',
        if (right < t) 'right',
      ];
}

/// Measures the gap between consecutive input reports from a controller: the
/// controller->app timing and how steady it is. This is not full end-to-end
/// lag (press-to-screen), which can only be measured with a camera.
class ReportTiming {
  ReportTiming({this.window = 240});

  /// How many recent intervals to keep.
  final int window;
  final List<double> _intervals = [];
  int? _lastMs;

  /// Feed each event's timestamp (milliseconds). Returns false if the sample
  /// was ignored (first event, or a non-increasing/implausible timestamp).
  bool add(int timestampMs) {
    final last = _lastMs;
    _lastMs = timestampMs;
    if (last == null) return false;
    final delta = (timestampMs - last).toDouble();
    // Drop zero/negative steps and long idle gaps (> 0.5s = you stopped moving).
    if (delta <= 0 || delta > 500) return false;
    _intervals.add(delta);
    if (_intervals.length > window) _intervals.removeAt(0);
    return true;
  }

  void reset() {
    _intervals.clear();
    _lastMs = null;
  }

  int get sampleCount => _intervals.length;
  bool get hasData => _intervals.isNotEmpty;

  double get averageMs =>
      _intervals.isEmpty ? 0 : _intervals.reduce((a, b) => a + b) / _intervals.length;
  double get minMs => _intervals.isEmpty ? 0 : _intervals.reduce(math.min);
  double get maxMs => _intervals.isEmpty ? 0 : _intervals.reduce(math.max);

  /// Spread between the fastest and slowest report in the window.
  double get jitterMs => _intervals.isEmpty ? 0 : maxMs - minMs;

  /// Implied report rate in Hz from the average interval.
  double get rateHz => averageMs <= 0 ? 0 : 1000 / averageMs;
}

/// Apply a radial dead zone to a raw stick reading, the way a game would.
/// Returns the magnitude the game would actually see (0 inside the dead zone,
/// rescaled to 0..1 outside it).
double appliedMagnitude(double x, double y, double deadZone) {
  final mag = math.sqrt(x * x + y * y);
  if (mag <= deadZone) return 0;
  return ((mag - deadZone) / (1 - deadZone)).clamp(0.0, 1.0);
}
