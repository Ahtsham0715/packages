import 'package:flutter/widgets.dart';

import 'field_spec.dart';

/// Everything Sablekey can store.
///
/// The `id` is persisted inside the encrypted blob and must never change.
/// Order here is the order shown in the "new item" sheet, so the common types
/// come first.
enum ItemType {
  login(
    id: 'login',
    label: 'Login',
    description: 'Website or app sign-in',
    icon: Icons.language_rounded,
    primaryKey: 'username',
    passwordKey: 'password',
    uriKey: 'uri',
    fields: [
      FieldSpec(
        key: 'username',
        label: 'Username',
        kind: FieldKind.username,
        autofillHints: ['username', 'emailAddress'],
      ),
      FieldSpec(
        key: 'password',
        label: 'Password',
        kind: FieldKind.secret,
        autofillHints: ['password'],
      ),
      FieldSpec(
        key: 'uri',
        label: 'Website',
        kind: FieldKind.url,
        hint: 'example.com',
      ),
    ],
  ),

  card(
    id: 'card',
    label: 'Payment card',
    description: 'Credit or debit card',
    icon: Icons.credit_card_rounded,
    primaryKey: 'number',
    fields: [
      FieldSpec(
        key: 'holder',
        label: 'Cardholder name',
        kind: FieldKind.text,
        autofillHints: ['creditCardName'],
      ),
      FieldSpec(
        key: 'number',
        label: 'Card number',
        kind: FieldKind.cardNumber,
        autofillHints: ['creditCardNumber'],
      ),
      FieldSpec(
        key: 'expiry',
        label: 'Expires',
        kind: FieldKind.expiry,
        hint: 'MM/YY',
        autofillHints: ['creditCardExpirationDate'],
      ),
      FieldSpec(
        key: 'cvv',
        label: 'Security code',
        kind: FieldKind.pin,
        autofillHints: ['creditCardSecurityCode'],
      ),
      FieldSpec(key: 'pin', label: 'Card PIN', kind: FieldKind.pin),
      FieldSpec(key: 'issuer', label: 'Issuing bank', kind: FieldKind.text),
    ],
  ),

  secureNote(
    id: 'note',
    label: 'Secure note',
    description: 'Free-form encrypted text',
    icon: Icons.sticky_note_2_rounded,
    primaryKey: 'body',
    fields: [
      FieldSpec(key: 'body', label: 'Note', kind: FieldKind.multiline),
    ],
  ),

  identity(
    id: 'identity',
    label: 'Identity',
    description: 'Personal details for forms',
    icon: Icons.badge_rounded,
    primaryKey: 'fullName',
    fields: [
      FieldSpec(
        key: 'fullName',
        label: 'Full name',
        kind: FieldKind.text,
        autofillHints: ['name'],
      ),
      FieldSpec(
        key: 'email',
        label: 'Email',
        kind: FieldKind.email,
        autofillHints: ['emailAddress'],
      ),
      FieldSpec(
        key: 'phone',
        label: 'Phone',
        kind: FieldKind.phone,
        autofillHints: ['telephoneNumber'],
      ),
      FieldSpec(
        key: 'address',
        label: 'Address',
        kind: FieldKind.multiline,
        autofillHints: ['postalAddress'],
      ),
      FieldSpec(
        key: 'postcode',
        label: 'Postcode',
        kind: FieldKind.text,
        autofillHints: ['postalCode'],
      ),
      FieldSpec(key: 'country', label: 'Country', kind: FieldKind.text),
      FieldSpec(key: 'dob', label: 'Date of birth', kind: FieldKind.date),
      FieldSpec(key: 'nationalId', label: 'National ID', kind: FieldKind.secret),
    ],
  ),

  passport(
    id: 'passport',
    label: 'Passport',
    description: 'Travel document',
    icon: Icons.travel_explore_rounded,
    primaryKey: 'number',
    fields: [
      FieldSpec(key: 'fullName', label: 'Full name', kind: FieldKind.text),
      FieldSpec(key: 'number', label: 'Passport number', kind: FieldKind.secret),
      FieldSpec(key: 'country', label: 'Issuing country', kind: FieldKind.text),
      FieldSpec(key: 'issued', label: 'Issued', kind: FieldKind.date),
      FieldSpec(key: 'expires', label: 'Expires', kind: FieldKind.date),
      FieldSpec(key: 'birthplace', label: 'Place of birth', kind: FieldKind.text),
    ],
  ),

