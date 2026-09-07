import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/password_strength.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/strength_meter.dart';
import '../../widgets/surfaces.dart';

/// Master password, biometrics, panic wipe and the security log.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null || !vault.isUnlocked) return const SizedBox.shrink();

    final settings = vault.settings;
    final controller = ref.read(vaultControllerProvider.notifier);
    final header = ref.read(repositoryProvider).header;

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, 0, Space.lg, Space.huge),
        children: [
          const SectionHeader('Master password'),
          SableCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change master password'),
                  subtitle: const Text(
                    'Your entries are not re-encrypted — only the key that '
                    'wraps them is.',
                  ),
                  onTap: () => _changePassword(context, ref),
                ),
                if (header != null)
                  ListTile(
                    leading: const Icon(Icons.speed_rounded),
                    title: const Text('Key derivation'),
                    subtitle: Text(
                      '${header.kdfParams}\n'
                      'Chosen on this device so an attacker pays this cost per '
                      'guess.',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ),
          ),

          const SectionHeader('Biometric unlock'),
          SableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!vault.biometricAvailable)
                  Text(
                    'This device has no enrolled biometrics.',
                    style: theme.textTheme.bodySmall,
                  )
                else ...[
                  SwitchListTile(
                    value: vault.biometricEnrolled,
                    onChanged: (value) async {
                      if (value) {
                        final ok = await _confirmPassword(context, ref);
                        if (ok) await controller.enrolBiometrics();
                      } else {
                        await controller.removeBiometrics();
                      }
                    },
                    title: const Text('Unlock with biometrics'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Your vault key is stored in the platform keystore. The '
                    'biometric check is enforced by this app rather than by '
                    'the keystore itself, so on a rooted or jailbroken device '
                    'it could be bypassed. Your master password always works, '
                    'and is the stronger option.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),

          const SectionHeader('If someone else has my phone'),
          SableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sablekey already slows repeated guesses down, doubling the '
                  'delay after every few failures. A panic wipe goes further '
                  'and destroys the vault outright.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.md),
                ListTile(
                  leading: const Icon(Icons.local_fire_department_rounded),
                  title: const Text('Erase after failed attempts'),
                  subtitle: Text(
                    settings.panicWipeEnabled
                        ? 'After ${settings.panicWipeAfterAttempts} attempts'
                        : 'Off',
                  ),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _choosePanicWipe(context, ref),
                ),
                if (settings.panicWipeEnabled)
                  const NoticeBanner(
                    tone: NoticeTone.danger,
                    icon: Icons.warning_amber_rounded,
                    message: 'This is irreversible and there is no server copy. '
                        'Keep a current encrypted backup somewhere safe.',
                  ),
              ],
            ),
          ),

          const SectionHeader('Danger zone'),
          SableCard(
            accent: SableColors.danger,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Erase this vault', style: theme.textTheme.titleMedium),
                const SizedBox(height: Space.sm),
                Text(
                  'Deletes every entry, attachment and setting from this '
                  'device, and overwrites the freed pages.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.lg),
                OutlinedButton(
                  onPressed: () => _confirmErase(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SableColors.danger,
                    side: const BorderSide(color: SableColors.danger),
                  ),
                  child: const Text('Erase vault'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmPassword(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm your master password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Master password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      controller.dispose();
      return false;
    }

    final ok = await ref
        .read(repositoryProvider)
        .verifyMasterPassword(controller.text);
    controller.dispose();

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That password is not correct')),
      );
    }
    return ok;
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _ChangePasswordScreen()),
    );
  }

  Future<void> _choosePanicWipe(BuildContext context, WidgetRef ref) async {
    final vault = ref.read(vaultControllerProvider).requireValue;
    const options = {0: 'Off', 5: 'After 5 attempts', 10: 'After 10 attempts'};

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
                groupValue: vault.settings.panicWipeAfterAttempts,
                onChanged: (value) => Navigator.of(context).pop(value),
                title: Text(entry.value),
              ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    // Turning this on is a decision people regret; make them type the word.
    if (choice > 0) {
      final typed = await _typeToConfirm(
        context,
        title: 'Enable panic wipe',
        body: 'After $choice failed unlock attempts, this vault will be '
            'erased with no way to recover it. Make sure you have an '
            'encrypted backup first.',
        word: 'ERASE',
      );
      if (!typed) return;
    }

    await ref.read(vaultControllerProvider.notifier).updateSettings(
          vault.settings.copyWith(panicWipeAfterAttempts: choice),
        );
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref) async {
    final typed = await _typeToConfirm(
      context,
      title: 'Erase this vault?',
      body: 'Everything stored in Sablekey on this device will be destroyed. '
          'There is no cloud copy and no recovery.',
      word: 'ERASE',
    );
    if (!typed || !context.mounted) return;
    await ref.read(vaultControllerProvider.notifier).eraseVault();
  }
}

/// A confirmation that cannot be dismissed by muscle memory.
Future<bool> _typeToConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String word,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(body),
            const SizedBox(height: Space.lg),
            Text('Type $word to continue.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Space.sm),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'ERASE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: controller.text.trim().toUpperCase() == word
                ? () => Navigator.of(context).pop(true)
                : null,
            style: FilledButton.styleFrom(backgroundColor: SableColors.danger),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result ?? false;
}

class _ChangePasswordScreen extends ConsumerStatefulWidget {
  const _ChangePasswordScreen();

  @override
  ConsumerState<_ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<_ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  PasswordStrength _strength = PasswordStrength.empty;
  bool _busy = false;

  static const int _minimumBits = 60;

  @override
  void initState() {
    super.initState();
    _next.addListener(() {
      setState(() =>
          _strength = ref.read(estimatorProvider).evaluate(_next.text));
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final ok = await ref
        .read(vaultControllerProvider.notifier)
        .changeMasterPassword(
          currentPassword: _current.text,
          newPassword: _next.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Master password changed. Biometric unlock and autofill have been '
            'switched off — set them up again if you want them.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    final valid = _next.text == _confirm.text &&
        _next.text.isNotEmpty &&
        _strength.entropyBits >= _minimumBits;

    return Scaffold(
      appBar: AppBar(title: const Text('Change master password')),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: [
          Text(
            'Your entries stay exactly as they are. Only the 32-byte key that '
            'wraps them is re-encrypted, so this is instant even on a large '
            'vault.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),
          TextField(
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: Space.lg),
          StrengthMeter(strength: _strength),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _confirm,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              errorText: _confirm.text.isNotEmpty && _confirm.text != _next.text
                  ? 'These do not match'
                  : null,
            ),
          ),
          if (vault?.errorMessage != null) ...[
            const SizedBox(height: Space.lg),
            NoticeBanner(
              tone: NoticeTone.danger,
              icon: Icons.error_outline_rounded,
              message: vault!.errorMessage!,
            ),
          ],
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: valid && !_busy ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text('Change password'),
          ),
        ],
      ),
    );
  }
}
