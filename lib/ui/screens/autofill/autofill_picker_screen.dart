import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/totp.dart';
import '../../../core/platform/autofill_bridge.dart';
import '../../../domain/models/item_type.dart';
import '../../../domain/models/vault_item.dart';
import '../../../data/models/security_event.dart';
import '../../../state/search_state.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';
import '../../widgets/vault_item_tile.dart';
import '../unlock/unlock_screen.dart';
import '../vault/item_editor_screen.dart';

/// The screen the Android autofill service launches.
///
/// This is a whole separate entry point into the app — see
/// `AutofillHostActivity`. The vault is unlocked here, in the app's own
/// process, and the chosen credential is handed straight back to the platform.
/// Nothing is cached, and the activity is marked `noHistory` so it cannot be
/// swiped back to afterwards.
class AutofillPickerScreen extends ConsumerStatefulWidget {
  const AutofillPickerScreen({super.key});

  @override
  ConsumerState<AutofillPickerScreen> createState() =>
      _AutofillPickerScreenState();
}

class _AutofillPickerScreenState extends ConsumerState<AutofillPickerScreen> {
  AutofillRequest? _request;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = await AutofillBridge.pendingRequest();
    if (!mounted) return;
    setState(() {
      _request = request;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final request = _request;
    if (request == null) {
      // Launched at the autofill route without a request — nothing sensible to
      // show, so hand control straight back.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => AutofillBridge.cancel());
      return const Scaffold(body: SizedBox.shrink());
    }

    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!vault.isUnlocked) {
      // The unlock screen is reused verbatim, so the autofill path cannot
      // develop its own weaker unlock over time.
      return const UnlockScreen();
    }

    return request.mode == AutofillMode.save
        ? _SaveRequestView(request: request)
        : _FillRequestView(request: request);
  }
}

class _FillRequestView extends ConsumerWidget {
  const _FillRequestView({required this.request});

  final AutofillRequest request;

  Future<void> _fill(WidgetRef ref, VaultItem item) async {
    String? totpCode;
    if (item.totp != null) {
      // Generated at the moment of filling; a code produced any earlier could
      // already have rolled over by the time the form is submitted.
      totpCode = (await Totp.generate(item.totp!)).value;
    }

    final cardFields = <String, String>{};
    if (item.type == ItemType.card) {
      for (final entry in {
        'number': 'number',
        'expiry': 'expiry',
        'cvv': 'cvv',
        'holder': 'holder',
      }.entries) {
        final value = item.fields[entry.value];
        if (value != null && value.isNotEmpty) cardFields[entry.key] = value;
      }
    }

    await ref.read(vaultControllerProvider.notifier).noteItemUsed(item);
    await ref.read(repositoryProvider).logEvent(
          SecurityEvent.autofillServed(target: request.displayTarget),
        );

    await AutofillBridge.respond(
      username: item.username,
      password: item.password,
      totpCode: totpCode,
      cardFields: cardFields,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target = request.target;
    final matches = ref.watch(autofillCandidatesProvider(target));
    final vault = ref.watch(vaultControllerProvider).requireValue;

    final others = vault.liveItems
        .where((item) => item.type.isAutofillable)
        .where((item) => !matches.any((match) => match.id == item.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill a login'),
        leading: IconButton(
          onPressed: AutofillBridge.cancel,
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, 0, Space.lg, Space.huge),
        children: [
          NoticeBanner(
            icon: Icons.arrow_outward_rounded,
            message: 'Filling into ${request.displayTarget}',
          ),

          if (matches.isEmpty && others.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Space.huge),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Nothing saved for this yet',
                message: 'Close this and add the login in Sablekey, then try '
                    'again.',
              ),
            ),

          if (matches.isNotEmpty) ...[
            const SectionHeader('Matches this site'),
            SableCard(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Column(
                children: [
                  for (final item in matches)
                    VaultItemTile(
                      item: item,
                      onTap: () => _fill(ref, item),
                    ),
                ],
              ),
            ),
          ],

          if (others.isNotEmpty) ...[
            SectionHeader(
              matches.isEmpty ? 'All logins' : 'Other logins',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Text(
                'These are not associated with ${request.displayTarget}. '
                'Filling one here will not add that association.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            SableCard(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Column(
                children: [
                  for (final item in others)
                    VaultItemTile(
                      item: item,
                      onTap: () => _fill(ref, item),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Offers to save credentials the user just typed into another app.
class _SaveRequestView extends ConsumerWidget {
  const _SaveRequestView({required this.request});

  final AutofillRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final target = request.displayTarget;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Save this login?'),
        leading: IconButton(
          onPressed: () => AutofillBridge.finishSave(saved: false),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sablekey can store the credentials you just entered in $target.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Space.xl),
            SableCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Username', style: theme.textTheme.labelSmall),
                  Text(
                    request.suggestedUsername ?? '—',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Space.lg),
                  Text('Password', style: theme.textTheme.labelSmall),
                  Text(
                    '•' * (request.suggestedPassword?.length ?? 0).clamp(8, 20),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => _save(context, ref),
              child: const Text('Save to vault'),
            ),
            const SizedBox(height: Space.md),
            OutlinedButton(
              onPressed: () => AutofillBridge.finishSave(saved: false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final item = VaultItem(
      id: '',
      type: ItemType.login,
      name: request.webDomain ?? request.appLabel ?? 'Saved login',
      fields: {
        if (request.suggestedUsername != null)
          'username': request.suggestedUsername!,
        if (request.suggestedPassword != null)
          'password': request.suggestedPassword!,
        if (request.webDomain != null) 'uri': request.webDomain!,
      },
      extraUris: [
        if (request.webDomain == null && request.packageName != null)
          'androidapp://${request.packageName}',
      ],
      createdAt: now,
      updatedAt: now,
      passwordUpdatedAt: now,
    );

    // Offer the editor rather than saving silently, so the entry gets a name
    // the user will recognise later instead of a bare domain.
    final reviewed = await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ItemEditorScreen(item: item)),
    );
    if (reviewed == null) {
      await AutofillBridge.finishSave(saved: true);
    }
  }
}