  driversLicence(
    id: 'licence',
    label: "Driver's licence",
    description: 'Licence details',
    icon: Icons.directions_car_rounded,
    primaryKey: 'number',
    fields: [
      FieldSpec(key: 'fullName', label: 'Full name', kind: FieldKind.text),
      FieldSpec(key: 'number', label: 'Licence number', kind: FieldKind.secret),
      FieldSpec(key: 'authority', label: 'Issuing authority', kind: FieldKind.text),
      FieldSpec(key: 'classes', label: 'Categories', kind: FieldKind.text),
      FieldSpec(key: 'issued', label: 'Issued', kind: FieldKind.date),
      FieldSpec(key: 'expires', label: 'Expires', kind: FieldKind.date),
    ],
  ),

  bankAccount(
    id: 'bank',
    label: 'Bank account',
    description: 'IBAN, sort code, account number',
    icon: Icons.account_balance_rounded,
    primaryKey: 'accountNumber',
    fields: [
      FieldSpec(key: 'bank', label: 'Bank', kind: FieldKind.text),
      FieldSpec(key: 'holder', label: 'Account holder', kind: FieldKind.text),
      FieldSpec(key: 'accountNumber', label: 'Account number', kind: FieldKind.secret),
      FieldSpec(key: 'sortCode', label: 'Sort code / routing', kind: FieldKind.text),
      FieldSpec(key: 'iban', label: 'IBAN', kind: FieldKind.secret),
      FieldSpec(key: 'swift', label: 'SWIFT / BIC', kind: FieldKind.text),
      FieldSpec(key: 'pin', label: 'Telephone banking PIN', kind: FieldKind.pin),
    ],
  ),

  wifi(
    id: 'wifi',
    label: 'Wi-Fi network',
    description: 'Network name and key',
    icon: Icons.wifi_rounded,
    primaryKey: 'ssid',
    passwordKey: 'password',
    fields: [
      FieldSpec(key: 'ssid', label: 'Network name (SSID)', kind: FieldKind.text),
      FieldSpec(key: 'password', label: 'Network key', kind: FieldKind.secret),
      FieldSpec(key: 'security', label: 'Security', kind: FieldKind.text, hint: 'WPA3'),
    ],
  ),

  sshKey(
    id: 'ssh',
    label: 'SSH key',
    description: 'Key pair and passphrase',
    icon: Icons.terminal_rounded,
    primaryKey: 'label',
    passwordKey: 'passphrase',
    fields: [
      FieldSpec(key: 'label', label: 'Key name', kind: FieldKind.text),
      FieldSpec(key: 'publicKey', label: 'Public key', kind: FieldKind.multiline),
      FieldSpec(key: 'privateKey', label: 'Private key', kind: FieldKind.secret),
      FieldSpec(key: 'passphrase', label: 'Passphrase', kind: FieldKind.secret),
      FieldSpec(key: 'fingerprint', label: 'Fingerprint', kind: FieldKind.text),
    ],
  ),

  server(
    id: 'server',
    label: 'Server',
    description: 'Host, port and credentials',
    icon: Icons.dns_rounded,
    primaryKey: 'host',
    passwordKey: 'password',
    fields: [
      FieldSpec(key: 'host', label: 'Host', kind: FieldKind.text),
      FieldSpec(key: 'port', label: 'Port', kind: FieldKind.number),
      FieldSpec(key: 'username', label: 'Username', kind: FieldKind.username),
      FieldSpec(key: 'password', label: 'Password', kind: FieldKind.secret),
      FieldSpec(key: 'protocol', label: 'Protocol', kind: FieldKind.text, hint: 'SSH'),
    ],
  ),

  database(
    id: 'database',
    label: 'Database',
    description: 'Connection details',
    icon: Icons.storage_rounded,
    primaryKey: 'database',
    passwordKey: 'password',
    fields: [
      FieldSpec(key: 'engine', label: 'Engine', kind: FieldKind.text, hint: 'PostgreSQL'),
      FieldSpec(key: 'host', label: 'Host', kind: FieldKind.text),
      FieldSpec(key: 'port', label: 'Port', kind: FieldKind.number),
      FieldSpec(key: 'database', label: 'Database', kind: FieldKind.text),
      FieldSpec(key: 'username', label: 'Username', kind: FieldKind.username),
      FieldSpec(key: 'password', label: 'Password', kind: FieldKind.secret),
      FieldSpec(key: 'connectionString', label: 'Connection string', kind: FieldKind.secret),
    ],
  ),

  apiCredential(
    id: 'api',
    label: 'API credential',
    description: 'Keys, tokens and secrets',
    icon: Icons.vpn_key_rounded,
    primaryKey: 'service',
    passwordKey: 'secret',
    fields: [
      FieldSpec(key: 'service', label: 'Service', kind: FieldKind.text),
      FieldSpec(key: 'keyId', label: 'Key ID', kind: FieldKind.text),
      FieldSpec(key: 'secret', label: 'Secret key', kind: FieldKind.secret),
      FieldSpec(key: 'token', label: 'Token', kind: FieldKind.secret),
      FieldSpec(key: 'endpoint', label: 'Endpoint', kind: FieldKind.url),
      FieldSpec(key: 'expires', label: 'Expires', kind: FieldKind.date),
    ],
  ),

