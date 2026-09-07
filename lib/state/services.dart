import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/clipboard_service.dart';
import '../data/db/vault_database.dart';
import '../data/key_storage.dart';
import '../data/vault_repository.dart';
import '../domain/services/health_auditor.dart';
import '../domain/services/password_generator.dart';
import '../domain/services/password_strength.dart';
import '../domain/services/search_engine.dart';

/// Everything the app needs that has to be built asynchronously.
///
/// Bundled into one object so the UI waits on a single future at startup
/// instead of a cascade of them, and so the wordlists — which are read from
/// bundled assets — are parsed exactly once for the life of the process.
class SableServices {
  SableServices({
    required this.database,
    required this.repository,
    required this.keyStorage,
    required this.generator,
    required this.estimator,
    required this.auditor,
    required this.clipboard,
  });

  final VaultDatabase database;
  final VaultRepository repository;
  final KeyStorage keyStorage;
  final PasswordGenerator generator;
  final PasswordStrengthEstimator estimator;
  final HealthAuditor auditor;
  final ClipboardService clipboard;

  static const SearchEngine search = SearchEngine();
}

/// Opens the database and loads the bundled word lists.
final servicesProvider = FutureProvider<SableServices>((ref) async {
  final database = await VaultDatabase.open();
  final repository = VaultRepository(database);

  // Load the header eagerly: the unlock screen needs to know whether a vault
  // exists before it can decide what to show.
  await repository.loadHeader();

  final wordlistSource =
      await rootBundle.loadString('assets/wordlist/passphrase_words.txt');
  final commonSource =
      await rootBundle.loadString('assets/wordlist/common_passwords.txt');

  final words = PasswordGenerator.parseWordlist(wordlistSource);
  final commonPasswords = PasswordGenerator.parseWordlist(commonSource)
      .map((word) => word.toLowerCase())
      .toSet();

  final estimator = PasswordStrengthEstimator(
    commonPasswords: commonPasswords,
    // The passphrase list doubles as the dictionary the strength estimator
    // charges word-level entropy for. That keeps the two consistent: a
    // passphrase built from this list is scored by exactly the list it came
    // from, rather than by a different one that would over- or under-rate it.
    dictionaryWords: words.map((word) => word.toLowerCase()).toSet(),
  );

  final services = SableServices(
    database: database,
    repository: repository,
    keyStorage: KeyStorage(),
    generator: PasswordGenerator(wordlist: words),
    estimator: estimator,
    auditor: HealthAuditor(estimator: estimator),
    clipboard: ClipboardService(),
  );

  ref.onDispose(() {
    services.clipboard.dispose();
    // Locking on dispose means a hot restart in development cannot leave keys
    // alive in a detached isolate.
    repository.lock();
  });

  return services;
});

/// Convenience accessors, valid only once [servicesProvider] has resolved.
final repositoryProvider = Provider<VaultRepository>((ref) {
  return ref.watch(servicesProvider).requireValue.repository;
});

final clipboardProvider = Provider<ClipboardService>((ref) {
  return ref.watch(servicesProvider).requireValue.clipboard;
});

final generatorProvider = Provider<PasswordGenerator>((ref) {
  return ref.watch(servicesProvider).requireValue.generator;
});

final estimatorProvider = Provider<PasswordStrengthEstimator>((ref) {
  return ref.watch(servicesProvider).requireValue.estimator;
});

final auditorProvider = Provider<HealthAuditor>((ref) {
  return ref.watch(servicesProvider).requireValue.auditor;
});

final keyStorageProvider = Provider<KeyStorage>((ref) {
  return ref.watch(servicesProvider).requireValue.keyStorage;
});
