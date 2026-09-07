import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/item_type.dart';
import '../theme/tokens.dart';

/// A hexagonal plate carrying an item's type icon.
///
/// The hexagon is the icon's shape, repeated at list scale. It also solves a
/// real problem: a password manager normally identifies entries by their site
/// favicon, and Sablekey cannot fetch one without a network. So identity comes
/// from a deterministic colour plus the type glyph, which is stable, instant,
/// and gives away nothing to an observer glancing at the screen.
class ItemAvatar extends StatelessWidget {
  const ItemAvatar({
    required this.type,
    required this.seed,
    this.size = 42,
    this.icon,
    super.key,
  });

  /// Renders a hexagon around an arbitrary icon, for uses outside the vault
  /// list (audit categories, settings sections).
  const ItemAvatar.custom({
    required IconData this.icon,
    required this.seed,
    this.size = 42,
    super.key,
  }) : type = null;

  final ItemType? type;

  /// Drives the colour. Usually the item name, so the colour never changes.
  final String seed;

  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = SableColors.accentFor(seed);
    final glyph = icon ?? type?.icon ?? Icons.lock_rounded;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HexPainter(
          fill: accent.withValues(alpha: 0.16),
          stroke: accent.withValues(alpha: 0.55),
        ),
        child: Center(
          child: Icon(glyph, size: size * 0.44, color: accent),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final path = Path();
    for (var i = 0; i < 6; i++) {
      // Flat-top hexagon: reads more stable in a vertical list than a
      // pointy-top one, which looks like it is about to fall over.
      final angle = math.pi / 180 * (60 * i);
      final point = Offset(
        centre.dx + radius * math.cos(angle),
        centre.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  @override
  bool shouldRepaint(_HexPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.stroke != stroke;
}
