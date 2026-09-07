import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'faceted_border.dart';
import 'tokens.dart';

/// Builds the app's two themes.
///
/// No downloaded fonts. A font package that fetches its files at runtime would
/// mean the app opens a socket, which is the one thing Sablekey promises it
/// cannot do. The type scale below is tuned on the platform's own font instead:
/// tight tracking on headings, generous line height on body text, and a
/// tabular-figure style for anything showing a code or a secret.
abstract final class SableTheme {
  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: SableColors.obsidian,
        surface: SableColors.surface,
        surfaceRaised: SableColors.surfaceRaised,
        surfaceSunken: SableColors.surfaceSunken,
        hairline: SableColors.hairline,
        hairlineStrong: SableColors.hairlineStrong,
        textPrimary: SableColors.textPrimary,
        textSecondary: SableColors.textSecondary,
        textTertiary: SableColors.textTertiary,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: SableColors.parchment,
        surface: SableColors.surfaceLight,
        surfaceRaised: SableColors.surfaceRaisedLight,
        surfaceSunken: SableColors.surfaceSunkenLight,
        hairline: SableColors.hairlineLight,
        hairlineStrong: SableColors.hairlineStrongLight,
        textPrimary: SableColors.textPrimaryLight,
        textSecondary: SableColors.textSecondaryLight,
        textTertiary: SableColors.textTertiaryLight,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceRaised,
    required Color surfaceSunken,
    required Color hairline,
    required Color hairlineStrong,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
  }) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: SableColors.ember,
      onPrimary: const Color(0xFF1A0E06),
      primaryContainer: isDark
          ? const Color(0xFF3A2416)
          : const Color(0xFFFFE6CF),
      onPrimaryContainer:
          isDark ? SableColors.emberBright : const Color(0xFF4A2A12),
      secondary: SableColors.emberBright,
      onSecondary: const Color(0xFF1A0E06),
      error: SableColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceRaised,
      surfaceContainerLow: surfaceSunken,
      onSurfaceVariant: textSecondary,
      outline: hairlineStrong,
      outlineVariant: hairline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: textPrimary,
      onInverseSurface: background,
      inversePrimary: SableColors.emberDeep,
    );

    final textTheme = _textTheme(textPrimary, textSecondary, textTertiary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: textPrimary, size: 22),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: FacetedBorder(
          radius: Radii.lg,
          chamfer: Radii.chamfer,
          side: BorderSide(color: hairline),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textTertiary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        floatingLabelStyle: textTheme.labelLarge?.copyWith(
          color: SableColors.ember,
        ),
        border: _inputBorder(hairline),
        enabledBorder: _inputBorder(hairline),
        focusedBorder: _inputBorder(SableColors.ember, width: 1.5),
        errorBorder: _inputBorder(SableColors.danger),
        focusedErrorBorder: _inputBorder(SableColors.danger, width: 1.5),
        errorStyle: textTheme.bodySmall?.copyWith(color: SableColors.danger),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SableColors.ember,
          foregroundColor: const Color(0xFF1A0E06),
          disabledBackgroundColor: hairlineStrong,
          disabledForegroundColor: textTertiary,
          minimumSize: const Size.fromHeight(54),
          textStyle: textTheme.labelLarge,
          shape: const FacetedBorder(radius: Radii.md, chamfer: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: hairlineStrong),
          textStyle: textTheme.labelLarge,
          shape: const FacetedBorder(radius: Radii.md, chamfer: 14),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SableColors.ember,
          textStyle: textTheme.labelLarge,
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: SableColors.ember,
        foregroundColor: const Color(0xFF1A0E06),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const FacetedBorder(radius: Radii.lg, chamfer: 16),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        showDragHandle: true,
        dragHandleColor: hairlineStrong,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
        shape: const FacetedBorder(radius: Radii.lg, chamfer: Radii.chamfer),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textPrimary),
        actionTextColor: SableColors.emberBright,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const FacetedBorder(radius: Radii.md, chamfer: 14),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceSunken,
        selectedColor: SableColors.ember.withValues(alpha: 0.18),
        side: BorderSide(color: hairline),
        labelStyle: textTheme.labelMedium!,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        shape: const FacetedBorder(radius: Radii.sm, chamfer: 8),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? SableColors.ember
                : textTertiary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? SableColors.ember.withValues(alpha: 0.25)
                : surfaceSunken),
        trackOutlineColor: WidgetStatePropertyAll(hairlineStrong),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.xs,
        ),
        shape: const FacetedBorder(radius: Radii.md, chamfer: 12),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SableColors.ember,
        linearTrackColor: Colors.transparent,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: hairline),
        ),
        textStyle: textTheme.bodySmall,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color colour, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: colour, width: width),
      );

  static TextTheme _textTheme(
      Color primary, Color secondary, Color tertiary) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.9,
        color: primary,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: primary,
      ),
      headlineSmall: TextStyle(
        fontSize: 21,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14.5,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: primary,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      // Used for section headers above grouped lists.
      labelSmall: TextStyle(
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: tertiary,
      ),
    );
  }

  /// Style for anything showing a secret, a code or a fingerprint.
  ///
  /// Monospace with a wide-open zero: the difference between `O` and `0` in a
  /// password being read aloud is not a detail.
  static TextStyle mono(BuildContext context, {double? size, Color? colour}) {
    final theme = Theme.of(context);
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono', 'monospace'],
      fontSize: size ?? 15,
      height: 1.5,
      letterSpacing: 0.6,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: colour ?? theme.colorScheme.onSurface,
    );
  }
}
