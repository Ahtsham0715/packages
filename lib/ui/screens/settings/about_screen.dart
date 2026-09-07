import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/security_event.dart';
import '../../../state/services.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';

/// What the app is, how it protects things, and what it does not protect
/// against.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.lg, 0, Space.lg, Space.huge),
        children: [
          Row(
            children: [
              Image.asset(
                'assets/brand/sablekey_mark_512.png',
                width: 52,
                height: 52,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: Space.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sablekey', style: theme.textTheme.headlineSmall),
                  Text('Version 1.0.0', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),

          const SectionHeader('How your vault is protected'),
          SableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Fact(
                  label: 'Key derivation',
                  value: 'Argon2id, with parameters measured on this device',
                ),
                _Fact(
                  label: 'Encryption',
                  value: 'XChaCha20-Poly1305, one sealed envelope per record',
                ),
                _Fact(
                  label: 'Key hierarchy',
                  value: 'A random data key, wrapped by your password — so '
                      'changing it does not re-encrypt the vault',
                ),
                _Fact(
                  label: 'Network',
                  value: 'The Android build ships without the INTERNET '
                      'permission',
                ),
                _Fact(
                  label: 'Backups',
                  value: 'Android cloud backup and device transfer are both '
                      'disabled for this app',
                ),
              ],
            ),
          ),

          const SectionHeader('What this does not protect against'),
          SableCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No password manager protects everything, and one that says '
                  'otherwise is lying to you.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: Space.md),
                _Limit(
                  'A compromised device. Malware with root, or a keylogger, '
                  'can capture your master password as you type it.',
                ),
                _Limit(
                  'Forgetting your master password. There is no recovery, by '
                  'design — a reset path would be a way in for someone else.',
                ),
                _Limit(
                  'Screenshots on iOS. The system offers no way to block '
                  'them; only the app-switcher preview is hidden.',
                ),
                _Limit(
                  'A real breach check. That needs a network request, so the '
                  'health screen compares against a bundled list instead.',
                ),
              ],
            ),
          ),

          const SectionHeader('Security log'),
          const _SecurityLog(),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: Space.xxs),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _Limit extends StatelessWidget {
  const _Limit(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.remove_rounded, size: 14),
          ),
          const SizedBox(width: Space.md),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _SecurityLog extends ConsumerWidget {
  const _SecurityLog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return FutureBuilder<List<SecurityEvent>>(
      future: ref.read(repositoryProvider).loadEvents(limit: 60),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SableCard(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final events = snapshot.data!;
        if (events.isEmpty) {
          return SableCard(
            child: Text('Nothing logged yet.',
                style: theme.textTheme.bodySmall),
          );
        }

        return SableCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Encrypted alongside your entries, and readable only when the '
                'vault is open.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: Space.lg),
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(event.kind.label,
                                style: theme.textTheme.bodyMedium),
                            if (event.detail != null)
                              Text(event.detail!,
                                  style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Text(
                        _stamp(event.at),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _stamp(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(when.day)}/${two(when.month)} ${two(when.hour)}:'
        '${two(when.minute)}';
  }
}
