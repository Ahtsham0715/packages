import 'package:flutter/widgets.dart';

/// The Sablekey palette, spacing scale and motion constants.
///
/// The look is "obsidian and ember": a near-black ground with warm light
/// pushed through it, rather than the blue-grey that every Material app
/// defaults to. Accent colour is used sparingly and always means something —
/// an action, a warning, a strength reading — so it never becomes decoration.
///
/// Colours here are mirrored in `android/app/src/main/res/values/colors.xml`
/// for the launch screen and the autofill row, which are drawn by the system
/// before Flutter is running.
abstract final class SableColors {
  // --- Dark (the default; the app is designed dark-first) ----------------
  static const Color obsidian = Color(0xFF08070C);
  static const Color surface = Color(0xFF13111B);
  static const Color surfaceRaised = Color(0xFF1B1825);
  static const Color surfaceSunken = Color(0xFF0C0B11);
  static const Color hairline = Color(0x1AFFFFFF);
  static const Color hairlineStrong = Color(0x33FFFFFF);

  static const Color textPrimary = Color(0xFFEDE8F2);
  static const Color textSecondary = Color(0xFF9A93A8);
  static const Color textTertiary = Color(0xFF645D73);

  // --- Light ("parchment and ember") -------------------------------------
  static const Color parchment = Color(0xFFF7F4F0);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceRaisedLight = Color(0xFFFDFAF7);
  static const Color surfaceSunkenLight = Color(0xFFEFEAE4);
  static const Color hairlineLight = Color(0x14000000);
  static const Color hairlineStrongLight = Color(0x24000000);

  static const Color textPrimaryLight = Color(0xFF1A171F);
  static const Color textSecondaryLight = Color(0xFF5C5566);
  static const Color textTertiaryLight = Color(0xFF8B8394);

  // --- Ember (shared) -----------------------------------------------------
  static const Color emberBright = Color(0xFFFFC77A);
  static const Color ember = Color(0xFFF2803C);
  static const Color emberDeep = Color(0xFFD84A5F);

  /// The gradient from the app icon. Used for the strength meter, primary
  /// actions and the unlock screen glow.
  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emberBright, ember, emberDeep],
    stops: [0.0, 0.55, 1.0],
  );

  // --- Semantic -----------------------------------------------------------
  /// Strength and health readings, weakest to strongest.
  static const List<Color> strengthScale = [
    Color(0xFFE5484D), // very weak
    Color(0xFFEF7A3C), // weak
    Color(0xFFE6B54A), // fair
    Color(0xFF6FBF73), // strong
    Color(0xFF3FA9A0), // excellent
  ];

  static const Color danger = Color(0xFFE5484D);
  static const Color warning = Color(0xFFE6B54A);
  static const Color success = Color(0xFF6FBF73);
  static const Color info = Color(0xFF6E8CD8);

  /// A stable colour per item type, so entries are recognisable at a glance
  /// without needing a favicon the app is not allowed to download.
  static const List<Color> typeAccents = [
    Color(0xFFF2803C),
    Color(0xFF6E8CD8),
    Color(0xFF3FA9A0),
    Color(0xFFB07BD8),
    Color(0xFFE6B54A),
    Color(0xFF6FBF73),
    Color(0xFFD84A5F),
    Color(0xFF7FA0B8),
  ];

  /// Picks a type accent deterministically from a string.
  ///
  /// Deterministic rather than random so an entry keeps the same colour
  /// forever — the colour becomes part of how the user recognises it in a
  /// list.
  static Color accentFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return typeAccents[hash % typeAccents.length];
  }
}

/// The spacing scale. Everything in the UI is a multiple of these.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets card = EdgeInsets.all(lg);
}

/// Corner radii. The chamfer is what makes the shapes read as cut stone
/// rather than as rounded rectangles — see [FacetedBorder].
abstract final class Radii {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;

  /// How deep the cut corner bites, as a fraction of the shorter side.
  static const double chamfer = 18;
}

/// Animation timings.
///
/// Short and consistent. A password manager is opened dozens of times a day,
/// and animation that is charming on the first open is friction on the
/// fortieth.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasised = Curves.easeOutBack;
}
