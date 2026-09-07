import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/crypto/totp.dart';
import '../theme/tokens.dart';

/// Live TOTP code with a ring that drains as it expires.
///
/// Refreshes once a second — enough for the ring to look continuous without
/// waking the framework 60 times a second for an animation nobody is watching
/// closely. The code is recomputed only when the counter window changes, not on
/// every tick.
class TotpBadge extends StatefulWidget {
  const TotpBadge({
    required this.config,
    this.onCopy,
    this.compact = false,
    super.key,
  });

  final TotpConfig config;
  final ValueChanged<String>? onCopy;
  final bool compact;

  @override
  State<TotpBadge> createState() => _TotpBadgeState();
}

class _TotpBadgeState extends State<TotpBadge> {
  Timer? _ticker;
  TotpCode? _code;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(TotpBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.secret != widget.config.secret) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final code = await Totp.generate(widget.config);
      if (!mounted) return;
      setState(() {
        _code = code;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return Text(
        'This two-factor secret could not be read',
        style: theme.textTheme.bodySmall?.copyWith(color: SableColors.danger),
      );
    }

    final code = _code;
    if (code == null) {
      return SizedBox(
        height: widget.compact ? 20 : 44,
        child: const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final colour = code.isExpiring ? SableColors.warning : SableColors.ember;

    return InkWell(
      onTap: widget.onCopy == null ? null : () => widget.onCopy!(code.value),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.compact ? 18 : 26,
              height: widget.compact ? 18 : 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // TweenAnimationBuilder smooths the once-a-second jump into a
                  // continuous sweep.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: code.fractionRemaining, end: code.fractionRemaining),
                    duration: const Duration(milliseconds: 950),
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: widget.compact ? 2 : 2.6,
                      backgroundColor: theme.colorScheme.outlineVariant,
                      valueColor: AlwaysStoppedAnimation(colour),
                    ),
                  ),
                  if (!widget.compact)
                    Text(
                      '${code.secondsRemaining}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: colour,
                        letterSpacing: 0,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            Text(
              code.formatted,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'monospace'],
                fontSize: widget.compact ? 14 : 20,
                fontWeight: FontWeight.w600,
                letterSpacing: widget.compact ? 1.0 : 2.0,
                color: colour,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (widget.onCopy != null && !widget.compact) ...[
              const SizedBox(width: Space.sm),
              Icon(
                Icons.copy_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
