import 'package:flutter/material.dart';

import '../theme/faceted_border.dart';
import '../theme/tokens.dart';

/// The standard container: a faceted card with a hairline edge and a lit cut.
class SableCard extends StatelessWidget {
  const SableCard({
    required this.child,
    this.padding = Space.card,
    this.onTap,
    this.corner = FacetCorner.topRight,
    this.accent,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final FacetCorner corner;

  /// When set, tints the border and the lit cut. Used to carry an item's type
  /// colour without flooding the card with it.
  final Color? accent;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = FacetedBorder(
      radius: Radii.lg,
      chamfer: Radii.chamfer,
      corner: corner,
      side: BorderSide(
        color: selected
            ? SableColors.ember
            : (accent?.withValues(alpha: 0.35) ?? theme.colorScheme.outlineVariant),
        width: selected ? 1.5 : 1,
      ),
    );

    return Material(
      color: theme.colorScheme.surface,
      shape: border,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: border,
        child: FacetHighlight(
          corner: corner,
          chamfer: Radii.chamfer,
          colour: (accent ?? SableColors.emberBright).withValues(alpha: 0.35),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A small uppercase label above a group of rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {this.action, this.icon, super.key});

  final String label;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: theme.textTheme.labelSmall?.color),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Shown when a list has nothing in it.
///
/// Always says what to do next rather than only what is missing — an empty
/// state that just says "No items" leaves the user to guess.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerLow,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.xl),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: Space.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A short strip of ember gradient, used as a rule under headings.
class EmberRule extends StatelessWidget {
  const EmberRule({this.width = 44, this.height = 3, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: SableColors.emberGradient,
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
    );
  }
}

/// An inline warning or note.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = NoticeTone.info,
    this.action,
    super.key,
  });

  final String message;
  final IconData icon;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = switch (tone) {
      NoticeTone.info => SableColors.info,
      NoticeTone.warning => SableColors.warning,
      NoticeTone.danger => SableColors.danger,
      NoticeTone.success => SableColors.success,
    };

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colour.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: Space.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, danger, success }
