import 'package:flutter/material.dart';

import '../../domain/models/vault_item.dart';
import '../theme/tokens.dart';
import 'item_avatar.dart';

/// One row in the vault list.
class VaultItemTile extends StatelessWidget {
  const VaultItemTile({
    required this.item,
    required this.onTap,
    this.onFavourite,
    this.concealSubtitle = false,
    this.trailing,
    super.key,
  });

  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback? onFavourite;

  /// Masks the username, for use somewhere overlooked.
  final bool concealSubtitle;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _subtitle();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            ItemAvatar(type: item.type, seed: item.name),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name.isEmpty ? 'Untitled' : item.name,
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.totp != null) ...[
                        const SizedBox(width: Space.sm),
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                      if (item.attachmentIds.isNotEmpty) ...[
                        const SizedBox(width: Space.xs),
                        Icon(
                          Icons.attach_file_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      concealSubtitle ? _mask(subtitle) : subtitle,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onFavourite != null)
              IconButton(
                onPressed: onFavourite,
                iconSize: 19,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  item.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: item.favourite
                      ? SableColors.emberBright
                      : theme.colorScheme.onSurfaceVariant,
                ),
                tooltip: item.favourite ? 'Remove favourite' : 'Add favourite',
              ),
          ],
        ),
      ),
    );
  }

  /// The most useful identifying line for this type — username for a login,
  /// the masked number for a card, and so on.
  String? _subtitle() {
    final username = item.username;
    if (username != null && username.isNotEmpty) return username;

    final primary = item.primaryValue;
    if (primary == null || primary.isEmpty) return item.type.label;

    final spec = item.type.specFor(item.type.primaryKey);
    if (spec?.isSecret ?? false) {
      // Never print a secret in a list. A card number becomes its last four,
      // which is what identifies it to its owner anyway.
      final digits = primary.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) return '•••• ${digits.substring(digits.length - 4)}';
      return item.type.label;
    }
    return primary;
  }

  static String _mask(String value) {
    if (value.length <= 2) return '••••';
    return '${value[0]}${'•' * (value.length - 2).clamp(3, 10)}'
        '${value[value.length - 1]}';
  }
}
