import 'package:flutter/foundation.dart';

import '../models/field_spec.dart';
import '../models/item_type.dart';
import '../models/vault_item.dart';
import 'password_strength.dart';

/// The kinds of problem the audit reports, worst first.
enum HealthIssue {
  compromised(
    title: 'Known password',
    detail: 'Appears in the bundled list of the most-guessed passwords. '
        'Attackers try these first.',
    weight: 40,
  ),
  weak(
    title: 'Weak password',
    detail: 'Short or predictable enough to fall to an offline attack.',
    weight: 25,
  ),
  reused(
    title: 'Reused password',
    detail: 'Used on more than one entry. One breach then opens all of them.',
    weight: 20,
  ),
  stale(
    title: 'Old password',
    detail: 'Unchanged for a long time. Worth rotating for anything that '
        'matters.',
    weight: 6,
  ),
  missingTotp(
    title: 'No two-factor code',
    detail: 'This login has no second factor stored, and the site may support '
        'one.',
    weight: 5,
  ),
  insecureUri(
    title: 'Unencrypted address',
    detail: 'The stored address uses http://, so credentials would travel in '
        'the clear.',
    weight: 8,
  ),
  expiring(
    title: 'Expiring soon',
    detail: 'This document or card expires within 60 days.',
    weight: 4,
  ),
  expired(
    title: 'Expired',
    detail: 'The expiry date on this entry has passed.',
    weight: 6,
  ),
  emptyPassword(
    title: 'No password saved',
    detail: 'This entry has a password field, but it is empty.',
    weight: 3,
  );

  const HealthIssue({
    required this.title,
    required this.detail,
    required this.weight,
  });

  final String title;
  final String detail;

  /// How much one instance costs the overall score.
  final int weight;
}

/// One item and everything wrong with it.
@immutable
class ItemHealth {
  const ItemHealth({
    required this.item,
    required this.issues,
    required this.strength,
    this.reuseCount = 0,
  });

  final VaultItem item;
  final Set<HealthIssue> issues;
  final PasswordStrength strength;

  /// How many entries share this password, including this one.
  final int reuseCount;

  bool get isHealthy => issues.isEmpty;

  /// The issue that should be shown as the headline for this item.
  HealthIssue? get worst {
    HealthIssue? worst;
    for (final issue in issues) {
      if (worst == null || issue.weight > worst.weight) worst = issue;
    }
    return worst;
  }
}

/// The whole-vault report.
@immutable
class VaultHealthReport {
  const VaultHealthReport({
    required this.results,
    required this.score,
    required this.auditedCount,
    required this.generatedAt,
  });

  static const VaultHealthReport empty = VaultHealthReport(
    results: [],
    score: 100,
    auditedCount: 0,
    generatedAt: null,
  );

  final List<ItemHealth> results;

  /// 0-100. Shown as a single number because that is the only form most people
  /// will act on, with the itemised list one tap away.
  final int score;

  /// How many items carried an auditable secret at all.
  final int auditedCount;

  final DateTime? generatedAt;

  List<ItemHealth> withIssue(HealthIssue issue) =>
      results.where((r) => r.issues.contains(issue)).toList(growable: false);

  int countOf(HealthIssue issue) =>
      results.where((r) => r.issues.contains(issue)).length;

  Set<String> idsWith(HealthIssue issue) =>
      withIssue(issue).map((r) => r.item.id).toSet();

  List<ItemHealth> get problems {
    final list = results.where((r) => !r.isHealthy).toList()
      ..sort((a, b) {
        final aw = a.worst?.weight ?? 0;
        final bw = b.worst?.weight ?? 0;
        if (aw != bw) return bw.compareTo(aw);
        return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
      });
    return list;
  }

  String get verdict {
    if (auditedCount == 0) return 'Nothing to audit yet';
    if (score >= 90) return 'Your vault is in good shape';
    if (score >= 70) return 'A few things worth fixing';
    if (score >= 40) return 'Several passwords need attention';
    return 'Your vault needs work';
  }
}

/// Scores every stored secret and explains what is wrong with it.
///
/// Runs entirely locally against decrypted items. It cannot tell you whether a
/// password appeared in a real breach — that needs a network lookup this app
/// deliberately cannot perform — so "compromised" here means "matched the
/// bundled list of the most-guessed passwords", and the UI says exactly that.
class HealthAuditor {
  HealthAuditor({
    required PasswordStrengthEstimator estimator,
    this.staleAfter = const Duration(days: 365),
    this.expiryWarning = const Duration(days: 60),
  }) : _estimator = estimator;

  final PasswordStrengthEstimator _estimator;
  final Duration staleAfter;
  final Duration expiryWarning;

