import 'package:flutter/foundation.dart';

import '../models/field_spec.dart';
import '../models/item_type.dart';
import '../models/vault_item.dart';

/// A filter parsed out of a `key:value` term in the query.
@immutable
class SearchFilter {
  const SearchFilter(this.key, this.value);
  final String key;
  final String value;
}

/// A query broken into its structured filters and its free-text terms.
///
/// Sablekey's search bar takes operators the way a mail client does:
///
/// ```
///   github                       plain text, fuzzy-matched
///   "acme corp"                  quoted phrase, matched verbatim
///   type:login bank              only logins, matching "bank"
///   tag:work has:totp            work items that carry a 2FA code
///   url:example.com              matched against the item's URIs
///   user:alice@                  matched against username/email fields
///   in:trash                     search deleted items instead
///   is:favourite  is:weak        saved filters from the audit
/// ```
@immutable
class SearchQuery {
  const SearchQuery({
    required this.terms,
    required this.phrases,
    required this.filters,
    required this.raw,
  });

  factory SearchQuery.parse(String raw) {
    final terms = <String>[];
    final phrases = <String>[];
    final filters = <SearchFilter>[];

    for (final token in _tokenize(raw)) {
      if (token.isQuoted) {
        phrases.add(token.text.toLowerCase());
        continue;
      }
      final colon = token.text.indexOf(':');
      if (colon > 0 && colon < token.text.length - 1) {
        final key = token.text.substring(0, colon).toLowerCase();
        final value = token.text.substring(colon + 1).toLowerCase();
        if (_knownFilterKeys.contains(key)) {
          filters.add(SearchFilter(key, value));
          continue;
        }
      }
      if (token.text.isNotEmpty) terms.add(token.text.toLowerCase());
    }

    return SearchQuery(
      terms: terms,
      phrases: phrases,
      filters: filters,
      raw: raw,
    );
  }

  static const Set<String> _knownFilterKeys = {
    'type', 'tag', 'folder', 'in', 'is', 'has',
    'name', 'user', 'username', 'url', 'uri', 'site', 'note', 'notes',
  };

  final List<String> terms;
  final List<String> phrases;
  final List<SearchFilter> filters;
  final String raw;

  bool get isEmpty => terms.isEmpty && phrases.isEmpty && filters.isEmpty;

  /// Whether the query explicitly asks for deleted items.
  bool get wantsTrash =>
      filters.any((f) => f.key == 'in' && (f.value == 'trash' || f.value == 'bin'));

  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    void flush({required bool quoted}) {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) tokens.add(_Token(text, quoted));
      buffer.clear();
    }

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') {
        flush(quoted: inQuotes);
        inQuotes = !inQuotes;
        continue;
      }
      if (char == ' ' && !inQuotes) {
        flush(quoted: false);
        continue;
      }
      buffer.write(char);
    }
    flush(quoted: inQuotes);
    return tokens;
  }
}

@immutable
class _Token {
  const _Token(this.text, this.isQuoted);
  final String text;
  final bool isQuoted;
}

/// An item that matched, with the score that ordered it.
@immutable
class SearchHit {
  const SearchHit({required this.item, required this.score});
  final VaultItem item;
  final double score;
}

/// Context the engine needs for audit-backed filters like `is:weak`.
@immutable
class SearchContext {
  const SearchContext({
    this.weakItemIds = const {},
    this.reusedItemIds = const {},
    this.staleItemIds = const {},
  });

  final Set<String> weakItemIds;
  final Set<String> reusedItemIds;
  final Set<String> staleItemIds;
}

/// Ranked, in-memory search over the unlocked vault.
///
/// Search runs against decrypted items held in memory rather than against the
/// database, which is what makes fuzzy matching and operators possible at all:
/// the stored rows are opaque ciphertext, and an index built over them would
/// either leak what it indexed or be useless.
///
/// Secrets are deliberately not searchable. Letting a query match a password
/// would turn the result list into a confirmation oracle for anyone holding an
/// unlocked phone.
class SearchEngine {
  const SearchEngine();

