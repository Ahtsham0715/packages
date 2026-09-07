# Security design and threat model

This document states what Sablekey protects, how, and — more importantly —
what it does not protect against. A password manager that only lists its
strengths is not being straight with you.

---

## 1. Cryptographic design

### Key hierarchy

```
  master password
       │  Argon2id(salt, m/t/p from the vault header)
       ▼
  master key ──HKDF-SHA256──┬──► key-encryption key   (info "sablekey/v1/kek")
                            └──► verifier key         (info "sablekey/v1/verifier")

  data key  (32 bytes from Random.secure(), never derived from the password)
       │  HKDF-SHA256
       ├──► item key        (info "sablekey/v1/item")
       ├──► attachment key  (info "sablekey/v1/attachment")
       ├──► blind-index key (info "sablekey/v1/blind-index")
       └──► autofill key    (info "sablekey/v1/autofill")
```

The master key never encrypts anything directly. It wraps the data key, and
nothing else.

**Why the data key is random rather than derived.** Two consequences follow,
and both matter:

1. Changing the master password rewraps 32 bytes. It does not re-encrypt the
   vault, so it is instant whether you have 5 entries or 5,000.
2. Biometric unlock is possible at all. The platform keystore holds a second
   wrapper around the same data key, so a fingerprint reconstructs a fully
   functional key ring without the master password being present.

**Why every purpose gets its own subkey.** A flaw that exposes one subkey — the
iOS autofill mirror key being the most exposed — reveals nothing about the
others.

### Primitives

| Purpose | Algorithm | Notes |
|---|---|---|
| Password hashing | Argon2id | Parameters calibrated per device, stored in the header, floor enforced on read |
| Authenticated encryption | XChaCha20-Poly1305 | Random 24-byte nonce per message |
| Key derivation | HKDF-SHA256 | Distinct `info` label per purpose |
| TOTP | HMAC-SHA1/256/512 | RFC 6238 |
| Blind index | HMAC-SHA256, truncated to 128 bits | Keyed from the data key |

**Why XChaCha20 and not ChaCha20.** The 24-byte nonce can be generated randomly
with no practical collision risk. A 12-byte nonce would require a per-key
counter, and a counter that resets — after restoring from a backup, say —
silently destroys confidentiality. Getting that wrong produces no error and no
symptom.

**Why Argon2id and not PBKDF2.** Memory-hardness is what makes GPU and ASIC
attacks expensive rather than merely slower.

### The envelope

```
  0     'S'
  1     'K'
  2     format version (1)
  3     algorithm id   (1 = XChaCha20-Poly1305)
  4..27 nonce (24 random bytes)
  28..  ciphertext || Poly1305 tag
```

The 4-byte header is passed as additional authenticated data, so the version
and algorithm bytes are covered by the tag. Without that, an attacker with
write access could flip the algorithm byte and try to steer a future build onto
a weaker cipher.

Each record also binds its own identity into the AAD (the item id, the string
`settings`, `attachment:<id>`, and so on), so a valid ciphertext cannot be
lifted out of one row and dropped into another.

**Decryption failures are indistinguishable.** `DecryptionFailure` carries no
detail about whether the key was wrong, the MAC failed, or the input was
truncated. Distinguishing them would turn the database file into a decryption
oracle for anyone who can write to it.

### KDF parameter floor

Argon2 parameters live in the vault header so a vault created on a slow phone
still opens on a fast one, and so the cost can be raised later. That makes the
header an attack surface: an attacker who can write to the database could set
`m=8, t=1` and then brute-force the master password cheaply.

`KdfParams.meetsFloor` is checked on every unlock and every backup restore.
Below the floor, the vault refuses to open rather than deriving weakly. This is
covered by a test.

### Password normalisation

The master password is normalised before derivation: zero-width characters are
stripped, full-width Latin is folded to ASCII, and every Unicode space variant
becomes U+0020. A phone keyboard that emits U+00A0 instead of a space would
otherwise lock you out of your own vault, with no way to discover why.

---

## 2. What is stored, and what leaks

Every secret is encrypted before SQLite sees it. The columns beside each
ciphertext hold an opaque UUID and timestamps — nothing else. Item type, name,
folder, tags and URLs all live *inside* the encrypted blob.

**What an attacker with a copy of `vault.db` learns:**

- how many entries exist
- when each was created and last modified
- how many attachments exist and roughly how large each is
- when the vault was created and when the password was last changed

**What they do not learn:** anything about the content.

This residual metadata is a deliberate trade. Keeping timestamps in the clear
is what lets the app list, sort and page the vault without decrypting every
row, and what makes an interrupted write recoverable.

**Failed-attempt counters are stored in plaintext**, because they must be
readable while the vault is locked — which is the only moment they matter.

**The security event log is encrypted.** A plaintext audit log would tell an
attacker when the vault is usually opened, which apps have been filled, and how
close a panic-wipe threshold is.

---

## 3. Platform hardening

### Android

- **No `INTERNET` permission.** The manifest does not merely omit it; it
  strips it with `tools:node="remove"`, so a plugin three levels down the
  dependency tree cannot reintroduce it into the merged manifest. Verify with
  `./gradlew :app:processReleaseManifest` and read the output. The debug
  variant adds it back for `flutter attach`; release builds cannot open a
  socket.
