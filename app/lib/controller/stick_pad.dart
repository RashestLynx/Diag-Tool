import 'package:flutter/material.dart';

/// A square pad that shows one analog stick: crosshairs, an optional dead-zone
/// circle, an optional drift ring (how far the stick wandered at rest), and a
/// live dot for the current position.
class StickPad extends StatelessWidget {
  const StickPad({
    super.key,
    required this.x,
    required this.y,
    this.deadZone = 0,
    this.driftRing = 0,
  });

  /// Current stick position, each -1.0..1.0 (Y positive = up).
  final double x;
  final double y;

  /// Dead-zone radius as a fraction of full travel (0 = don't draw).
  final double deadZone;

  /// Resting-drift radius as a fraction of full travel (0 = don't draw).
  final double driftRing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _StickPainter(
          x: x,
          y: y,
          deadZone: deadZone,
          driftRing: driftRing,
          grid: scheme.outlineVariant,
          dot: scheme.primary,
          dead: scheme.outline,
          drift: scheme.error,
        ),
      ),
    );
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter({
    required this.x,
    required this.y,
    required this.deadZone,
    required this.driftRing,
    required this.grid,
    required this.dot,
    required this.dead,
    required this.drift,
  });

  final double x, y, deadZone, driftRing;
  final Color grid, dot, dead, drift;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 6;

    final boundary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = grid;
    canvas.drawCircle(center, radius, boundary);

    // Crosshairs.
    final cross = Paint()
      ..color = grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), cross);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), cross);

    // Dead-zone circle.
    if (deadZone > 0) {
      canvas.drawCircle(
        center,
        radius * deadZone,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = dead,
      );
    }

    // Drift ring: how far it wandered while resting.
    if (driftRing > 0.01) {
      canvas.drawCircle(
        center,
        radius * driftRing.clamp(0, 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = drift.withValues(alpha: 0.7),
      );
    }

    // Live position dot (Y is up-positive, so invert for screen coords).
    final pos = Offset(
      center.dx + x.clamp(-1.0, 1.0) * radius,
      center.dy - y.clamp(-1.0, 1.0) * radius,
    );
    canvas.drawLine(center, pos, Paint()
      ..color = dot.withValues(alpha: 0.5)
      ..strokeWidth = 2);
    canvas.drawCircle(pos, 8, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_StickPainter old) =>
      old.x != x || old.y != y || old.deadZone != deadZone || old.driftRing != driftRing;
}
