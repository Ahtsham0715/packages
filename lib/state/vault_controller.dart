import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/key_ring.dart';
import '../core/crypto/kdf.dart';
import '../core/platform/secure_screen.dart';
import '../core/services/auto_lock_service.dart';
import '../data/autofill_mirror.dart';
import '../data/key_storage.dart';
import '../data/models/security_event.dart';
import '../data/models/vault_settings.dart';
import '../domain/models/vault_item.dart';
import '../domain/services/health_auditor.dart';
import 'services.dart';

/// Where the app is in its lifecycle.
enum VaultStatus {
  /// Still opening the database.
  loading,

  /// No vault on this device yet — show onboarding.
  needsSetup,

  /// A vault exists and is closed.
  locked,

  /// Open, with items in memory.
  unlocked,
}

@immutable
class VaultState {
  const VaultState({
    required this.status,
    this.items = const [],
    this.folders = const [],
    this.settings = VaultSettings.defaults,
    this.health = VaultHealthReport.empty,
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.biometricAvailable = false,
    this.biometricEnrolled = false,
    this.errorMessage,
    this.busy = false,
  });

  final VaultStatus status;

  /// Decrypted items. Present only while [status] is [VaultStatus.unlocked],
  /// and dropped the instant the vault locks.
  final List<VaultItem> items;

  final List<Folder> folders;
  final VaultSettings settings;
  final VaultHealthReport health;

  final int failedAttempts;
  final DateTime? lockoutUntil;
  final bool biometricAvailable;
  final bool biometricEnrolled;

  final String? errorMessage;
  final bool busy;

  bool get isUnlocked => status == VaultStatus.unlocked;

  bool get isLockedOut =>
      lockoutUntil != null && lockoutUntil!.isAfter(DateTime.now());

  Duration get lockoutRemaining => lockoutUntil == null
      ? Duration.zero
      : lockoutUntil!.difference(DateTime.now());

  List<VaultItem> get liveItems =>
      items.where((item) => !item.isDeleted).toList(growable: false);

  List<VaultItem> get trashedItems =>
      items.where((item) => item.isDeleted).toList(growable: false);

  Set<String> get allTags {
    final tags = <String>{};
    for (final item in liveItems) {
      tags.addAll(item.tags);
    }
    return tags;
  }

  VaultState copyWith({
    VaultStatus? status,
    List<VaultItem>? items,
    List<Folder>? folders,
    VaultSettings? settings,
    VaultHealthReport? health,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool clearLockout = false,
    bool? biometricAvailable,
    bool? biometricEnrolled,
    String? errorMessage,
    bool clearError = false,
    bool? busy,
  }) =>
      VaultState(
        status: status ?? this.status,
        items: items ?? this.items,
        folders: folders ?? this.folders,
        settings: settings ?? this.settings,
        health: health ?? this.health,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
        biometricAvailable: biometricAvailable ?? this.biometricAvailable,
        biometricEnrolled: biometricEnrolled ?? this.biometricEnrolled,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        busy: busy ?? this.busy,
      );
}

final vaultControllerProvider =
    AsyncNotifierProvider<VaultController, VaultState>(VaultController.new);

/// Owns the vault's lifecycle: setup, unlock, edits, lock.
///
/// Every path that produces or destroys key material goes through here, which
/// is what makes the auto-lock guarantee checkable — there is one `lock()`, and
/// it is the only thing that drops the decrypted items.
class VaultController extends AsyncNotifier<VaultState> {
  AutoLockService? _autoLock;

  @override
  Future<VaultState> build() async {
    final services = await ref.watch(servicesProvider.future);
    final repository = services.repository;

    _autoLock ??= AutoLockService(onLock: lock)..start();
    ref.onDispose(() => _autoLock?.stop());

    final exists = await repository.vaultExists;
    if (!exists) {
      return const VaultState(status: VaultStatus.needsSetup);
    }

    return VaultState(
      status: VaultStatus.locked,
      failedAttempts: await repository.failedAttempts(),
      lockoutUntil: await repository.lockoutUntil(),
      biometricAvailable: await services.keyStorage.isBiometricAvailable,
      biometricEnrolled: await services.keyStorage.isEnrolled,
    );
  }

  VaultState get _current => state.requireValue;

  SableServices get _services => ref.read(servicesProvider).requireValue;

  // ---------------------------------------------------------------------
  // Setup and unlock
  // ---------------------------------------------------------------------

  /// Creates the vault. [onProgress] fires while Argon2 parameters are being
  /// calibrated, which takes a couple of seconds on a mid-range phone.
  Future<void> createVault(String masterPassword) async {
    state = AsyncData(_current.copyWith(busy: true, clearError: true));
    try {
      final params = await Kdf.calibrate();
      await _services.repository.createVault(
        password: masterPassword,
        params: params,
      );
      await _loadUnlockedState();
    } on Object catch (error) {
      state = AsyncData(_current.copyWith(
        busy: false,
        errorMessage: 'Could not create the vault: $error',
      ));
    }
  }