- **`allowBackup="false"` plus explicit `data-extraction-rules`.** With backup
  on, Android would copy the vault to Google Drive under a key you do not
  control. Device-to-device transfer ignores `allowBackup`, so it is excluded
  separately.
- **`FLAG_SECURE`** blocks screenshots, screen recording, and the recents
  thumbnail.
- **`EXTRA_IS_SENSITIVE` on the clipboard**, so Android 13+ does not render a
  preview of a copied password, and it stays out of clipboard history and
  cross-device sync.
- **The autofill picker activity is `noHistory` and `excludeFromRecents`**, and
  sets `FLAG_SECURE` unconditionally regardless of user preference.

### iOS

- Keychain items are `first_unlock_this_device`: never synced to iCloud, never
  restored to a different device.
- The pasteboard is `localOnly` with an expiry, so Universal Clipboard does not
  carry a password to a nearby Mac.
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are false.
- No ATS exceptions, because there are no network requests to except.

---

## 4. Known limitations

These are real. They are listed here, and the relevant ones are repeated inside
the app.

### Biometric unlock is enforced by the app, not the keystore

The data key is stored in `EncryptedSharedPreferences` (Android, hardware-backed
Keystore) or the Keychain (iOS). The biometric prompt happens **before** the app
reads that entry — the ordering is enforced by Sablekey's own code, not by the
keystore.

On a device where an attacker has root or a jailbreak, that ordering can be
bypassed and the key read directly. Binding the key to
`setUserAuthenticationRequired` in the Android Keystore would close this gap and
is the main piece of hardening still outstanding.

This is why biometric unlock is **opt-in and off by default**, and why the app
says your master password is the stronger option.

### The iOS autofill mirror is a second copy

An `ASCredentialProviderViewController` must produce credentials from inside
its own process, and cannot run Argon2id or XChaCha20 (neither is in CryptoKit).
Opening the real vault there is not possible.

So enabling iOS autofill writes a **logins-only mirror**: domain, username,
password and TOTP secret, encrypted with AES-256-GCM under a Keychain key
created with `.biometryCurrentSet`.

- Reading it requires Face ID or Touch ID, enforced by the Keychain itself.
- Re-enrolling a face or finger invalidates the key, and the mirror with it.
- Notes, cards, documents, attachments and every non-login type are never
  mirrored.
- **Anyone who can pass your device biometric can read those logins without
  your master password.**

Off by default. The toggle states the number of logins involved and this exact
consequence. Turning it off, changing the master password, or erasing the vault
all destroy the key and the file.

Android does not use a mirror and never writes one.

### Screenshots cannot be blocked on iOS

There is no equivalent to `FLAG_SECURE`. Sablekey covers the window with a blur
when the app resigns active, which hides the app-switcher snapshot — the one
that persists to disk. A deliberate screenshot cannot be prevented.

### "Known password" is not a breach check

Checking a password against Have I Been Pwned requires a network request, which
this app cannot make. The health screen compares against a bundled list of the
most-guessed passwords instead, and says so on the screen. That catches the
passwords tried first, which is where most credential-stuffing damage happens —
but it is not the same thing, and is not presented as if it were.

### Strength estimation is an estimate

The zxcvbn-style estimator charges dictionary words, keyboard runs, sequences,
repeats and leet substitutions only what they really cost an attacker. It is
substantially better than counting character classes, and it is still a model.
An unusual password may be scored lower than it deserves, and a password built
on a pattern the estimator does not know may be scored higher.

### Memory zeroisation is best-effort

`SecureBytes` wipes buffers and refuses use after destruction. Dart gives no
guarantee that the garbage collector has not already copied a buffer elsewhere.
This shortens the window in which a key sits in a readable page; it does not
eliminate it.

### Two-factor codes live beside the first factor

Storing TOTP secrets in the same vault as the passwords weakens the separation
that two factors are supposed to provide. Every mainstream manager does this,
and the realistic alternative most people choose is a screenshot of the QR code
in their camera roll. It is your call; the feature is optional.

### There is no recovery

No reset link, no recovery key, no support address that can help. A recovery
path is, by construction, a second way in. If you forget the master password,
the vault is unrecoverable — which is why onboarding requires an explicit
acknowledgement rather than fine print.

**Keep a current encrypted backup**, especially before enabling panic wipe.

---

## 5. Out of scope

Sablekey does not defend against:

- **A compromised device.** Root, a jailbreak, or a keylogger defeats any
  password manager. The master password is typed on a keyboard the OS controls.
- **Physical coercion.** Panic wipe destroys data; it does not protect you.
- **A malicious build.** Build from source and verify what you install.
- **Shoulder surfing beyond the basics.** Secrets are masked by default and
  screenshots are blocked on Android; someone watching you reveal a password is
  outside what software can prevent.

---

## 6. Reporting a problem

This is a personal project without a security team. If you find a flaw, open a
GitHub issue — or, for anything you believe is exploitable, contact the
repository owner privately first.