  VaultHealthReport audit(List<VaultItem> items, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final live = items.where((item) => !item.isDeleted).toList(growable: false);

    // Count password usage first, so the reuse verdict is available while
    // scoring each item.
    final usage = <String, int>{};
    for (final item in live) {
      for (final secret in item.auditedSecrets) {
        usage.update(secret, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    final results = <ItemHealth>[];
    var auditedCount = 0;
    var penalty = 0;

    for (final item in live) {
      final issues = <HealthIssue>{};
      var strength = PasswordStrength.empty;
      var reuseCount = 0;

      final passwordKey = item.type.passwordKey;
      final password = passwordKey == null ? null : item.fields[passwordKey];

      if (passwordKey != null) {
        if (password == null || password.isEmpty) {
          issues.add(HealthIssue.emptyPassword);
        } else {
          auditedCount++;
          strength = _estimator.evaluate(password);
          reuseCount = usage[password] ?? 1;

          if (strength.isCommon) {
            issues.add(HealthIssue.compromised);
          } else if (strength.score <= 1) {
            issues.add(HealthIssue.weak);
          }
          if (reuseCount > 1) issues.add(HealthIssue.reused);

          final changedAt = item.passwordUpdatedAt ?? item.createdAt;
          if (at.difference(changedAt) > staleAfter) {
            issues.add(HealthIssue.stale);
          }
        }
      }

      if (item.type == ItemType.login &&
          item.totp == null &&
          (password?.isNotEmpty ?? false)) {
        issues.add(HealthIssue.missingTotp);
      }

      for (final uri in item.allUris) {
        if (uri.toLowerCase().startsWith('http://')) {
          issues.add(HealthIssue.insecureUri);
          break;
        }
      }

      final expiry = _expiryOf(item);
      if (expiry != null) {
        if (expiry.isBefore(at)) {
          issues.add(HealthIssue.expired);
        } else if (expiry.difference(at) <= expiryWarning) {
          issues.add(HealthIssue.expiring);
        }
      }

      for (final issue in issues) {
        penalty += issue.weight;
      }

      results.add(ItemHealth(
        item: item,
        issues: issues,
        strength: strength,
        reuseCount: reuseCount,
      ));
    }

    return VaultHealthReport(
      results: results,
      score: _scoreFrom(penalty, live.length),
      auditedCount: auditedCount,
      generatedAt: at,
    );
  }

  /// Turns the raw penalty into 0-100, scaled by vault size.
  ///
  /// Without the scaling, one bad password in a vault of three would score the
  /// same as one bad password in a vault of three hundred, and the number would
  /// stop meaning anything as the vault grew.
  static int _scoreFrom(int penalty, int itemCount) {
    if (itemCount == 0) return 100;
    final perItem = penalty / itemCount;
    // A vault where every item carries a mid-weight issue lands near zero.
    final score = 100 - (perItem * 4.5).round();
    return score.clamp(0, 100);
  }

  /// Finds an expiry date on the item, whatever the type calls it.
  static DateTime? _expiryOf(VaultItem item) {
    for (final spec in item.type.fields) {
      if (spec.kind != FieldKind.date && spec.kind != FieldKind.expiry) continue;
      if (!spec.key.toLowerCase().contains('expir')) continue;
      final raw = item.fields[spec.key];
      if (raw == null || raw.trim().isEmpty) continue;
      final parsed = parseExpiry(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Parses the date formats people actually type: `MM/YY`, `MM/YYYY`,
  /// `YYYY-MM-DD`, `DD/MM/YYYY`.
  ///
  /// Returns the *end* of the month for month-precision values, since a card
  /// marked 03/27 is valid through the whole of March.
  @visibleForTesting
  static DateTime? parseExpiry(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final iso = RegExp(r'^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$').firstMatch(value);
    if (iso != null) {
      final year = int.parse(iso.group(1)!);
      final month = int.parse(iso.group(2)!);
      final day = iso.group(3);
      if (month < 1 || month > 12) return null;
      return day == null
          ? _endOfMonth(year, month)
          : DateTime(year, month, int.parse(day));
    }

    final slash =
        RegExp(r'^(\d{1,4})\s*[/.\-]\s*(\d{1,4})(?:\s*[/.\-]\s*(\d{1,4}))?$')
            .firstMatch(value);
    if (slash != null) {
      final a = int.parse(slash.group(1)!);
      final b = int.parse(slash.group(2)!);
      final c = slash.group(3);

      if (c == null) {
        // MM/YY or MM/YYYY.
        if (a < 1 || a > 12) return null;
        return _endOfMonth(_expandYear(b), a);
      }
      // DD/MM/YYYY, the common non-US form. A day above 12 disambiguates.
      final day = a;
      final month = b;
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      return DateTime(_expandYear(int.parse(c)), month, day);
    }
    return null;
  }

  static int _expandYear(int year) {
    if (year >= 1000) return year;
    // Two-digit years on cards and documents are always this century.
    return 2000 + year;
  }

  static DateTime _endOfMonth(int year, int month) =>
      DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
}
