import 'package:flutter/foundation.dart';

/// Things worth being able to look back on.
enum SecurityEventKind {
  vaultCreated('Vault created'),
  unlocked('Vault unlocked'),
  failedUnlock('Failed unlock attempt'),
  lockedOut('Locked out after repeated failures'),
  masterPasswordChanged('Master password changed'),
  biometricEnrolled('Biometric unlock enabled'),
  biometricRemoved('Biometric unlock disabled'),
  exported('Vault exported'),
  imported('Items imported'),
  autofillServed('Credential filled into another app'),
  autofillEnabled('Autofill service enabled'),
  panicWipe('Vault erased after failed attempts'),
  vaultErased('Vault erased');

  const SecurityEventKind(this.label);
  final String label;

  static SecurityEventKind fromName(String name) =>
      SecurityEventKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => SecurityEventKind.unlocked,
      );
}

/// One line in the encrypted security log.
///
/// The log lives inside the vault, sealed under the same key as everything
/// else. A plaintext audit log would be a gift to anyone with the device: it
/// would tell them when the vault is typically opened, which apps were filled,
/// and whether a wipe threshold is close.
@immutable
class SecurityEvent {
  const SecurityEvent({
    required this.kind,
    required this.at,
    this.detail,
  });

  factory SecurityEvent.fromJson(Map<String, Object?> json) => SecurityEvent(
        kind: SecurityEventKind.fromName(json['kind']! as String),
        at: DateTime.fromMillisecondsSinceEpoch(json['at']! as int),
        detail: json['detail'] as String?,
      );

  factory SecurityEvent.vaultCreated() =>
      SecurityEvent(kind: SecurityEventKind.vaultCreated, at: DateTime.now());

  factory SecurityEvent.unlocked({required String method}) => SecurityEvent(
        kind: SecurityEventKind.unlocked,
        at: DateTime.now(),
        detail: method,
      );

  factory SecurityEvent.masterPasswordChanged() => SecurityEvent(
        kind: SecurityEventKind.masterPasswordChanged,
        at: DateTime.now(),
      );

  factory SecurityEvent.exported({required String format}) => SecurityEvent(
        kind: SecurityEventKind.exported,
        at: DateTime.now(),
        detail: format,
      );

  factory SecurityEvent.imported({required int count, required String source}) =>
      SecurityEvent(
        kind: SecurityEventKind.imported,
        at: DateTime.now(),
        detail: '$count items from $source',
      );

  factory SecurityEvent.autofillServed({required String target}) =>
      SecurityEvent(
        kind: SecurityEventKind.autofillServed,
        at: DateTime.now(),
        detail: target,
      );

  final SecurityEventKind kind;
  final DateTime at;

  /// Short context. Must never contain a secret — this is a log, and logs get
  /// read on screens in public.
  final String? detail;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'at': at.millisecondsSinceEpoch,
        if (detail != null) 'detail': detail,
      };
}
