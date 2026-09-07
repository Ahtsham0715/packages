import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';
import '../../widgets/vault_item_tile.dart';
import '../vault/item_detail_screen.dart';

/// Deleted entries, recoverable until they age out.
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null || !vault.isUnlocked) return const SizedBox.shrink();

    final trashed = vault.trashedItems;
    final controller = ref.read(vaultControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (trashed.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Empty the trash?'),
                    content: Text(
                      '${trashed.length} '
                      '${trashed.length == 1 ? 'entry' : 'entries'} will be '
                      'erased permanently.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: SableColors.danger,
                        ),
                        child: const Text('Empty'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await controller.emptyTrash();
              },
              child: const Text('Empty'),
            ),
        ],
      ),
      body: trashed.isEmpty
          ? const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'The trash is empty',
              message: 'Deleted entries wait here before being erased, so a '
                  'mistake is recoverable.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Space.lg, 0, Space.lg, Space.huge),
              children: [
                NoticeBanner(
                  icon: Icons.schedule_rounded,
                  message: 'Entries here are erased automatically '
                      '${vault.settings.trashRetentionDays} days after being '
                      'deleted.',
                ),
                const SizedBox(height: Space.lg),
                for (final item in trashed)
                  VaultItemTile(
                    item: item,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ItemDetailScreen(itemId: item.id),
                      ),
                    ),
                    trailing: IconButton(
                      onPressed: () => controller.restoreItem(item),
                      icon: const Icon(Icons.restore_rounded, size: 20),
                      tooltip: 'Restore',
                    ),
                  ),
              ],
            ),
    );
  }
}