  cryptoWallet(
    id: 'wallet',
    label: 'Crypto wallet',
    description: 'Seed phrase and keys',
    icon: Icons.currency_bitcoin_rounded,
    primaryKey: 'walletName',
    passwordKey: 'seedPhrase',
    fields: [
      FieldSpec(key: 'walletName', label: 'Wallet', kind: FieldKind.text),
      FieldSpec(key: 'seedPhrase', label: 'Recovery phrase', kind: FieldKind.secret),
      FieldSpec(key: 'privateKey', label: 'Private key', kind: FieldKind.secret),
      FieldSpec(key: 'publicAddress', label: 'Public address', kind: FieldKind.text),
      FieldSpec(key: 'passphrase', label: 'Passphrase', kind: FieldKind.secret),
      FieldSpec(key: 'derivationPath', label: 'Derivation path', kind: FieldKind.text),
    ],
  ),

  softwareLicence(
    id: 'software',
    label: 'Software licence',
    description: 'Product keys',
    icon: Icons.workspace_premium_rounded,
    primaryKey: 'product',
    passwordKey: 'licenceKey',
    fields: [
      FieldSpec(key: 'product', label: 'Product', kind: FieldKind.text),
      FieldSpec(key: 'version', label: 'Version', kind: FieldKind.text),
      FieldSpec(key: 'licenceKey', label: 'Licence key', kind: FieldKind.secret),
      FieldSpec(key: 'registeredTo', label: 'Registered to', kind: FieldKind.text),
      FieldSpec(key: 'purchased', label: 'Purchased', kind: FieldKind.date),
      FieldSpec(key: 'expires', label: 'Expires', kind: FieldKind.date),
    ],
  ),

  membership(
    id: 'membership',
    label: 'Membership',
    description: 'Loyalty and member numbers',
    icon: Icons.card_membership_rounded,
    primaryKey: 'memberNumber',
    fields: [
      FieldSpec(key: 'organisation', label: 'Organisation', kind: FieldKind.text),
      FieldSpec(key: 'memberNumber', label: 'Member number', kind: FieldKind.secret),
      FieldSpec(key: 'memberName', label: 'Member name', kind: FieldKind.text),
      FieldSpec(key: 'tier', label: 'Tier', kind: FieldKind.text),
      FieldSpec(key: 'expires', label: 'Expires', kind: FieldKind.date),
      FieldSpec(key: 'phone', label: 'Support phone', kind: FieldKind.phone),
    ],
  ),

  medical(
    id: 'medical',
    label: 'Medical record',
    description: 'Insurance and health details',
    icon: Icons.medical_information_rounded,
    primaryKey: 'policyNumber',
    fields: [
      FieldSpec(key: 'provider', label: 'Provider', kind: FieldKind.text),
      FieldSpec(key: 'policyNumber', label: 'Policy number', kind: FieldKind.secret),
      FieldSpec(key: 'groupNumber', label: 'Group number', kind: FieldKind.text),
      FieldSpec(key: 'patientName', label: 'Patient', kind: FieldKind.text),
      FieldSpec(key: 'bloodType', label: 'Blood type', kind: FieldKind.text),
      FieldSpec(key: 'allergies', label: 'Allergies', kind: FieldKind.multiline),
      FieldSpec(key: 'notes', label: 'Conditions', kind: FieldKind.multiline),
    ],
  );

  const ItemType({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.fields,
    required this.primaryKey,
    this.passwordKey,
    this.uriKey,
  });

  /// Stable persisted identifier.
  final String id;

  final String label;
  final String description;
  final IconData icon;
  final List<FieldSpec> fields;

  /// The field shown as the subtitle in lists.
  final String primaryKey;

  /// The field the health audit treats as "the password", if any.
  final String? passwordKey;

  /// The field autofill matches against a web domain or package name.
  final String? uriKey;

  bool get supportsTotp =>
      this == ItemType.login || this == ItemType.apiCredential || this == ItemType.server;

  /// Whether this type can be offered by the platform autofill service.
  bool get isAutofillable => passwordKey != null && this != ItemType.wifi;

  FieldSpec? specFor(String key) {
    for (final spec in fields) {
      if (spec.key == key) return spec;
    }
    return null;
  }

  static ItemType fromId(String id) {
    for (final type in ItemType.values) {
      if (type.id == id) return type;
    }
    // An unknown type means the vault came from a newer build. Degrade to a
    // note so the data stays visible and editable rather than disappearing.
    return ItemType.secureNote;
  }
}
