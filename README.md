<div align="center">

<img src="assets/brand/sablekey_icon_1024.png" width="120" alt="Sablekey">

# Sablekey

**A password manager that cannot phone home.**

No account. No sync. No servers. The Android build ships without the
permission required to open a network connection at all.

</div>

---

## What it is

Sablekey is an offline password manager for Android and iOS, built in Flutter.
Everything lives on the device, encrypted under a key derived from a master
password that is never stored anywhere.

Most "offline" apps mean *we don't currently upload anything*. This one means
the shipped APK holds no `INTERNET` permission, so it could not upload
anything if a future dependency tried — the manifest actively strips the
permission at merge time, and a test in CI fails if that directive disappears.

The trade-off is real and deliberate: no sync between devices, no web vault, no
"forgot password" link. If you lose the master password, the vault is gone.
That is what makes the rest of it true.

## Features

**Storage**
- 16 entry types: logins, payment cards, secure notes, identities, passports,
  driving licences, bank accounts, Wi-Fi networks, SSH keys, servers,
  databases, API credentials, crypto wallets, software licences, memberships,
  medical records
- Custom fields (plain or hidden) on any entry
- Encrypted file attachments, stored separately so they never load with the list
- Folders, tags, favourites
- Password history, kept automatically when you rotate a password
- Trash with automatic purge

**Finding things**
- Ranked fuzzy search — `gth` finds GitHub
- Mail-client operators: `type:login`, `tag:work`, `has:totp`, `has:attachment`,
  `is:favourite`, `is:weak`, `is:reused`, `url:`, `user:`, `in:trash`, and
  `"quoted phrases"`
- Secrets are deliberately **not** searchable, so the result list can never
  confirm a guess about a password

**Generating**
- Passwords with per-class control, look-alike exclusion, and a genuine
  uniform distribution (rejection sampling, not place-and-shuffle)
- Passphrases from a bundled 3,008-word list — 11.55 bits per word, stated
  honestly in the UI and computed from the real list length
- PINs and throwaway usernames
- Every draw comes from `Random.secure()`; a test fails the build if a plain
  `Random()` appears anywhere in `lib/`

**Two-factor**
- Built-in TOTP (RFC 6238), verified against all eight RFC test vectors
- SHA-1, SHA-256 and SHA-512; 6–10 digits; custom periods
- Scan a QR code with the camera, or paste a setup key

**Autofill**
- Android: a full `AutofillService` that **never caches a credential** — see
  below
- iOS: an AutoFill credential provider extension, opt-in, with its trade-off
  spelled out in the app itself

**Health**
- Weak, reused, old, expired and unencrypted-URL detection
- Offline strength estimation in the style of zxcvbn: dictionary words,
  keyboard runs, sequences, repeats and leet substitutions are each charged
  only what they really cost an attacker

**Getting data in and out**
- Encrypted `.skbak` backups with their own password and their own Argon2
  parameters
- CSV import from Bitwarden, 1Password, LastPass, KeePass, Dashlane, NordPass,
  Chrome and Edge
- Plaintext CSV export, because being able to leave is part of trusting a
  password manager — gated behind a warning and your master password

**Locking down**
- Auto-lock on idle and on leaving the foreground
- Biometric unlock (opt-in)
- Screenshot blocking and app-switcher hiding
- Clipboard marked sensitive at the OS level and cleared on a timer
- Exponential back-off on failed unlocks
- Optional panic wipe after N failures

## How your vault is protected

```
  master password
       │  Argon2id  (parameters measured on your device, stored in the header)
       ▼
  master key ──HKDF──┬──► key-encryption key ──► unwraps the data key
                     └──► verifier key       ──► "is this password right?"

  data key  (32 random bytes, never derived from the password)
       │  HKDF
       ├──► item key         ──► every vault record
       ├──► attachment key   ──► file payloads
       ├──► blind-index key  ──► duplicate detection
       └──► autofill key     ──► the optional iOS mirror
```

The data key being **random rather than password-derived** is the load-bearing
decision:

- Changing your master password rewraps 32 bytes instead of re-encrypting the
  whole vault, so it is instant on a vault of any size.
- Biometric unlock can recover a fully functional key ring from the platform
  keystore without the password ever being present.

Every stored secret goes through one authenticated envelope —
XChaCha20-Poly1305 with a random 24-byte nonce, with the format and algorithm
bytes covered by the tag. XChaCha rather than ChaCha because a 24-byte nonce
can be generated randomly with no practical collision risk; a 12-byte nonce
would need a counter, and a counter that resets after a restore silently
destroys confidentiality.

Decryption failures are deliberately indistinguishable from one another, so the
database file cannot be used as an oracle.

