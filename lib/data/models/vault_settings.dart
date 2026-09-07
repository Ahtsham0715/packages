import 'package:flutter/foundation.dart';

/// How long the app may sit idle before it locks itself.
enum AutoLockDelay {
  immediately(0, 'Immediately'),
  fifteenSeconds(15, 'After 15 seconds'),
  thirtySeconds(30, 'After 30 seconds'),
  oneMinute(60, 'After 1 minute'),
  fiveMinutes(300, 'After 5 minutes'),
  fifteenMinutes(900, 'After 15 minutes'),
  never(-1, 'Only when I lock it');

  const AutoLockDelay(this.seconds, this.label);
  final int seconds;
  final String label;

  static AutoLockDelay fromSeconds(int seconds) => AutoLockDelay.values
      .firstWhere((d) => d.seconds == seconds,
          orElse: () => AutoLockDelay.oneMinute);
}

/// How the vault list is ordered.
enum VaultSortOrder {
  nameAscending('Name (A-Z)'),
  nameDescending('Name (Z-A)'),
  recentlyUsed('Recently used'),
  recentlyUpdated('Recently updated'),
  mostUsed('Most used');

  const VaultSortOrder(this.label);
  final String label;
}

/// User-controlled behaviour, stored encrypted inside the vault.
@immutable
class VaultSettings {
  const VaultSettings({
    this.autoLockSeconds = 60,
    this.lockWhenBackgrounded = true,
    this.biometricUnlock = false,
    this.clipboardClearSeconds = 30,
    this.panicWipeAfterAttempts = 0,
    this.blockScreenshots = true,
    this.hideContentsInAppSwitcher = true,
    this.autofillEnabled = false,
    this.trashRetentionDays = 30,
    this.sortOrder = VaultSortOrder.nameAscending,
    this.showFavouritesFirst = true,
    this.concealUsernamesInList = false,
    this.confirmPasswordBeforeExport = true,
    this.warnOnWeakOnSave = true,
  });

  factory VaultSettings.fromJson(Map<String, Object?> json) => VaultSettings(
        autoLockSeconds: (json['autoLock'] as int?) ?? 60,
        lockWhenBackgrounded: (json['lockBg'] as bool?) ?? true,
        biometricUnlock: (json['bio'] as bool?) ?? false,
        clipboardClearSeconds: (json['clip'] as int?) ?? 30,
        panicWipeAfterAttempts: (json['panic'] as int?) ?? 0,
        blockScreenshots: (json['noShot'] as bool?) ?? true,
        hideContentsInAppSwitcher: (json['noPeek'] as bool?) ?? true,
        autofillEnabled: (json['autofill'] as bool?) ?? false,
        trashRetentionDays: (json['trashDays'] as int?) ?? 30,
        sortOrder: VaultSortOrder.values.firstWhere(
          (o) => o.name == json['sort'],
          orElse: () => VaultSortOrder.nameAscending,
        ),
        showFavouritesFirst: (json['favFirst'] as bool?) ?? true,
        concealUsernamesInList: (json['hideUser'] as bool?) ?? false,
        confirmPasswordBeforeExport: (json['exportAuth'] as bool?) ?? true,
        warnOnWeakOnSave: (json['warnWeak'] as bool?) ?? true,
      );

  static const VaultSettings defaults = VaultSettings();

  /// Seconds of inactivity before locking. -1 means never.
  final int autoLockSeconds;

  /// Lock as soon as the app leaves the foreground, regardless of the timer.
  final bool lockWhenBackgrounded;

  final bool biometricUnlock;

  /// Seconds before a copied secret is cleared from the clipboard. 0 disables.
  final int clipboardClearSeconds;

  /// Erase the vault after this many consecutive failed unlocks. 0 disables.
  ///
  /// Off by default and guarded behind a typed confirmation: someone who
  /// enables this without understanding it can destroy their only copy by
  /// handing their phone to a curious child.
  final int panicWipeAfterAttempts;

  final bool blockScreenshots;
  final bool hideContentsInAppSwitcher;
  final bool autofillEnabled;
  final int trashRetentionDays;
  final VaultSortOrder sortOrder;
  final bool showFavouritesFirst;

  /// Mask usernames in the list, for use on a train.
  final bool concealUsernamesInList;

  final bool confirmPasswordBeforeExport;
  final bool warnOnWeakOnSave;

  AutoLockDelay get autoLockDelay => AutoLockDelay.fromSeconds(autoLockSeconds);

  Duration get trashRetention => Duration(days: trashRetentionDays);

  bool get panicWipeEnabled => panicWipeAfterAttempts > 0;

  Map<String, Object?> toJson() => {
        'autoLock': autoLockSeconds,
        'lockBg': lockWhenBackgrounded,
        'bio': biometricUnlock,
        'clip': clipboardClearSeconds,
        'panic': panicWipeAfterAttempts,
        'noShot': blockScreenshots,
        'noPeek': hideContentsInAppSwitcher,
        'autofill': autofillEnabled,
        'trashDays': trashRetentionDays,
        'sort': sortOrder.name,
        'favFirst': showFavouritesFirst,
        'hideUser': concealUsernamesInList,
        'exportAuth': confirmPasswordBeforeExport,
        'warnWeak': warnOnWeakOnSave,
      };

  VaultSettings copyWith({
    int? autoLockSeconds,
    bool? lockWhenBackgrounded,
    bool? biometricUnlock,
    int? clipboardClearSeconds,
    int? panicWipeAfterAttempts,
    bool? blockScreenshots,
    bool? hideContentsInAppSwitcher,
    bool? autofillEnabled,
    int? trashRetentionDays,
    VaultSortOrder? sortOrder,
    bool? showFavouritesFirst,
    bool? concealUsernamesInList,
    bool? confirmPasswordBeforeExport,
    bool? warnOnWeakOnSave,
  }) =>
      VaultSettings(
        autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
        lockWhenBackgrounded: lockWhenBackgrounded ?? this.lockWhenBackgrounded,
        biometricUnlock: biometricUnlock ?? this.biometricUnlock,
        clipboardClearSeconds:
            clipboardClearSeconds ?? this.clipboardClearSeconds,
        panicWipeAfterAttempts:
            panicWipeAfterAttempts ?? this.panicWipeAfterAttempts,
        blockScreenshots: blockScreenshots ?? this.blockScreenshots,
        hideContentsInAppSwitcher:
            hideContentsInAppSwitcher ?? this.hideContentsInAppSwitcher,
        autofillEnabled: autofillEnabled ?? this.autofillEnabled,
        trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
        sortOrder: sortOrder ?? this.sortOrder,
        showFavouritesFirst: showFavouritesFirst ?? this.showFavouritesFirst,
        concealUsernamesInList:
            concealUsernamesInList ?? this.concealUsernamesInList,
        confirmPasswordBeforeExport:
            confirmPasswordBeforeExport ?? this.confirmPasswordBeforeExport,
        warnOnWeakOnSave: warnOnWeakOnSave ?? this.warnOnWeakOnSave,
      );
}
