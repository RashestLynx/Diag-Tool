import 'package:diag_tool/controller/stick_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyController', () {
    test('by USB vendor id', () {
      expect(classifyController(vendorId: 0x054C), ControllerBrand.playstation);
      expect(classifyController(vendorId: 0x045E), ControllerBrand.xbox);
    });
    test('by name when id is missing (macOS/iOS)', () {
      expect(classifyController(name: 'DualSense Wireless Controller'), ControllerBrand.playstation);
      expect(classifyController(name: 'Xbox Wireless Controller'), ControllerBrand.xbox);
      expect(classifyController(name: 'Some USB Gamepad'), ControllerBrand.generic);
    });
    test('id wins over a misleading name', () {
      expect(classifyController(vendorId: 0x054C, name: 'xbox'), ControllerBrand.playstation);
    });
  });

  group('brandNames', () {
    test('PlayStation face buttons', () {
      final n = brandNames(ControllerBrand.playstation);
      expect(n.a, 'Cross');
      expect(n.y, 'Triangle');
    });
    test('Xbox face buttons', () {
      expect(brandNames(ControllerBrand.xbox).a, 'A');
    });
  });

  group('StickDriftRecorder + verdict', () {
    test('a still, centred stick is healthy', () {
      final rec = StickDriftRecorder();
      for (var i = 0; i < 30; i++) {
        rec.add(0.0, 0.0);
      }
      final r = rec.result();
      expect(r.verdict, DriftVerdict.healthy);
      expect(r.driftPercent, 0);
      expect(r.direction, 'centred');
    });

    test('small wander is flagged minor', () {
      final rec = StickDriftRecorder();
      for (var i = 0; i < 20; i++) {
        rec.add(0.07, 0.0);
      }
      final r = rec.result();
      expect(r.verdict, DriftVerdict.minor);
      expect(r.direction, 'right');
    });

    test('big resting offset is drift, with a sensible dead-zone suggestion', () {
      final rec = StickDriftRecorder();
      for (var i = 0; i < 20; i++) {
        rec.add(0.0, -0.18); // stuck pulling down
      }
      final r = rec.result();
      expect(r.verdict, DriftVerdict.drift);
      expect(r.direction, 'down');
      expect(r.recommendedDeadZonePercent, 20);
    });

    test('tracks the farthest excursion, not just the average', () {
      final rec = StickDriftRecorder();
      rec.add(0.0, 0.0);
      rec.add(0.0, 0.0);
      rec.add(0.0, 0.12); // one spike past the drift threshold
      expect(rec.result().verdict, DriftVerdict.drift);
    });

    test('empty recorder is safe', () {
      expect(StickDriftRecorder().result().verdict, DriftVerdict.healthy);
    });
  });

  group('appliedMagnitude (dead zone math)', () {
    test('inside the dead zone reads as zero', () {
      expect(appliedMagnitude(0.05, 0.0, 0.1), 0.0);
    });
    test('outside the dead zone is rescaled to full travel', () {
      expect(appliedMagnitude(1.0, 0.0, 0.1), closeTo(1.0, 1e-9));
      expect(appliedMagnitude(0.55, 0.0, 0.1), closeTo(0.5, 1e-9));
    });
  });

  group('InputCoverage', () {
    test('tracks buttons and reports what is missing', () {
      final c = InputCoverage();
      c.markButton('a');
      c.markButton('b');
      expect(c.missingButtons(['a', 'b', 'x']), ['x']);
    });

    test('stick full range needs all four directions to reach the rim', () {
      final c = InputCoverage();
      c.markStick(StickSide.left, 0.95, 0); // right
      c.markStick(StickSide.left, -0.95, 0); // left
      c.markStick(StickSide.left, 0, 0.95); // up
      expect(c.stickFullRange(StickSide.left), isFalse);
      expect(c.missingDirections(StickSide.left), ['down']);
      c.markStick(StickSide.left, 0, -0.95); // down
      expect(c.stickFullRange(StickSide.left), isTrue);
      expect(c.missingDirections(StickSide.left), isEmpty);
    });

    test('a worn stick that never reaches the rim is flagged', () {
      final c = InputCoverage();
      for (final (x, y) in [(0.8, 0.0), (-0.8, 0.0), (0.0, 0.8), (0.0, -0.8)]) {
        c.markStick(StickSide.right, x, y);
      }
      expect(c.stickFullRange(StickSide.right), isFalse);
      expect(c.stickMaxMagnitude(StickSide.right), closeTo(0.8, 1e-9));
    });

    test('triggers must reach near full', () {
      final c = InputCoverage();
      c.markTrigger(StickSide.left, 0.5);
      expect(c.triggerFull(StickSide.left), isFalse);
      c.markTrigger(StickSide.left, 1.0);
      expect(c.triggerFull(StickSide.left), isTrue);
      expect(c.triggerMax(StickSide.left), 1.0);
    });

    test('isComplete only when everything has responded', () {
      final c = InputCoverage();
      const buttons = ['a', 'b'];
      void fullSticks() {
        for (final s in StickSide.values) {
          c.markStick(s, 1, 0);
          c.markStick(s, -1, 0);
          c.markStick(s, 0, 1);
          c.markStick(s, 0, -1);
          c.markTrigger(s, 1);
        }
      }
      fullSticks();
      expect(c.isComplete(buttons), isFalse); // buttons not pressed yet
      c.markButton('a');
      c.markButton('b');
      expect(c.isComplete(buttons), isTrue);
    });
  });
}
