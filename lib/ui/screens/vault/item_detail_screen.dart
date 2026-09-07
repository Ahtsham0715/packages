import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/vault_item.dart';
import '../../../domain/services/health_auditor.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/item_avatar.dart';
import '../../widgets/secret_row.dart';
import '../../widgets/strength_meter.dart';
import '../../widgets/surfaces.dart';
import '../../widgets/totp_badge.dart';
import 'item_editor_screen.dart';

/// Everything stored on one entry.
///
/// Reads the item from the controller by id rather than taking a snapshot, so
/// an edit made on the editor screen is reflected the moment the user comes
/// back, and so the screen empties itself if the vault locks underneath it.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null || !vault.isUnlocked) {
      return const Scaffold(body: SizedBox.shrink());
    }

    VaultItem? item;
    for (final candidate in vault.items) {
      if (candidate.id == itemId) {
        item = candidate;
        break;
      }
    }

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.help_outline_rounded,
          title: 'This entry is gone',
          message: 'It was deleted or purged while this screen was open.',
        ),
      );
    }

    return _DetailBody(item: item);
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.item});

  final VaultItem item;

  Future<void> _copy(
    BuildContext context,
    WidgetRef ref,
    String value, {
    required bool secret,
    required String label,
  }) async {
    final clipboard = ref.read(clipboardProvider);
    final settings = ref.read(vaultControllerProvider).requireValue.settings;
    clipboard.clearAfter = Duration(seconds: settings.clipboardClearSeconds);

    if (secret) {
      await clipboard.copySecret(value);
      await ref.read(vaultControllerProvider.notifier).noteItemUsed(item);
    } else {
      await clipboard.copyPlain(value);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          secret && settings.clipboardClearSeconds > 0
              ? '$label copied — clipboard clears in '
                  '${settings.clipboardClearSeconds}s'
              : '$label copied',
        ),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).requireValue;

    ItemHealth? health;
    for (final result in vault.health.results) {
      if (result.item.id == item.id) {
        health = result;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(item.type.label),
        actions: [
          IconButton(
            onPressed: () => ref
                .read(vaultControllerProvider.notifier)
                .toggleFavourite(item),
            icon: Icon(item.favourite
                ? Icons.star_rounded
                : Icons.star_outline_rounded),
            color: item.favourite ? SableColors.emberBright : null,
            tooltip: 'Favourite',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ItemEditorScreen(item: item)),
            ),
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit',
          ),
          _OverflowMenu(item: item),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.huge),
        children: [
          _Hero(item: item),

          if (item.isDeleted) ...[
            const SizedBox(height: Space.lg),
            const NoticeBanner(
              tone: NoticeTone.warning,
              icon: Icons.delete_outline_rounded,
              message: 'This entry is in the trash. Restore it to use it '
                  'again.',
            ),
          ],

          if (health != null && !health.isHealthy) ...[
            const SizedBox(height: Space.lg),
            _HealthCallout(health: health),
          ],

          const SizedBox(height: Space.lg),
          SableCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final spec in item.type.fields)
                  if ((item.fields[spec.key] ?? '').isNotEmpty)
                    DetailRow(
                      label: spec.label,
                      value: item.fields[spec.key]!,
                      isSecret: spec.isSecret,
                      monospace: spec.isSecret,
                      onCopy: () => _copy(
                        context,
                        ref,
                        item.fields[spec.key]!,
                        secret: spec.isSecret,
                        label: spec.label,
                      ),
                    ),
              ],
            ),
          ),

          if (item.totp != null) ...[
            const SectionHeader('Two-factor code'),
            SableCard(
              child: TotpBadge(
                config: item.totp!,
                onCopy: (code) => _copy(
                  context,
                  ref,
                  code,
                  secret: true,
                  label: 'Code',
                ),
              ),
            ),
          ],

          if (item.customFields.isNotEmpty) ...[
            const SectionHeader('Custom fields'),
            SableCard(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final field in item.customFields)
                    DetailRow(
                      label: field.label,
                      value: field.value,
                      isSecret: field.kind.isSecret,
                      onCopy: () => _copy(
                        context,
                        ref,
                        field.value,
                        secret: field.kind.isSecret,
                        label: field.label,
                      ),
                    ),
                ],
              ),
            ),
          ],

          if (item.notes.trim().isNotEmpty) ...[
            const SectionHeader('Notes'),
            SableCard(
              child: SelectableText(
                item.notes,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],

          if (item.extraUris.isNotEmpty) ...[
            const SectionHeader('Also fills on'),
            SableCard(
              child: Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final uri in item.extraUris) Chip(label: Text(uri)),
                ],
              ),
            ),
          ],

          if (item.tags.isNotEmpty) ...[
            const SectionHeader('Tags'),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final tag in item.tags)
                  Chip(
                    avatar: const Icon(Icons.tag_rounded, size: 14),
                    label: Text(tag),
                  ),
              ],
            ),
          ],

          if (item.passwordHistory.isNotEmpty) ...[
            const SectionHeader('Password history'),
            SableCard(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(
                children: [
                  for (final entry in item.passwordHistory)
                    DetailRow(
                      label: 'Replaced ${_relative(entry.replacedAt)}',
                      value: entry.value,
                      isSecret: true,
                      monospace: true,
                      onCopy: () => _copy(
                        context,
                        ref,
                        entry.value,
                        secret: true,
                        label: 'Previous password',
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SectionHeader('Details'),
          SableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetaLine(label: 'Created', value: _relative(item.createdAt)),
                _MetaLine(label: 'Updated', value: _relative(item.updatedAt)),
                if (item.passwordUpdatedAt != null)
                  _MetaLine(
                    label: 'Password changed',
                    value: _relative(item.passwordUpdatedAt!),
                  ),
                if (item.lastUsedAt != null)
                  _MetaLine(
                    label: 'Last used',
                    value: _relative(item.lastUsedAt!),
                  ),
                if (item.useCount > 0)
                  _MetaLine(label: 'Used', value: '${item.useCount} times'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final difference = DateTime.now().difference(when);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} h ago';
    if (difference.inDays < 30) return '${difference.inDays} days ago';
    if (difference.inDays < 365) {
      return '${(difference.inDays / 30).round()} months ago';
    }
    return '${(difference.inDays / 365).round()} years ago';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item});

  final VaultItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ItemAvatar(type: item.type, seed: item.name, size: 56),
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name.isEmpty ? 'Untitled' : item.name,
                style: theme.textTheme.headlineSmall,
              ),
              if (item.username != null)
                Text(item.username!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthCallout extends StatelessWidget {
  const _HealthCallout({required this.health});

  final ItemHealth health;

  @override
  Widget build(BuildContext context) {
    final worst = health.worst;
    if (worst == null) return const SizedBox.shrink();

    final tone = switch (worst) {
      HealthIssue.compromised || HealthIssue.expired => NoticeTone.danger,
      HealthIssue.weak || HealthIssue.reused => NoticeTone.warning,
      _ => NoticeTone.info,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoticeBanner(
          tone: tone,
          icon: Icons.shield_outlined,
          message: '${worst.title}. ${worst.detail}'
              '${worst == HealthIssue.reused ? ' Shared with '
                  '${health.reuseCount - 1} other '
                  '${health.reuseCount == 2 ? 'entry' : 'entries'}.' : ''}',
        ),
        if (health.strength.entropyBits > 0) ...[
          const SizedBox(height: Space.md),
          StrengthMeter(strength: health.strength, compact: true),
        ],
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.item});

  final VaultItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(vaultControllerProvider.notifier);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (choice) async {
        switch (choice) {
          case 'trash':
            await controller.trashItem(item);
            if (context.mounted) Navigator.of(context).pop();
          case 'restore':
            await controller.restoreItem(item);
          case 'purge':
            final confirmed = await _confirmPurge(context);
            if (confirmed && context.mounted) {
              await controller.purgeItem(item);
              if (context.mounted) Navigator.of(context).pop();
            }
        }
      },
      itemBuilder: (context) => [
        if (!item.isDeleted)
          const PopupMenuItem(
            value: 'trash',
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('Move to trash'),
              contentPadding: EdgeInsets.zero,
            ),
          )
        else ...[
          const PopupMenuItem(
            value: 'restore',
            child: ListTile(
              leading: Icon(Icons.restore_rounded),
              title: Text('Restore'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'purge',
            child: ListTile(
              leading: Icon(Icons.delete_forever_rounded),
              title: Text('Delete permanently'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }

  Future<bool> _confirmPurge(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          '"${item.name}" and everything attached to it will be erased. '
          'There is no undo, and no copy of it anywhere else.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: SableColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