  Future<bool> unlock(String masterPassword) async {
    if (_current.isLockedOut) return false;

    state = AsyncData(_current.copyWith(busy: true, clearError: true));
    final repository = _services.repository;

    try {
      await repository.unlock(masterPassword);
      await _loadUnlockedState();
      return true;
    } on WrongPasswordException {
      final attempts = await repository.failedAttempts();
      final settings = _current.settings;

      // Panic wipe, if the user asked for it. Checked here rather than in the
      // repository so it can never fire during a background or scripted call.
      if (settings.panicWipeEnabled &&
          attempts >= settings.panicWipeAfterAttempts) {
        await _panicWipe();
        return false;
      }

      state = AsyncData(_current.copyWith(
        busy: false,
        failedAttempts: attempts,
        lockoutUntil: await repository.lockoutUntil(),
        errorMessage: 'Incorrect master password',
      ));
      return false;
    } on Object catch (error) {
      state = AsyncData(_current.copyWith(
        busy: false,
        errorMessage: 'Could not open the vault: $error',
      ));
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    final keyStorage = _services.keyStorage;
    state = AsyncData(_current.copyWith(busy: true, clearError: true));

    final dataKey = await keyStorage.unlock();
    if (dataKey == null) {
      state = AsyncData(_current.copyWith(
        busy: false,
        errorMessage: keyStorage.lastOutcome == BiometricOutcome.cancelled
            ? null
            : keyStorage.lastOutcome.message,
        clearError: keyStorage.lastOutcome == BiometricOutcome.cancelled,
      ));
      return false;
    }

    try {
      await _services.repository.unlockWithDataKey(dataKey);
      await _loadUnlockedState();
      return true;
    } on Object catch (error) {
      state = AsyncData(_current.copyWith(
        busy: false,
        errorMessage: 'Biometric unlock failed: $error',
      ));
      return false;
    }
  }

  Future<void> _loadUnlockedState() async {
    final repository = _services.repository;
    final settings = await repository.loadSettings();

    // Housekeeping that only makes sense with the keys available.
    await repository.purgeExpiredTrash(settings.trashRetention);

    final snapshot = await repository.loadAll();
    final health = _services.auditor.audit(snapshot.items);

    await SecureScreen.setSecure(enabled: settings.blockScreenshots);

    _autoLock!
      ..configure(
        autoLockSeconds: settings.autoLockSeconds,
        lockWhenBackgrounded: settings.lockWhenBackgrounded,
      )
      ..arm();

    state = AsyncData(VaultState(
      status: VaultStatus.unlocked,
      items: snapshot.items,
      folders: snapshot.folders,
      settings: snapshot.settings,
      health: health,
      biometricAvailable: _current.biometricAvailable,
      biometricEnrolled: await _services.keyStorage.isEnrolled,
    ));

    if (settings.autofillEnabled) {
      unawaited(AutofillMirror.sync(snapshot.items));
    }
  }

  /// Drops every key and every decrypted item.
  ///
  /// Safe to call at any time, including when already locked — the auto-lock
  /// timer and the lifecycle observer both race towards it.
  void lock() {
    final services = ref.read(servicesProvider).valueOrNull;
    if (services == null) return;

    services.repository.lock();
    unawaited(services.clipboard.clearNow());
    _autoLock?.disarm();

    final previous = state.valueOrNull;
    if (previous == null || previous.status == VaultStatus.needsSetup) return;

    state = AsyncData(VaultState(
      status: VaultStatus.locked,
      biometricAvailable: previous.biometricAvailable,
      biometricEnrolled: previous.biometricEnrolled,
      settings: previous.settings,
    ));
  }

  /// Resets the idle countdown. Wired to the app-wide activity detector.
  void noteActivity() => _autoLock?.touch();

  Future<void> _panicWipe() async {
    final repository = _services.repository;
    await repository.logEvent(SecurityEvent(
      kind: SecurityEventKind.panicWipe,
      at: DateTime.now(),
    ));
    await repository.eraseVault();
    await _services.keyStorage.removeEnrolment();
    await AutofillMirror.clear();
    state = const AsyncData(VaultState(status: VaultStatus.needsSetup));
  }

  // ---------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------

  Future<VaultItem> saveItem(VaultItem item) async {
    final saved = await _services.repository.saveItem(item);
    await _refreshItems();
    return saved;
  }

  Future<void> trashItem(VaultItem item) async {
    await _services.repository.trashItem(item);
    await _refreshItems();
  }

  Future<void> restoreItem(VaultItem item) async {
    await _services.repository.restoreItem(item);
    await _refreshItems();
  }

  Future<void> purgeItem(VaultItem item) async {
    await _services.repository.purgeItem(item.id);
    await _refreshItems();
  }

  Future<int> emptyTrash() async {
    final count = await _services.repository.emptyTrash();
    await _refreshItems();
    return count;
  }

  Future<void> toggleFavourite(VaultItem item) async {
    await _services.repository.saveItem(
      item.copyWith(favourite: !item.favourite, updatedAt: DateTime.now()),
    );
    await _refreshItems();
  }

  /// Records a use, for the recently-used ordering.
  ///
  /// Deliberately does not refresh the whole vault: this fires on every copy,
  /// and re-auditing several thousand items each time a password is copied
  /// would make the button feel slow for no visible benefit.
  Future<void> noteItemUsed(VaultItem item) async {
    final updated = item.markUsed();
    await _services.repository.saveItem(updated);
    final items = [
      for (final existing in _current.items)
        if (existing.id == updated.id) updated else existing,
    ];
    state = AsyncData(_current.copyWith(items: items));
  }

  Future<void> saveFolder(Folder folder) async {
    await _services.repository.saveFolder(folder);
    state = AsyncData(
        _current.copyWith(folders: await _services.repository.loadFolders()));
  }

  Future<void> deleteFolder(String id) async {
    await _services.repository.deleteFolder(id);
    // Items pointing at the removed folder fall back to no folder rather than
    // becoming unreachable.
    for (final item in _current.items.where((i) => i.folderId == id)) {
      await _services.repository.saveItem(item.copyWith(clearFolder: true));
    }
    await _refreshItems();
  }

  Future<void> importItems(List<VaultItem> items) async {
    await _services.repository.saveItems(items);
    await _services.repository.logEvent(
      SecurityEvent.imported(count: items.length, source: 'file'),
    );
    await _refreshItems();
  }

  Future<void> _refreshItems() async {
    final repository = _services.repository;
    final items = await repository.loadItems();
    final folders = await repository.loadFolders();
    final health = _services.auditor.audit(items);

    state = AsyncData(_current.copyWith(
      items: items,
      folders: folders,
      health: health,
    ));

    if (_current.settings.autofillEnabled) {
      unawaited(AutofillMirror.sync(items));
    }
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  Future<void> updateSettings(VaultSettings settings) async {
    await _services.repository.saveSettings(settings);
    await SecureScreen.setSecure(enabled: settings.blockScreenshots);

    _autoLock?.configure(
      autoLockSeconds: settings.autoLockSeconds,
      lockWhenBackgrounded: settings.lockWhenBackgrounded,
    );

    state = AsyncData(_current.copyWith(settings: settings));

    if (settings.autofillEnabled) {
      unawaited(AutofillMirror.sync(_current.items));
    } else {
      unawaited(AutofillMirror.clear());
    }
  }

  /// Turns on biometric unlock, having just verified the master password.
  Future<bool> enrolBiometrics() async {
    final repository = _services.repository;
    if (!repository.isUnlocked) return false;

    final dataKey = repository.keyRing.exportDataKeyForWrapping();
    try {
      await _services.keyStorage.enrol(dataKey);
      await repository.logEvent(SecurityEvent(
        kind: SecurityEventKind.biometricEnrolled,
        at: DateTime.now(),
      ));
      await updateSettings(_current.settings.copyWith(biometricUnlock: true));
      state = AsyncData(_current.copyWith(biometricEnrolled: true));
      return true;
    } on Object catch (error) {
      state = AsyncData(_current.copyWith(
        errorMessage: 'Could not enable biometric unlock: $error',
      ));
      return false;
    } finally {
      // The copy handed to the keystore is the keystore's now; wipe ours.
      dataKey.fillRange(0, dataKey.length, 0);
    }
  }

  Future<void> removeBiometrics() async {
    await _services.keyStorage.removeEnrolment();
    await _services.repository.logEvent(SecurityEvent(
      kind: SecurityEventKind.biometricRemoved,
      at: DateTime.now(),
    ));
    await updateSettings(_current.settings.copyWith(biometricUnlock: false));
    state = AsyncData(_current.copyWith(biometricEnrolled: false));
  }

  Future<bool> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final repository = _services.repository;
    if (!await repository.verifyMasterPassword(currentPassword)) {
      state = AsyncData(
          _current.copyWith(errorMessage: 'Your current password is incorrect'));
      return false;
    }

    await repository.changeMasterPassword(newPassword: newPassword);

    // The biometric enrolment and the iOS mirror both wrap the data key. The
    // data key itself has not changed, so they stay valid — but someone
    // changing their master password usually means to revoke access, so both
    // are cleared and must be set up again deliberately.
    await _services.keyStorage.removeEnrolment();
    await AutofillMirror.clear();
    await updateSettings(_current.settings.copyWith(
      biometricUnlock: false,
      autofillEnabled: false,
    ));
    state = AsyncData(_current.copyWith(biometricEnrolled: false));
    return true;
  }

  Future<void> eraseVault() async {
    await _services.repository.eraseVault();
    await _services.keyStorage.removeEnrolment();
    await AutofillMirror.clear();
    _autoLock?.disarm();
    state = const AsyncData(VaultState(status: VaultStatus.needsSetup));
  }

  void clearError() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearError: true));
  }
}