**Full threat model, including what this does *not* protect against:**
[SECURITY.md](SECURITY.md).

## How autofill works, and why it's built this way

The obvious way to implement Android autofill is to keep a decrypted index of
logins where the background service can read it. That would mean plaintext
credentials on disk whenever autofill is enabled — which undoes the entire
point of the app.

Sablekey does not do that. Its `AutofillService` answers every request with a
single **locked** dataset carrying an authentication intent. Tapping it launches
Sablekey, you unlock, you pick an entry, and that activity hands the chosen
values straight back to the requesting app. The vault is decrypted only inside
the app's own process, only while the picker is on screen.

The cost is one extra tap compared with managers that keep a plaintext cache.
That tap is the product.

**iOS cannot use this design.** A credential provider extension must produce
credentials from inside its own process, and it cannot run Argon2id or
XChaCha20 (neither is in CryptoKit). So iOS autofill is opt-in and writes a
**logins-only mirror** encrypted with AES-256-GCM under a Keychain key gated by
`.biometryCurrentSet`. Notes, cards, documents and attachments are never
mirrored. Anyone who can pass your device biometric could read that subset
without your master password. The app says exactly this on the toggle that
turns it on.

## Building

Prerequisites: Flutter 3.22+, and Xcode 15+ / Android SDK 34 for the respective
platforms.

This repository holds hand-written source, not generated scaffolding. Two
generated pieces are not committed and must be materialised once after cloning:

```bash
git clone <your-repo-url> sablekey
cd sablekey
flutter pub get

# Android: generate the Gradle wrapper (the wrapper .jar is a binary artefact)
cd android && gradle wrapper --gradle-version 8.7 && cd ..

# iOS: generate the Xcode project, then add the extension target (see below)
flutter create --platforms=ios --project-name sablekey --org com.sablekey .
```

Then:

```bash
flutter test                    # unit tests
flutter run                     # debug
flutter build apk --release     # Android
flutter build ipa --release     # iOS
```

### Android release signing

Create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Without it, release builds fall back to the debug key so the project still
assembles on a fresh clone.

### iOS AutoFill extension

`flutter create` generates `Runner` only. To wire up autofill, in Xcode:

1. **File → New → Target → AutoFill Credential Provider Extension**, named
   `SablekeyAutofill`.
2. Replace the generated files with the ones in `ios/SablekeyAutofill/`.
3. Add `ios/Runner/SablekeyMirror.swift` to **both** targets' Compile Sources.
4. Add the App Group `group.com.sablekey.app` to both targets, and register it
   on the Apple Developer portal.
5. Set both targets' entitlements to the `.entitlements` files in this repo.

Skip all of this if you only want Android; nothing else depends on it.

### Regenerating brand assets

```bash
python3 tool/generate_icons.py   # needs pillow
```

Redraws every launcher icon, the adaptive and monochrome layers, and the full
iOS AppIcon set from one vector description.

## Project layout

```
lib/
  core/crypto/      Argon2id, XChaCha20-Poly1305 envelope, key ring, TOTP
  core/platform/    FLAG_SECURE and autofill method channels
  core/services/    auto-lock, clipboard
  data/             SQLite, repository, backups, CSV, keystore
  domain/models/    item types (a field table, not a class per type)
  domain/services/  generator, search, health audit, strength estimation
  state/            Riverpod providers and the vault controller
  ui/               design system, widgets, screens
android/app/src/main/kotlin/…/autofill/   AutofillService, structure parser
ios/SablekeyAutofill/                     credential provider extension
test/                                     unit tests
tool/generate_icons.py                    brand asset generation
```

Item types are **data, not classes**. Each type declares its fields in a table
in `lib/domain/models/item_type.dart`, and the editor, detail view, search,
health audit, CSV mapping and autofill all read that table. Adding a type is a
table entry, not a new code path.

## Tests

```bash
flutter test
```

Covers the crypto envelope (including a bit-flip sweep over every byte of a
ciphertext), the key hierarchy and re-keying, TOTP against the RFC 6238
vectors, the generator's distribution and class guarantees, search ranking and
operator parsing, URI matching against public-suffix confusion, the health
audit and date parsing, CSV round-tripping, and backup tamper detection.

`test/hygiene_test.dart` asserts repository-level invariants: no insecure
`Random()` under `lib/`, no HTTP client anywhere, the manifest's
`INTERNET`-removal directive still present, and that a generated passphrase is
never rated weak by the app's own estimator.

## Status

Version 1.0.0. Written as a personal-use application.

The cryptographic design follows current practice and the algorithm-level
behaviour is covered by tests against published vectors, but it has not had an
external security audit. Treat it accordingly.

## Licence

MIT — see [LICENSE](LICENSE).
