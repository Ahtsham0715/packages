import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/password_strength.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/strength_meter.dart';
import '../../widgets/surfaces.dart';

/// First run: explain what the app is, then take a master password.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    setState(() => _page = 1);
    _controller.animateToPage(1, duration: Motion.standard, curve: Motion.enter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _IntroPage(onContinue: _next),
            const _CreateVaultPage(),
          ],
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          Image.asset(
            'assets/brand/sablekey_mark_512.png',
            width: 84,
            height: 84,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(height: Space.xl),
          Text('Sablekey', style: theme.textTheme.displaySmall),
          const SizedBox(height: Space.md),
          const EmberRule(),
          const SizedBox(height: Space.lg),
          Text(
            'A password manager that cannot phone home.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          const _Point(
            icon: Icons.cloud_off_rounded,
            title: 'No account, no sync, no servers',
            body: 'The Android build ships without the permission needed to '
                'open a network connection at all.',
          ),
          const _Point(
            icon: Icons.enhanced_encryption_rounded,
            title: 'Encrypted before it is stored',
            body: 'Argon2id derives your key; every record is sealed with '
                'XChaCha20-Poly1305 before the database sees it.',
          ),
          const _Point(
            icon: Icons.key_off_rounded,
            title: 'Only you can open it',
            body: 'There is no recovery path. Nobody can reset your master '
                'password, including you.',
          ),
          const Spacer(flex: 2),
          FilledButton(
            onPressed: onContinue,
            child: const Text('Create my vault'),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: SableColors.ember),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: Space.xxs),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateVaultPage extends ConsumerStatefulWidget {
  const _CreateVaultPage();

  @override
  ConsumerState<_CreateVaultPage> createState() => _CreateVaultPageState();
}

class _CreateVaultPageState extends ConsumerState<_CreateVaultPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _acknowledged = false;
  PasswordStrength _strength = PasswordStrength.empty;

  /// Below this the vault is not worth the cryptography protecting it.
  static const int _minimumBits = 60;

  @override
  void initState() {
    super.initState();
    _password.addListener(_evaluate);
  }

  @override
  void dispose() {
    _password
      ..removeListener(_evaluate)
      ..dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _evaluate() {
    final estimator = ref.read(estimatorProvider);
    setState(() => _strength = estimator.evaluate(_password.text));
  }

  bool get _canSubmit =>
      _acknowledged &&
      _password.text.isNotEmpty &&
      _password.text == _confirm.text &&
      _strength.entropyBits >= _minimumBits;

  Future<void> _create() async {
    await ref
        .read(vaultControllerProvider.notifier)
        .createVault(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(vaultControllerProvider).valueOrNull;
    final busy = state?.busy ?? false;
    final mismatch =
        _confirm.text.isNotEmpty && _confirm.text != _password.text;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.xl),
          Text('Choose a master password', style: theme.textTheme.headlineMedium),
          const SizedBox(height: Space.md),
          Text(
            'This one password protects everything else. Make it long — a '
            'phrase of several unrelated words beats a short string of symbols, '
            'and is far easier to remember.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xl),

          TextField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Master password',
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? 'Show' : 'Hide',
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          StrengthMeter(strength: _strength),

          if (_strength.entropyBits > 0 &&
              _strength.entropyBits < _minimumBits) ...[
            const SizedBox(height: Space.md),
            NoticeBanner(
              tone: NoticeTone.warning,
              icon: Icons.shield_outlined,
              message: 'A master password needs at least $_minimumBits bits of '
                  'strength. Adding words is the fastest way to get there.',
            ),
          ],
          if (_strength.warnings.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            StrengthAdvice(strength: _strength),
          ],

          const SizedBox(height: Space.lg),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Confirm master password',
              errorText: mismatch ? 'These do not match' : null,
            ),
          ),

          const SizedBox(height: Space.xl),
          // Deliberately a checkbox rather than fine print. There is genuinely
          // no recovery, and someone discovering that six months later has lost
          // everything.
          InkWell(
            onTap: () => setState(() => _acknowledged = !_acknowledged),
            borderRadius: BorderRadius.circular(Radii.md),
            child: Padding(
              padding: const EdgeInsets.all(Space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acknowledged,
                    onChanged: (value) =>
                        setState(() => _acknowledged = value ?? false),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'I understand that if I forget this password, my vault '
                      'cannot be recovered by anyone.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (state?.errorMessage != null) ...[
            const SizedBox(height: Space.lg),
            NoticeBanner(
              tone: NoticeTone.danger,
              icon: Icons.error_outline_rounded,
              message: state!.errorMessage!,
            ),
          ],

          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: _canSubmit && !busy ? _create : null,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text('Create vault'),
          ),
          const SizedBox(height: Space.md),
          Text(
            busy
                ? 'Measuring how hard this device can make an attacker work…'
                : 'Sablekey times Argon2id on this device and picks the '
                    'strongest settings it can run in about a second.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}
