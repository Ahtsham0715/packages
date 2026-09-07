import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';

/// The lock screen.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  Timer? _lockoutTicker;
  bool _triedBiometrics = false;

  @override
  void initState() {
    super.initState();
    // Offer biometrics immediately: making the user tap a button first, when
    // that is the whole point of the feature, is friction for no security gain.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferBiometrics());
    _lockoutTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickLockout(),
    );
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tickLockout() {
    final state = ref.read(vaultControllerProvider).valueOrNull;
    if (state == null) return;
    // Rebuild once a second only while a lockout is counting down.
    if (state.lockoutUntil != null) setState(() {});
  }

  Future<void> _maybeOfferBiometrics() async {
    if (_triedBiometrics) return;
    final state = ref.read(vaultControllerProvider).valueOrNull;
    if (state == null || !state.biometricEnrolled || state.isLockedOut) {
      _focus.requestFocus();
      return;
    }
    _triedBiometrics = true;
    final ok =
        await ref.read(vaultControllerProvider.notifier).unlockWithBiometrics();
    if (!ok && mounted) _focus.requestFocus();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return;
    final ok =
        await ref.read(vaultControllerProvider.notifier).unlock(_password.text);
    if (!ok && mounted) {
      _password.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(vaultControllerProvider).valueOrNull;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final lockedOut = state.isLockedOut;
    final remaining = state.lockoutRemaining;

    return Scaffold(
      body: Stack(
        children: [
          const _EmberGlow(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      Space.xxl * 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 3),
                    Image.asset(
                      'assets/brand/sablekey_mark_512.png',
                      width: 64,
                      height: 64,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(height: Space.xl),
                    Text('Welcome back', style: theme.textTheme.displaySmall),
                    const SizedBox(height: Space.sm),
                    Text(
                      'Your vault is locked.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(flex: 2),

                    TextField(
                      controller: _password,
                      focusNode: _focus,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      enabled: !lockedOut && !state.busy,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Master password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),

                    if (state.errorMessage != null) ...[
                      const SizedBox(height: Space.lg),
                      NoticeBanner(
                        tone: NoticeTone.danger,
                        icon: Icons.error_outline_rounded,
                        message: state.errorMessage!,
                      ),
                    ],

                    if (lockedOut) ...[
                      const SizedBox(height: Space.lg),
                      NoticeBanner(
                        tone: NoticeTone.warning,
                        icon: Icons.hourglass_top_rounded,
                        message: 'Too many attempts. Try again in '
                            '${remaining.inSeconds + 1}s.',
                      ),
                    ] else if (state.failedAttempts >= 2) ...[
                      const SizedBox(height: Space.lg),
                      _AttemptWarning(
                        attempts: state.failedAttempts,
                        wipeAt: state.settings.panicWipeEnabled
                            ? state.settings.panicWipeAfterAttempts
                            : null,
                      ),
                    ],

                    const SizedBox(height: Space.xl),
                    FilledButton(
                      onPressed: lockedOut || state.busy ? null : _submit,
                      child: state.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : const Text('Unlock'),
                    ),

                    if (state.biometricEnrolled && !lockedOut) ...[
                      const SizedBox(height: Space.md),
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => ref
                                .read(vaultControllerProvider.notifier)
                                .unlockWithBiometrics(),
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Use biometrics'),
                      ),
                    ],

                    const Spacer(flex: 3),
                    Center(
                      child: Text(
                        'Offline. Nothing here is sent anywhere.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Counts down to a panic wipe, when one is armed.
///
/// Someone who enabled this months ago must be told *before* the last attempt,
/// not after their vault is gone.
class _AttemptWarning extends StatelessWidget {
  const _AttemptWarning({required this.attempts, required this.wipeAt});

  final int attempts;
  final int? wipeAt;

  @override
  Widget build(BuildContext context) {
    if (wipeAt == null) {
      return NoticeBanner(
        tone: NoticeTone.warning,
        icon: Icons.info_outline_rounded,
        message: '$attempts failed attempts. Delays between attempts are '
            'getting longer.',
      );
    }

    final left = wipeAt! - attempts;
    return NoticeBanner(
      tone: left <= 2 ? NoticeTone.danger : NoticeTone.warning,
      icon: Icons.warning_amber_rounded,
      message: left <= 0
          ? 'The next failed attempt will erase this vault.'
          : '$left more failed ${left == 1 ? 'attempt' : 'attempts'} will '
              'erase this vault permanently.',
    );
  }
}

/// The ember bloom from the app icon, behind the lock screen.
class _EmberGlow extends StatelessWidget {
  const _EmberGlow();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.5, -0.55),
            radius: 1.1,
            colors: [Color(0x24F2803C), Color(0x00000000)],
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}
