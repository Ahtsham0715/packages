import 'package:flutter/widgets.dart';

/// How a field behaves: what keyboard it gets, whether it is masked, whether it
/// can be copied, and what the detail screen offers to do with it.
enum FieldKind {
  /// Plain single-line text.
  text,

  /// A login name. Offered to the autofill service as a username candidate.
  username,

  email,

  /// A site or app URI. Drives autofill matching and the "open" action.
  url,

  phone,

  /// Masked by default, copied to a clipboard that self-clears, excluded from
  /// screenshots, and covered by the reuse audit.
  secret,

  /// A short numeric secret. Masked, numeric keypad.
  pin,

  /// A payment card number: masked, grouped 4-4-4-4, Luhn-checked.
  cardNumber,

  /// MM/YY.
  expiry,

  /// A full date.
  date,

  /// Free-form notes. Rendered as a growing multi-line box.
  multiline,

  number;

  bool get isSecret =>
      this == FieldKind.secret || this == FieldKind.pin || this == FieldKind.cardNumber;

  /// Whether the reuse/weakness audit should look at this field.
  bool get isAudited => this == FieldKind.secret;

  TextInputType get keyboardType => switch (this) {
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.url => TextInputType.url,
        FieldKind.phone => TextInputType.phone,
        FieldKind.pin ||
        FieldKind.number ||
        FieldKind.cardNumber =>
          TextInputType.number,
        FieldKind.multiline => TextInputType.multiline,
        FieldKind.date || FieldKind.expiry => TextInputType.datetime,
        _ => TextInputType.text,
      };
}

/// The declaration of one field on an item type.
///
/// Item types are described by data rather than by a class per type. Adding
/// "Wi-Fi network" or "API credential" is a table entry, and the editor, the
/// detail view, search, the audit and autofill all pick it up without changes.
@immutable
class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.hint,
    this.autofillHints = const <String>[],
  });

  /// Stable storage key. Never change one of these without a migration — it is
  /// the key inside every encrypted item blob.
  final String key;

  final String label;
  final FieldKind kind;
  final String? hint;

  /// Platform autofill hints this field can satisfy, so the Android autofill
  /// service can map a form field to the right value.
  final List<String> autofillHints;

  bool get isSecret => kind.isSecret;
}
