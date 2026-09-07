import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/autofill_bridge.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../data/autofill_mirror.dart';
import '../../../data/models/vault_settings.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'security_screen.dart';
import 'trash_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null || !vault.isUnlocked) return const SizedBox.shrink();

    final settings = vault.settings;
    final controller = ref.read(vaultControllerProvider.notifier);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.xl, Space.lg, Space.xl, Space.huge),
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),

          const SectionHeader('Locking'),
          SableCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Auto-lock'),
                  subtitle: Text(settings.autoLockDelay.label),
                  onTap: () => _chooseAutoLock(context, ref, settings),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.exit_to_app_rounded),
                  value: settings.lockWhenBackgrounded,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(lockWhenBackgrounded: value),
                  ),
                  title: const Text('Lock when I leave the app'),
                  subtitle: const Text(
                    'Locks immediately when Sablekey is no longer frontmost',
                  ),
                ),
              ],
            ),
          ),

          const SectionHeader('Privacy'),
          SableCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.screenshot_monitor_rounded),
                  value: settings.blockScreenshots,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(blockScreenshots: value),
                  ),
                  title: const Text('Block screenshots'),
                  subtitle: Text(
                    SecureScreen.supportsScreenshotBlocking
                        ? 'Also hides Sablekey in the app switcher'
                        : 'iOS cannot block screenshots; the app switcher '
                            'preview is blurred instead',
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off_rounded),
                  value: settings.concealUsernamesInList,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(concealUsernamesInList: value),
                  ),
                  title: const Text('Mask usernames in the list'),
                  subtitle: const Text('For reading the vault in public'),
                ),
                ListTile(
                  leading: const Icon(Icons.content_paste_off_rounded),
                  title: const Text('Clear clipboard'),
                  subtitle: Text(
                    settings.clipboardClearSeconds == 0
                        ? 'Never'
                        : 'After ${settings.clipboardClearSeconds} seconds',
                  ),
                  onTap: () => _chooseClipboard(context, ref, settings),
                ),
              ],
            ),
          ),

          const SectionHeader('Autofill'),
          SableCard(
            child: _AutofillSection(settings: settings),
          ),

          const SectionHeader('Vault'),
          SableCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sort_rounded),
                  title: const Text('Sort order'),
                  subtitle: Text(settings.sortOrder.label),
                  onTap: () => _chooseSort(context, ref, settings),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.star_outline_rounded),
                  value: settings.showFavouritesFirst,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(showFavouritesFirst: value),
                  ),
                  title: const Text('Favourites first'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.shield_outlined),
                  value: settings.warnOnWeakOnSave,
                  onChanged: (value) => controller.updateSettings(
                    settings.copyWith(warnOnWeakOnSave: value),
                  ),
                  title: const Text('Warn before saving a weak password'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Trash'),
                  subtitle: Text(
                    '${vault.trashedItems.length} in the trash · deleted after '
                    '${settings.trashRetentionDays} days',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrashScreen()),
                  ),
                ),
              ],
            ),
          ),

          const SectionHeader('Security'),
          SableCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Master password and biometrics'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SecurityScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup and import'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BackupScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About Sablekey'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xl),
          OutlinedButton.icon(
            onPressed: controller.lock,
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Lock vault now'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseAutoLock(
      BuildContext context, WidgetRef ref, VaultSettings settings) async {
    final choice = await showModalBottomSheet<AutoLockDelay>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final delay in AutoLockDelay.values)
              RadioListTile<AutoLockDelay>(
                value: delay,
                groupValue: settings.autoLockDelay,
                onChanged: (value) => Navigator.of(context).pop(value),
                title: Text(delay.label),
              ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref.read(vaultControllerProvider.notifier).updateSettings(
          settings.copyWith(autoLockSeconds: choice.seconds),
        );
  }

  Future<void> _chooseClipboard(
      BuildContext context, WidgetRef ref, VaultSettings settings) async {
    const options = {
      0: 'Never clear',
      10: 'After 10 seconds',
      30: 'After 30 seconds',
      60: 'After 1 minute',
      120: 'After 2 minutes',
    };
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in options.entries)
              RadioListTile<int>(
                value: entry.key,
                groupValue: settings.clipboardClearSeconds,
                onChanged: (value) => Navigator.of(context).pop(value),
                title: Text(entry.value),
              ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref.read(vaultControllerProvider.notifier).updateSettings(
          settings.copyWith(clipboardClearSeconds: choice),
        );
  }

  Future<void> _chooseSort(
      BuildContext context, WidgetRef ref, VaultSettings settings) async {
    final choice = await showModalBottomSheet<VaultSortOrder>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final order in VaultSortOrder.values)
              RadioListTile<VaultSortOrder>(
                value: order,
                groupValue: settings.sortOrder,
                onChanged: (value) => Navigator.of(context).pop(value),
                title: Text(order.label),
              ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref.read(vaultControllerProvider.notifier).updateSettings(
          settings.copyWith(sortOrder: choice),
        );
  }
}

/// Autofill setup, with the platform difference stated rather than hidden.
class _AutofillSection extends ConsumerStatefulWidget {
  const _AutofillSection({required this.settings});

  final VaultSettings settings;

  @override
  ConsumerState<_AutofillSection> createState() => _AutofillSectionState();
}

class _AutofillSectionState extends ConsumerState<_AutofillSection> {
  bool? _serviceEnabled;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final enabled = await AutofillBridge.isServiceEnabled();
    if (mounted) setState(() => _serviceEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).requireValue;
    final usesMirror = AutofillMirror.isSupported;
    final eligible = AutofillMirror.countEligible(vault.items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.password_rounded, size: 20),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                'Fill logins in other apps',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (_serviceEnabled == true)
              const Icon(Icons.check_circle_rounded,
                  color: SableColors.success, size: 20),
          ],
        ),
        const SizedBox(height: Space.md),

        if (usesMirror) ...[
          Text(
            'On iOS, an AutoFill extension cannot open your vault — it runs in '
            'its own process and cannot run Argon2id. Turning this on writes a '
            'separate copy of your logins, encrypted with a key held in the '
            'Secure Enclave behind Face ID or Touch ID.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.md),
          NoticeBanner(
            tone: NoticeTone.warning,
            icon: Icons.info_outline_rounded,
            message: '$eligible ${eligible == 1 ? 'login' : 'logins'} would be '
                'included. Notes, cards, documents and attachments never are. '
                'Anyone who can pass your device biometric could read that '
                'copy without your master password.',
          ),
          const SizedBox(height: Space.md),
          SwitchListTile(
            value: widget.settings.autofillEnabled,
            onChanged: (value) => ref
                .read(vaultControllerProvider.notifier)
                .updateSettings(
                    widget.settings.copyWith(autofillEnabled: value)),
            title: const Text('Enable iOS AutoFill'),
            contentPadding: EdgeInsets.zero,
          ),
          Text(
            'Then turn Sablekey on under Settings › General › AutoFill & '
            'Passwords.',
            style: theme.textTheme.bodySmall,
          ),
        ] else ...[
          Text(
            'Sablekey answers autofill requests without ever caching a '
            'credential: Android shows a locked entry, you unlock here, and '
            'the chosen login is passed straight to the app asking for it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          if (_serviceEnabled == false)
            FilledButton.icon(
              onPressed: () async {
                await AutofillBridge.openSettings();
                await Future<void>.delayed(const Duration(seconds: 1));
                await _check();
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Set Sablekey as autofill provider'),
            )
          else if (_serviceEnabled == true)
            Text(
              'Sablekey is your autofill provider.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: SableColors.success,
              ),
            ),
        ],
      ],
    );
  }
}
