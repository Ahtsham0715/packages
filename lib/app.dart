import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/auto_lock_service.dart';
import 'state/vault_controller.dart';
import 'ui/screens/autofill/autofill_picker_screen.dart';
import 'ui/screens/onboarding/welcome_screen.dart';
import 'ui/screens/unlock/unlock_screen.dart';
import 'ui/screens/vault/vault_home_screen.dart';
import 'ui/theme/sable_theme.dart';
import 'ui/theme/tokens.dart';

class SablekeyApp extends ConsumerWidget {
  const SablekeyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The autofill flow launches the same Flutter app at a different route, so
    // the entry point is decided once here rather than by a router that would
    // have to be told about it everywhere.
    final isAutofill =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName ==
            '/autofill';

    return MaterialApp(
      title: 'Sablekey',
      debugShowCheckedModeBanner: false,
      theme: SableTheme.light(),
      darkTheme: SableTheme.dark(),
      // Dark is the designed-for mode; the light theme exists for people who
      // need it, not as an equal default.
      themeMode: ThemeMode.dark,
      home: isAutofill ? const AutofillPickerScreen() : const _AppGate(),
      builder: (context, child) {
        // Cap text scaling. Beyond about 1.3 the generated-password monospace
        // rows wrap mid-secret, which makes a password unreadable rather than
        // merely large.
        final scale = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Chooses the screen for the current vault state, and feeds user activity to
/// the auto-lock timer.
class _AppGate extends ConsumerWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultControllerProvider);

    return ActivityDetector(
      onActivity: () =>
          ref.read(vaultControllerProvider.notifier).noteActivity(),
      child: AnimatedSwitcher(
        duration: Motion.standard,
        switchInCurve: Motion.enter,
        child: vault.when(
          loading: () => const _SplashScreen(),
          error: (error, _) => _StartupFailure(error: error),
          data: (state) => switch (state.status) {
            VaultStatus.loading => const _SplashScreen(),
            VaultStatus.needsSetup => const WelcomeScreen(),
            VaultStatus.locked => const UnlockScreen(),
            VaultStatus.unlocked => const VaultHomeScreen(),
          },
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// Shown when the database itself could not be opened.
///
/// Deliberately does not offer a "reset" button. The most likely cause is a
/// storage permission or an OS upgrade quirk, and a one-tap wipe next to that
/// message is how someone loses a vault they could have recovered.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 40, color: SableColors.warning),
            const SizedBox(height: Space.lg),
            Text('Sablekey could not open its storage',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: Space.md),
            Text(
              'Your vault has not been changed. Restarting the app usually '
              'resolves this. If it persists, restore from your most recent '
              'encrypted backup on a fresh install.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.xl),
            SelectableText('$error', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
