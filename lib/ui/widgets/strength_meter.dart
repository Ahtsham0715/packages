import 'package:flutter/material.dart';

import '../../domain/services/password_strength.dart';
import '../theme/tokens.dart';

/// A five-segment strength readout with the entropy stated in figures.
///
/// The bar alone invites the reading "green means safe". Printing the actual
/// bits and the estimated crack time next to it turns a vague reassurance into
/// something the user can reason about — and makes it obvious why a long
/// passphrase beats a short string of symbols.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({
    required this.strength,
    this.showDetail = true,
    this.compact = false,
    super.key,
  });

  final PasswordStrength strength;
  final bool showDetail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = SableColors.strengthScale[strength.score.clamp(0, 4)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 5; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.standard,
                  curve: Motion.enter,
                  height: compact ? 3 : 5,
                  decoration: BoxDecoration(
                    color: i <= strength.score
                        ? colour
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (i < 4) const SizedBox(width: Space.xs),
            ],
          ],
        ),
        if (showDetail) ...[
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Text(
                strength.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colour,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${strength.entropyBits.round()} bits',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: Space.xxs),
            Text(
              strength.isCommon
                  ? 'Found in the bundled list of most-guessed passwords'
                  : 'An offline attacker would need about '
                      '${strength.offlineCrackTime}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: strength.isCommon
                    ? SableColors.danger
                    : theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// The warnings and suggestions from an estimate, as a bulleted list.
class StrengthAdvice extends StatelessWidget {
  const StrengthAdvice({required this.strength, super.key});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [...strength.warnings, ...strength.suggestions];
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(line, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
