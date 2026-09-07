import 'package:flutter/material.dart';

import '../../../domain/models/item_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/item_avatar.dart';

/// Lets the user pick what kind of entry to create.
Future<ItemType?> showItemTypeSheet(BuildContext context) {
  return showModalBottomSheet<ItemType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _ItemTypeSheet(),
  );
}

class _ItemTypeSheet extends StatelessWidget {
  const _ItemTypeSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.xl, 0, Space.xl, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New entry', style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  'Every type is stored the same way — sealed before it '
                  'touches the database.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                  Space.md, 0, Space.md, Space.xl),
              itemCount: ItemType.values.length,
              itemBuilder: (context, index) {
                final type = ItemType.values[index];
                return ListTile(
                  leading: ItemAvatar(type: type, seed: type.id, size: 38),
                  title: Text(type.label),
                  subtitle: Text(type.description),
                  onTap: () => Navigator.of(context).pop(type),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
