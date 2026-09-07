import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/health_auditor.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';
import '../../widgets/vault_item_tile.dart';
import '../vault/item_detail_screen.dart';

/// The vault health report.
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null || !vault.isUnlocked) {
      return const SizedBox.shrink();
    }

    final report = vault.health;
    final problems = report.problems;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.xl, Space.lg, Space.xl, Space.huge),
        children: [
          Text('Health', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 2),
          Text(
            'Checked on this device against the bundled lists. No password '
            'leaves the phone to be checked.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),

          _ScoreCard(report: report),

          if (report.auditedCount == 0) ...[
            const SizedBox(height: Space.xxl),
            const EmptyState(
              icon: Icons.health_and_safety_outlined,
              title: 'Nothing to audit yet',
              message: 'Add a login or two and this page will tell you which '
                  'passwords are weak, reused or overdue for a change.',
            ),
          ] else if (problems.isEmpty) ...[
            const SizedBox(height: Space.xl),
            const NoticeBanner(
              tone: NoticeTone.success,
              icon: Icons.verified_rounded,
              message: 'Nothing needs attention. Every stored password is '
                  'strong, unique and recent.',
            ),
          ] else ...[
            for (final issue in _issuesInReport(report)) ...[
              SectionHeader(
                '${issue.title} · ${report.countOf(issue)}',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Text(issue.detail, style: theme.textTheme.bodySmall),
              ),
              SableCard(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Column(
                  children: [
                    for (final result in report.withIssue(issue))
                      VaultItemTile(
                        item: result.item,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ItemDetailScreen(itemId: result.item.id),
                          ),
                        ),
                        trailing: issue == HealthIssue.reused
                            ? _ReuseBadge(count: result.reuseCount)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ],

          const SizedBox(height: Space.xxl),
          const NoticeBanner(
            icon: Icons.info_outline_rounded,
            message: 'Sablekey cannot check a password against a real breach '
                'database — that would require sending something about it to a '
                'server. "Known password" here means it matched the bundled '
                'list of the most-guessed passwords.',
          ),
        ],
      ),
    );
  }

  /// Only the issue categories that actually occur, worst first.
  static List<HealthIssue> _issuesInReport(VaultHealthReport report) {
    final present = HealthIssue.values
        .where((issue) => report.countOf(issue) > 0)
        .toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    return present;
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final VaultHealthReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = _colourFor(report.score);

    return SableCard(
      accent: colour,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: report.score / 100),
                  duration: Motion.slow,
                  curve: Motion.enter,
                  builder: (context, value, _) => SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: theme.colorScheme.outlineVariant,
                      valueColor: AlwaysStoppedAnimation(colour),
                    ),
                  ),
                ),
                Text(
                  '${report.score}',
                  style: theme.textTheme.headlineSmall?.copyWith(color: colour),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.verdict, style: theme.textTheme.titleMedium),
                const SizedBox(height: Space.xs),
                Text(
                  '${report.auditedCount} '
                  '${report.auditedCount == 1 ? 'password' : 'passwords'} '
                  'checked',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _colourFor(int score) {
    if (score >= 90) return SableColors.strengthScale[4];
    if (score >= 70) return SableColors.strengthScale[3];
    if (score >= 40) return SableColors.strengthScale[2];
    if (score >= 20) return SableColors.strengthScale[1];
    return SableColors.strengthScale[0];
  }
}

class _ReuseBadge extends StatelessWidget {
  const _ReuseBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xxs,
      ),
      decoration: BoxDecoration(
        color: SableColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        '×$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: SableColors.warning,
        ),
      ),
    );
  }
}