  List<SearchHit> search(
    List<VaultItem> items,
    SearchQuery query, {
    SearchContext context = const SearchContext(),
    int limit = 500,
  }) {
    final wantsTrash = query.wantsTrash;
    final hits = <SearchHit>[];

    for (final item in items) {
      if (item.isDeleted != wantsTrash) continue;
      if (!_passesFilters(item, query, context)) continue;

      final score = query.terms.isEmpty && query.phrases.isEmpty
          ? _baseScore(item)
          : _scoreText(item, query);
      if (score <= 0) continue;
      hits.add(SearchHit(item: item, score: score));
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  bool _passesFilters(
      VaultItem item, SearchQuery query, SearchContext context) {
    for (final filter in query.filters) {
      switch (filter.key) {
        case 'type':
          final matches = ItemType.values.any((t) =>
              (t.id == filter.value ||
                  t.label.toLowerCase().startsWith(filter.value)) &&
              t == item.type);
          if (!matches) return false;

        case 'tag':
          if (!item.tags.any((t) => t.toLowerCase() == filter.value)) {
            return false;
          }

        case 'folder':
          if ((item.folderId ?? '').toLowerCase() != filter.value) return false;

        case 'in':
          // Handled by the trash check in [search]; anything else is unknown.
          if (filter.value != 'trash' && filter.value != 'bin') return false;

        case 'is':
          switch (filter.value) {
            case 'favourite':
            case 'favorite':
            case 'fav':
              if (!item.favourite) return false;
            case 'weak':
              if (!context.weakItemIds.contains(item.id)) return false;
            case 'reused':
              if (!context.reusedItemIds.contains(item.id)) return false;
            case 'old':
            case 'stale':
              if (!context.staleItemIds.contains(item.id)) return false;
            default:
              return false;
          }

        case 'has':
          switch (filter.value) {
            case 'totp':
            case '2fa':
              if (item.totp == null) return false;
            case 'attachment':
            case 'file':
              if (item.attachmentIds.isEmpty) return false;
            case 'note':
              if (item.notes.trim().isEmpty) return false;
            case 'url':
            case 'uri':
              if (item.allUris.isEmpty) return false;
            default:
              return false;
          }

        case 'name':
          if (!item.name.toLowerCase().contains(filter.value)) return false;

        case 'user':
        case 'username':
          if (!(item.username ?? '').toLowerCase().contains(filter.value)) {
            return false;
          }

        case 'url':
        case 'uri':
        case 'site':
          if (!item.allUris
              .any((u) => u.toLowerCase().contains(filter.value))) {
            return false;
          }

        case 'note':
        case 'notes':
          if (!item.notes.toLowerCase().contains(filter.value)) return false;
      }
    }
    return true;
  }

  /// Ordering when the query is filters-only: favourites, then recent use.
  double _baseScore(VaultItem item) {
    var score = 1.0;
    if (item.favourite) score += 5;
    score += _recencyBoost(item);
    return score;
  }

  double _scoreText(VaultItem item, SearchQuery query) {
    final name = item.name.toLowerCase();
    final haystack = item.searchableText.toLowerCase();
    var total = 0.0;

    for (final phrase in query.phrases) {
      if (!haystack.contains(phrase)) return 0;
      total += name.contains(phrase) ? 60 : 25;
    }

    for (final term in query.terms) {
      final termScore = _scoreTerm(term, name, haystack, item);
      // Every bare term must match something. Anything else turns a two-word
      // query into a broader result set than one word, which is never what
      // someone typing a second word wants.
      if (termScore <= 0) return 0;
      total += termScore;
    }

    if (item.favourite) total += 8;
    total += _recencyBoost(item);
    return total;
  }

  double _scoreTerm(
      String term, String name, String haystack, VaultItem item) {
    if (name == term) return 120;
    if (name.startsWith(term)) return 90;

    // A match at a word boundary in the name beats one in the middle.
    for (final word in name.split(RegExp(r'[\s._\-/]+'))) {
      if (word.startsWith(term)) return 70;
    }
    if (name.contains(term)) return 50;

    // Domains: "gh" should find "github.com", and "github.com" should be found
    // by "github".
    for (final uri in item.allUris) {
      final host = _hostOf(uri);
      if (host.startsWith(term)) return 55;
      if (host.contains(term)) return 35;
    }

    if ((item.username ?? '').toLowerCase().contains(term)) return 30;
    if (haystack.contains(term)) return 20;

    // Last resort: initials and skipped letters, so "gth" finds "GitHub".
    final fuzzy = _subsequenceScore(term, name);
    return fuzzy;
  }

  double _recencyBoost(VaultItem item) {
    final used = item.lastUsedAt;
    if (used == null) return 0;
    final days = DateTime.now().difference(used).inDays;
    if (days <= 1) return 12;
    if (days <= 7) return 8;
    if (days <= 30) return 4;
    return 1;
  }

  /// Scores [term] as a subsequence of [target], rewarding matches that land
  /// close together and at word starts.
  static double _subsequenceScore(String term, String target) {
    if (term.isEmpty || target.isEmpty) return 0;
    var termIndex = 0;
    var lastMatch = -1;
    var score = 0.0;

    for (var i = 0; i < target.length && termIndex < term.length; i++) {
      if (target[i] != term[termIndex]) continue;
      final atWordStart =
          i == 0 || RegExp(r'[\s._\-/]').hasMatch(target[i - 1]);
      score += atWordStart ? 4 : 1;
      if (lastMatch >= 0 && i == lastMatch + 1) score += 2; // contiguous
      lastMatch = i;
      termIndex++;
    }

    if (termIndex < term.length) return 0; // not a subsequence at all
    // Normalise so a short match inside a long name does not outrank a real
    // substring hit.
    return (score / target.length) * 12;
  }

  static String _hostOf(String uri) {
    var value = uri.trim().toLowerCase();
    final scheme = value.indexOf('://');
    if (scheme >= 0) value = value.substring(scheme + 3);
    final slash = value.indexOf('/');
    if (slash >= 0) value = value.substring(0, slash);
    final at = value.indexOf('@');
    if (at >= 0) value = value.substring(at + 1);
    final colon = value.indexOf(':');
    if (colon >= 0) value = value.substring(0, colon);
    return value.startsWith('www.') ? value.substring(4) : value;
  }

  /// Suggestions shown under an empty or partial query.
  static const List<String> operatorHelp = [
    'type:login',
    'type:card',
    'tag:',
    'has:totp',
    'has:attachment',
    'is:favourite',
    'is:weak',
    'is:reused',
    'url:',
    'user:',
    'in:trash',
  ];
}

/// Matches a vault item against the app or website asking for a credential.
///
/// Kept beside search because it is the same problem — "which entries relate to
/// this string" — but with rules that must be stricter. A false positive in
/// search is an annoyance; a false positive here offers a password to the wrong
/// site, so subdomain and suffix handling is deliberately conservative.
abstract final class UriMatcher {
  /// Domains where the registrable part is two labels deep, so `co.uk` is not
  /// mistaken for a registrable domain that anyone could claim.
  static const Set<String> _multiPartSuffixes = {
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'net.uk', 'sch.uk',
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
    'co.nz', 'net.nz', 'org.nz', 'co.za', 'org.za',
    'com.br', 'com.mx', 'com.ar', 'com.tr', 'com.cn', 'com.tw',
    'co.jp', 'ne.jp', 'or.jp', 'co.kr', 'co.in', 'net.in', 'org.in',
    'com.sg', 'com.hk', 'com.my', 'com.pk', 'com.ph', 'co.id', 'com.vn',
  };

  static String hostOf(String uri) => SearchEngine._hostOf(uri);

  /// The registrable domain: `mail.google.com` -> `google.com`,
  /// `shop.example.co.uk` -> `example.co.uk`.
  static String registrableDomain(String host) {
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    final lastTwo = labels.sublist(labels.length - 2).join('.');
    if (_multiPartSuffixes.contains(lastTwo) && labels.length >= 3) {
      return labels.sublist(labels.length - 3).join('.');
    }
    return lastTwo;
  }

  /// Whether [item] should be offered for [target].
  ///
  /// [target] is a web domain or an Android package name.
  static bool matches(VaultItem item, String target) {
    if (target.trim().isEmpty) return false;
    final normalisedTarget = target.trim().toLowerCase();

    for (final uri in item.allUris) {
      if (_singleUriMatches(uri, normalisedTarget)) return true;
    }

    // Android package names are also stored as `androidapp://com.example`.
    for (final uri in item.allUris) {
      final stripped = uri.toLowerCase().replaceFirst('androidapp://', '');
      if (stripped == normalisedTarget) return true;
    }
    return false;
  }

  static bool _singleUriMatches(String storedUri, String target) {
    final storedHost = hostOf(storedUri);
    if (storedHost.isEmpty) return false;

    final targetHost = target.contains('://') ? hostOf(target) : target;
    if (storedHost == targetHost) return true;

    // Same registrable domain: accounts.google.com fills on mail.google.com.
    // Anything looser — matching on a shared suffix, say — would offer
    // credentials across unrelated sites on shared hosting.
    final storedDomain = registrableDomain(storedHost);
    final targetDomain = registrableDomain(targetHost);
    return storedDomain.isNotEmpty &&
        storedDomain.contains('.') &&
        storedDomain == targetDomain;
  }

  /// Ranks candidates so the closest host appears first in the autofill sheet.
  static int compareForTarget(VaultItem a, VaultItem b, String target) {
    final targetHost = target.contains('://') ? hostOf(target) : target;
    int rank(VaultItem item) {
      for (final uri in item.allUris) {
        if (hostOf(uri) == targetHost) return 0; // exact host
      }
      return 1; // same registrable domain
    }

    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byUse = b.useCount.compareTo(a.useCount);
    if (byUse != 0) return byUse;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

/// Field-level helpers shared by search and autofill.
extension VaultItemFieldLookup on VaultItem {
  /// The first non-empty value whose spec declares [hint] as an autofill hint.
  String? valueForAutofillHint(String hint) {
    for (final spec in type.fields) {
      if (!spec.autofillHints.contains(hint)) continue;
      final value = fields[spec.key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Fields safe to show in a collapsed list row.
  Iterable<FieldSpec> get previewFields =>
      type.fields.where((spec) => !spec.isSecret);
}
