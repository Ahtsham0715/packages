import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/item_type.dart';
import '../../../domain/models/vault_item.dart';
import '../../../domain/services/search_engine.dart';
import '../../../state/search_state.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';
import '../../widgets/vault_item_tile.dart';
import '../audit/audit_screen.dart';
import '../generator/generator_screen.dart';
import '../settings/settings_screen.dart';
import 'item_detail_screen.dart';
import 'item_editor_screen.dart';
import 'item_type_sheet.dart';

/// The main screen once the vault is open.
class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          _VaultTab(),
          GeneratorScreen(),
          AuditScreen(),
          SettingsScreen(),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _createItem(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Vault',
          ),
          NavigationDestination(
            icon: Icon(Icons.casino_outlined),
            selectedIcon: Icon(Icons.casino_rounded),
            label: 'Generate',
          ),
          NavigationDestination(
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety_rounded),
            label: 'Health',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _createItem(BuildContext context) async {
    final type = await showItemTypeSheet(context);
    if (type == null || !context.mounted) return;
    await Navigator.of(context).push<VaultItem>(
      MaterialPageRoute(
        builder: (_) => ItemEditorScreen(item: VaultItem.blank(type)),
      ),
    );
  }
}

class _VaultTab extends ConsumerStatefulWidget {
  const _VaultTab();

  @override
  ConsumerState<_VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends ConsumerState<_VaultTab> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchTextProvider);
    final typeFilter = ref.watch(typeFilterProvider);

    if (vault == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Column(
        children: [
          _Header(itemCount: vault.liveItems.length),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: _SearchField(
              controller: _searchController,
              onChanged: (value) =>
                  ref.read(searchTextProvider.notifier).state = value,
            ),
          ),
          const SizedBox(height: Space.md),
          _TypeFilterRow(
            selected: typeFilter,
            onSelected: (value) =>
                ref.read(typeFilterProvider.notifier).state = value,
          ),
          const SizedBox(height: Space.sm),
          Expanded(
            child: results.isEmpty
                ? _emptyState(vault.liveItems.isEmpty, query)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        Space.md, Space.sm, Space.md, 96),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return VaultItemTile(
                        item: item,
                        concealSubtitle: vault.settings.concealUsernamesInList,
                        onFavourite: () => ref
                            .read(vaultControllerProvider.notifier)
                            .toggleFavourite(item),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ItemDetailScreen(itemId: item.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool vaultIsEmpty, String query) {
    if (vaultIsEmpty) {
      return const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Your vault is empty',
        message: 'Tap New to add your first login, card or note — or import '
            'an export from another password manager in Settings.',
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'Nothing matched',
      message: query.contains(':')
          ? 'No entries match those filters.'
          : 'Try a shorter search, or use a filter like type:login or '
              'has:totp.',
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.md, Space.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vault', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 2),
                Text(
                  '$itemCount ${itemCount == 1 ? 'entry' : 'entries'}, '
                  'encrypted on this device',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => ref.read(vaultControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock_rounded),
            tooltip: 'Lock now',
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerLow,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search, or try type:login  has:totp  is:weak',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? IconButton(
                icon: const Icon(Icons.help_outline_rounded, size: 19),
                tooltip: 'Search operators',
                onPressed: () => _showOperatorHelp(context),
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 19),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
      ),
    );
  }

  void _showOperatorHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.xl, 0, Space.xl, Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Search operators', style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.md),
                Text(
                  'Combine any of these with ordinary search text. Quoted '
                  'phrases are matched exactly.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.lg),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final operator in SearchEngine.operatorHelp)
                      Chip(label: Text(operator)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TypeFilterRow extends StatelessWidget {
  const _TypeFilterRow({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  /// Only the types most people use often. The rest are reachable through
  /// `type:` in the search box, which keeps this row scannable.
  static const List<ItemType> _quickFilters = [
    ItemType.login,
    ItemType.card,
    ItemType.secureNote,
    ItemType.identity,
    ItemType.apiCredential,
    ItemType.wifi,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          const SizedBox(width: Space.sm),
          for (final type in _quickFilters) ...[
            FilterChip(
              avatar: Icon(type.icon, size: 15),
              label: Text(type.label),
              selected: selected == type.id,
              onSelected: (isOn) => onSelected(isOn ? type.id : null),
            ),
            const SizedBox(width: Space.sm),
          ],
        ],
      ),
    );
  }
}
