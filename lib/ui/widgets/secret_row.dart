import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/sable_theme.dart';
import '../theme/tokens.dart';

/// One labelled value on the detail screen.
///
/// Secrets start masked and are revealed only on an explicit tap, which is not
/// theatre: the most common way a password leaks is somebody standing behind
/// you while you look something else up on the same screen.
class DetailRow extends StatefulWidget {
  const DetailRow({
    required this.label,
    required this.value,
    this.isSecret = false,
    this.monospace = false,
    this.onCopy,
    this.onOpen,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final bool isSecret;
  final bool monospace;
  final VoidCallback? onCopy;

  /// Shown as an "open" affordance for URLs.
  final VoidCallback? onOpen;

  final Widget? trailing;

  @override
  State<DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<DetailRow> {
  bool _revealed = false;

  @override
  void didUpdateWidget(DetailRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-mask if the underlying value changes beneath us.
    if (oldWidget.value != widget.value) _revealed = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = widget.isSecret && !_revealed;
    final display = hidden ? '•' * widget.value.length.clamp(8, 24) : widget.value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: theme.textTheme.labelSmall),
                const SizedBox(height: Space.xs),
                SelectionArea(
                  // Selection is disabled while masked, or a long-press would
                  // copy the bullet characters and look broken.
                  child: hidden
                      ? Text(display, style: SableTheme.mono(context))
                      : Text(
                          display,
                          style: widget.monospace || widget.isSecret
                              ? SableTheme.mono(context)
                              : theme.textTheme.bodyLarge,
                        ),
                ),
              ],
            ),
          ),
          if (widget.isSecret)
            IconButton(
              onPressed: () => setState(() => _revealed = !_revealed),
              iconSize: 19,
              visualDensity: VisualDensity.compact,
              tooltip: _revealed ? 'Hide' : 'Reveal',
              icon: Icon(_revealed
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded),
            ),
          if (widget.onOpen != null)
            IconButton(
              onPressed: widget.onOpen,
              iconSize: 19,
              visualDensity: VisualDensity.compact,
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new_rounded),
            ),
          if (widget.onCopy != null)
            IconButton(
              onPressed: () {
                widget.onCopy!();
                HapticFeedback.selectionClick();
              },
              iconSize: 19,
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded),
            ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
  }
}

/// A countdown chip shown after copying a secret.
class ClipboardCountdown extends StatelessWidget {
  const ClipboardCountdown({required this.seconds, super.key});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, size: 15, color: SableColors.emberBright),
        const SizedBox(width: Space.sm),
        Text(
          'Clipboard clears in ${seconds}s',
          style: theme.textTheme.bodySmall?.copyWith(
            color: SableColors.emberBright,
          ),
        ),
      ],
    );
  }
}
