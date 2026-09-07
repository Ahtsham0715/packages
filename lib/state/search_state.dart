import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/vault_settings.dart';
import '../domain/models/vault_item.dart';
import '../domain/services/health_auditor.dart';
import '../domain/services/search_engine.dart';
import 'services.dart';
import 'vault_controller.dart';

/// The raw text in the search field.
final searchTextProvider = StateProvider<String>((ref) => '');

/// A type filter applied from the chip row, independent of the text query.
final typeFilterProvider = StateProvider<String?>((ref) => null);

/// The vault list as it should be shown right now.
///
/// Recomputed whenever the query, the filter or the vault changes. Search runs
/// over items already decrypted in memory, so this is a plain synchronous
/// provider rather than a future — which is what lets results update on every
/// keystroke without a spinner.
final searchResultsProvider = Provider<List<VaultItem>>((ref) {
  final vault = ref.watch(vaultControllerProvider).valueOrNull;
  if (vault == null || !vault.isUnlocked) return const [];

  final text = ref.watch(searchTextProvider);
  final typeFilter = ref.watch(typeFilterProvider);

  final queryText = [
    if (typeFilter != null) 'type:$typeFilter',
    text,
  ].where((part) => part.trim().isNotEmpty).join(' ');

  final query = SearchQuery.parse(queryText);
  final context = SearchContext(
    weakItemIds: vault.health.idsWith(HealthIssue.weak)
      ..addAll(vault.health.idsWith(HealthIssue.compromised)),
    reusedItemIds: vault.health.idsWith(HealthIssue.reused),
    staleItemIds: vault.health.idsWith(HealthIssue.stale),
  );

  if (query.isEmpty) {
    return _sorted(vault.items.where((item) => !item.isDeleted).toList(),
        vault.settings);
  }

  return SableServices.search
      .search(vault.items, query, context: context)
      .map((hit) => hit.item)
      .toList(growable: false);
});

/// Applies the user's chosen ordering to an unsearched list.
///
/// Only used when there is no query: with a query, relevance ordering wins,
/// because a name-sorted list of search results buries the best match.
List<VaultItem> _sorted(List<VaultItem> items, VaultSettings settings) {
  int byName(VaultItem a, VaultItem b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  final sorted = [...items];
  switch (settings.sortOrder) {
    case VaultSortOrder.nameAscending:
      sorted.sort(byName);
    case VaultSortOrder.nameDescending:
      sorted.sort((a, b) => byName(b, a));
    case VaultSortOrder.recentlyUsed:
      sorted.sort((a, b) {
        final aUsed = a.lastUsedAt;
        final bUsed = b.lastUsedAt;
        if (aUsed == null && bUsed == null) return byName(a, b);
        if (aUsed == null) return 1;
        if (bUsed == null) return -1;
        return bUsed.compareTo(aUsed);
      });
    case VaultSortOrder.recentlyUpdated:
      sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case VaultSortOrder.mostUsed:
      sorted.sort((a, b) {
        final byUse = b.useCount.compareTo(a.useCount);
        return byUse != 0 ? byUse : byName(a, b);
      });
  }

  if (settings.showFavouritesFirst) {
    final favourites = sorted.where((item) => item.favourite);
    final rest = sorted.where((item) => !item.favourite);
    return [...favourites, ...rest];
  }
  return sorted;
}

/// Candidate items for an autofill request, best match first.
final autofillCandidatesProvider =
    Provider.family<List<VaultItem>, String>((ref, target) {
  final vault = ref.watch(vaultControllerProvider).valueOrNull;
  if (vault == null || !vault.isUnlocked) return const [];

  final matches = vault.liveItems
      .where((item) => item.type.isAutofillable)
      .where((item) => UriMatcher.matches(item, target))
      .toList()
    ..sort((a, b) => UriMatcher.compareForTarget(a, b, target));
  return matches;
});
