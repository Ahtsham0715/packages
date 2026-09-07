import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/domain/models/item_type.dart';
import 'package:sablekey/domain/models/vault_item.dart';
import 'package:sablekey/domain/services/search_engine.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  VaultItem item({
    required String id,
    required String name,
    ItemType type = ItemType.login,
    String? username,
    String? password,
    String? uri,
    Set<String> tags = const {},
    bool favourite = false,
    bool deleted = false,
    String notes = '',
  }) =>
      VaultItem(
        id: id,
        type: type,
        name: name,
        fields: {
          if (username != null) 'username': username,
          if (password != null) 'password': password,
          if (uri != null) 'uri': uri,
          if (type == ItemType.secureNote) 'body': notes,
        },
        tags: tags,
        notes: notes,
        favourite: favourite,
        deletedAt: deleted ? now : null,
        createdAt: now,
        updatedAt: now,
      );

  final github = item(
    id: '1',
    name: 'GitHub',
    username: 'octocat',
    password: 'correct-horse',
    uri: 'https://github.com',
    tags: {'work', 'dev'},
  );
  final gitlab = item(
    id: '2',
    name: 'GitLab',
    username: 'alice',
    password: 'other-password',
    uri: 'https://gitlab.com',
    tags: {'work'},
  );
  final bank = item(
    id: '3',
    name: 'Barclays Bank',
    username: 'alice@example.com',
    password: 'bank-password',
    uri: 'https://barclays.co.uk',
    favourite: true,
  );
  final card = item(
    id: '4',
    name: 'Travel card',
    type: ItemType.card,
  );
  final note = item(
    id: '5',
    name: 'Recovery codes',
    type: ItemType.secureNote,
    notes: 'backup codes for github',
  );
  final binned = item(id: '6', name: 'Old account', deleted: true);

  final vault = [github, gitlab, bank, card, note, binned];
  const engine = SearchEngine();

  List<String> search(String query, {SearchContext? context}) => engine
      .search(vault, SearchQuery.parse(query),
          context: context ?? const SearchContext())
      .map((hit) => hit.item.id)
      .toList();

  group('text search', () {
    test('finds an exact name', () {
      expect(search('GitHub'), contains('1'));
    });

    test('is case insensitive', () {
      expect(search('github'), contains('1'));
      expect(search('GITHUB'), contains('1'));
    });

    test('ranks an exact name match above a mention in a note', () {
      final results = search('github');
      expect(results.first, '1');
      expect(results, contains('5'));
    });

    test('matches a prefix', () {
      expect(search('git'), containsAll(['1', '2']));
    });

    test('matches by domain', () {
      expect(search('barclays'), contains('3'));
    });

    test('matches a username', () {
      expect(search('octocat'), contains('1'));
    });

    test('treats several terms as AND, not OR', () {
      // Adding a word must narrow the result set. If it widened it, typing
      // more would give you more, which is never what a search box should do.
      final broad = search('git');
      final narrow = search('git alice');
      expect(narrow.length, lessThan(broad.length));
      expect(narrow, ['2']);
    });

    test('matches a quoted phrase exactly', () {
      expect(search('"Barclays Bank"'), ['3']);
      expect(search('"Barclays Building"'), isEmpty);
    });

    test('falls back to a subsequence match', () {
      // "gtb" is not a substring of "GitHub", but it is a subsequence.
      expect(search('gtb'), contains('1'));
    });

    test('returns nothing for a term that matches nowhere', () {
      expect(search('zzzzznothing'), isEmpty);
    });
  });

  group('secrets are not searchable', () {
    test('a password never matches', () {
      // Matching on a password would let anyone holding an unlocked phone
      // confirm a guess without revealing anything on screen.
      expect(search('correct-horse'), isEmpty);
      expect(search('bank-password'), isEmpty);
    });
  });

  group('filters', () {
    test('type:', () {
      expect(search('type:card'), ['4']);
      expect(search('type:login'), containsAll(['1', '2', '3']));
      expect(search('type:card'), isNot(contains('1')));
    });

    test('tag:', () {
      expect(search('tag:work'), containsAll(['1', '2']));
      expect(search('tag:dev'), ['1']);
    });

    test('is:favourite', () {
      expect(search('is:favourite'), ['3']);
      expect(search('is:favorite'), ['3']);
    });

    test('has:url', () {
      expect(search('has:url'), containsAll(['1', '2', '3']));
      expect(search('has:url'), isNot(contains('4')));
    });

    test('combines a filter with free text', () {
      expect(search('type:login git'), containsAll(['1', '2']));
      expect(search('type:login git'), isNot(contains('5')));
    });

    test('audit-backed filters use the supplied context', () {
      const context = SearchContext(weakItemIds: {'2'}, reusedItemIds: {'1'});
      expect(search('is:weak', context: context), ['2']);
      expect(search('is:reused', context: context), ['1']);
    });
  });

  group('trash', () {
    test('deleted items are excluded by default', () {
      expect(search('Old account'), isEmpty);
      expect(search(''), isNot(contains('6')));
    });

    test('in:trash searches only deleted items', () {
      expect(search('in:trash'), ['6']);
      expect(search('in:trash'), isNot(contains('1')));
    });
  });

  group('query parsing', () {
    test('separates filters from terms', () {
      final query = SearchQuery.parse('type:login  hello  tag:work');
      expect(query.terms, ['hello']);
      expect(query.filters.length, 2);
    });

    test('keeps an unknown key as ordinary text', () {
      // Otherwise searching for "note:buy milk" as literal text, or for a URL
      // containing a colon, would silently return nothing.
      final query = SearchQuery.parse('banana:split');
      expect(query.filters, isEmpty);
      expect(query.terms, ['banana:split']);
    });

    test('handles quoted phrases containing spaces', () {
      final query = SearchQuery.parse('"two words" single');
      expect(query.phrases, ['two words']);
      expect(query.terms, ['single']);
    });

    test('an empty query is empty', () {
      expect(SearchQuery.parse('   ').isEmpty, isTrue);
    });
  });

  group('UriMatcher', () {
    test('matches an exact host', () {
      expect(UriMatcher.matches(github, 'github.com'), isTrue);
    });

    test('ignores scheme, path and www', () {
      expect(UriMatcher.matches(github, 'https://github.com/login'), isTrue);
      expect(UriMatcher.matches(github, 'www.github.com'), isTrue);
    });

    test('matches a subdomain of the same registrable domain', () {
      expect(UriMatcher.matches(github, 'gist.github.com'), isTrue);
    });

    test('does not match an unrelated site', () {
      expect(UriMatcher.matches(github, 'gitlab.com'), isFalse);
      expect(UriMatcher.matches(github, 'github.com.evil.example'), isFalse);
    });

    test('does not match on a shared public suffix', () {
      // The bug this guards against: treating "co.uk" as the registrable
      // domain, so a Barclays login is offered on every .co.uk site.
      expect(UriMatcher.matches(bank, 'hsbc.co.uk'), isFalse);
      expect(UriMatcher.matches(bank, 'barclays.co.uk'), isTrue);
      expect(UriMatcher.matches(bank, 'online.barclays.co.uk'), isTrue);
    });

    test('registrableDomain handles multi-part suffixes', () {
      expect(UriMatcher.registrableDomain('mail.google.com'), 'google.com');
      expect(UriMatcher.registrableDomain('shop.example.co.uk'),
          'example.co.uk');
      expect(UriMatcher.registrableDomain('example.com'), 'example.com');
    });

    test('matches an Android package via extraUris', () {
      final app = github.copyWith(
        extraUris: ['androidapp://com.github.android'],
      );
      expect(UriMatcher.matches(app, 'com.github.android'), isTrue);
      expect(UriMatcher.matches(app, 'com.evil.android'), isFalse);
    });

    test('ranks an exact host above a sibling subdomain', () {
      final exact = item(
        id: 'a',
        name: 'Exact',
        uri: 'https://mail.google.com',
        password: 'x',
      );
      final sibling = item(
        id: 'b',
        name: 'Sibling',
        uri: 'https://drive.google.com',
        password: 'x',
      );
      final ranked = [sibling, exact]
        ..sort((a, b) => UriMatcher.compareForTarget(a, b, 'mail.google.com'));
      expect(ranked.first.id, 'a');
    });
  });
}
