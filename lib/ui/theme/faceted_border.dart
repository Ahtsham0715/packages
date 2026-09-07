import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Which corner is cut away.
enum FacetCorner { topLeft, topRight, bottomLeft, bottomRight, none }

/// A rounded rectangle with one corner sliced off at 45 degrees.
///
/// This is the shape signature of the app. It comes from the icon — a hexagon
/// of cut obsidian — and carrying the same cut into cards, buttons and sheets
/// is what stops the UI from looking like every other Material app with a new
/// colour scheme.
///
/// The chamfer is on one corner only, and always the same corner within a given
/// context, so it reads as a deliberate cut rather than as a shape that could
/// not decide what it was.
class FacetedBorder extends OutlinedBorder {
  const FacetedBorder({
    this.radius = 18,
    this.chamfer = 18,
    this.corner = FacetCorner.topRight,
    super.side = BorderSide.none,
  });

  final double radius;

  /// Length of the cut along each edge meeting [corner].
  final double chamfer;

  final FacetCorner corner;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => FacetedBorder(
        radius: radius * t,
        chamfer: chamfer * t,
        corner: corner,
        side: side.scale(t),
      );

  @override
  FacetedBorder copyWith({
    BorderSide? side,
    double? radius,
    double? chamfer,
    FacetCorner? corner,
  }) =>
      FacetedBorder(
        radius: radius ?? this.radius,
        chamfer: chamfer ?? this.chamfer,
        corner: corner ?? this.corner,
        side: side ?? this.side,
      );

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _build(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _build(rect);

  Path _build(Rect rect) {
    // Clamp so a small widget cannot produce a shape that folds in on itself.
    final maxCut = math.min(rect.width, rect.height) / 2;
    final cut = chamfer.clamp(0.0, maxCut);
    final r = radius.clamp(0.0, maxCut);

    final path = Path();
    final left = rect.left;
    final top = rect.top;
    final right = rect.right;
    final bottom = rect.bottom;

    /// Sweeps a quarter-circle of radius [r] centred on [centre].
    void quarterArc(Offset centre, double startAngle) {
      path.arcTo(
        Rect.fromCircle(center: centre, radius: r),
        startAngle,
        math.pi / 2,
        false,
      );
    }

    // Trace clockwise from the top-left corner.
    if (corner == FacetCorner.topLeft) {
      path.moveTo(left, top + cut);
      path.lineTo(left + cut, top);
    } else {
      path.moveTo(left, top + r);
      quarterArc(Offset(left + r, top + r), math.pi);
    }

    if (corner == FacetCorner.topRight) {
      path.lineTo(right - cut, top);
      path.lineTo(right, top + cut);
    } else {
      path.lineTo(right - r, top);
      quarterArc(Offset(right - r, top + r), -math.pi / 2);
    }

    if (corner == FacetCorner.bottomRight) {
      path.lineTo(right, bottom - cut);
      path.lineTo(right - cut, bottom);
    } else {
      path.lineTo(right, bottom - r);
      quarterArc(Offset(right - r, bottom - r), 0);
    }

    if (corner == FacetCorner.bottomLeft) {
      path.lineTo(left + cut, bottom);
      path.lineTo(left, bottom - cut);
    } else {
      path.lineTo(left + r, bottom);
      quarterArc(Offset(left + r, bottom - r), math.pi / 2);
    }

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      _build(rect.deflate(side.width / 2)),
      side.toPaint(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FacetedBorder &&
      other.radius == radius &&
      other.chamfer == chamfer &&
      other.corner == corner &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, chamfer, corner, side);
}

/// Draws a hairline of light along the chamfer, as if the cut face were
/// catching the light.
///
/// Purely decorative, and deliberately faint: at full strength it turns every
/// card into a diagram of itself.
class FacetHighlight extends StatelessWidget {
  const FacetHighlight({
    required this.child,
    this.corner = FacetCorner.topRight,
    this.chamfer = 18,
    this.colour,
    super.key,
  });

  final Widget child;
  final FacetCorner corner;
  final double chamfer;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _FacetHighlightPainter(
        corner: corner,
        chamfer: chamfer,
        colour: colour ?? const Color(0x33FFFFFF),
      ),
      child: child,
    );
  }
}

class _FacetHighlightPainter extends CustomPainter {
  const _FacetHighlightPainter({
    required this.corner,
    required this.chamfer,
    required this.colour,
  });

  final FacetCorner corner;
  final double chamfer;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (corner == FacetCorner.none) return;
    final cut = chamfer.clamp(0.0, math.min(size.width, size.height) / 2);

    final (Offset from, Offset to) = switch (corner) {
      FacetCorner.topLeft => (Offset(0, cut), Offset(cut, 0)),
      FacetCorner.topRight =>
        (Offset(size.width - cut, 0), Offset(size.width, cut)),
      FacetCorner.bottomRight => (
          Offset(size.width, size.height - cut),
          Offset(size.width - cut, size.height)
        ),
      FacetCorner.bottomLeft => (
          Offset(cut, size.height),
          Offset(0, size.height - cut)
        ),
      FacetCorner.none => (Offset.zero, Offset.zero),
    };

    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = colour
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FacetHighlightPainter oldDelegate) =>
      oldDelegate.corner != corner ||
      oldDelegate.chamfer != chamfer ||
      oldDelegate.colour != colour;
}
